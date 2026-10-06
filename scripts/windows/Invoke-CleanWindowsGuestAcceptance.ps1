# Runs only inside a fresh Windows Sandbox. Uses the inbox PowerShell 5.1 and
# .NET Framework UI Automation client; no SDK, runtime or toolchain is installed.
[CmdletBinding()]
param(
    [string]$InputDirectory = 'C:\AcceptanceInput',
    [string]$OutputDirectory = 'C:\AcceptanceOutput',
    [switch]$ValidateHelpers
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Acceptance([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-AcceptanceAccountMode([string]$InputPath, [string]$OutputPath, [string]$UserName, [string]$ProfilePath, [string]$ScriptRoot) {
    if ($InputPath -ceq 'C:\AcceptanceInput') {
        Assert-Acceptance ($OutputPath -ceq 'C:\AcceptanceOutput') 'Expected the dedicated Sandbox mappings.'
        Assert-Acceptance ($UserName -ieq 'WDAGUtilityAccount') 'Production acceptance is allowed only for Windows Sandbox WDAGUtilityAccount.'
        Assert-Acceptance ($ProfilePath.TrimEnd('\') -ieq 'C:\Users\WDAGUtilityAccount') 'Unexpected Sandbox user profile.'
        return 'WDAG'
    }
    if($InputPath -cmatch '^C:\\Users\\Public\\SteamWrapperPermissionAcceptance-(?<run>[a-f0-9]{32})\\input$') {
        $run=[string]$Matches['run']
        Assert-Acceptance ($OutputPath -ceq ('C:\Users\Public\SteamWrapperPermissionAcceptance-'+$run+'\evidence') -and
            $UserName -ceq 'WDAGUtilityAccount' -and $ProfilePath.TrimEnd('\') -ieq 'C:\Users\WDAGUtilityAccount' -and $ScriptRoot -ieq $InputPath) 'The distinct permission lane requires its exact guest-local run and original WDAG native profile.'
        return 'WDAGStandardPermission'
    }
    Assert-Acceptance ($InputPath -cmatch '^C:\\Users\\Public\\SteamWrapperAcceptance-(?<run>[a-f0-9]{32})\\input$') 'Unexpected guest-local standard-account input.'
    $run=[string]$Matches['run']; $expectedName='SwAcc-' + $run.Substring(0,14)
    Assert-Acceptance ($OutputPath -ceq ('C:\Users\Public\SteamWrapperAcceptance-' + $run + '\evidence') -and
        $UserName -ceq $expectedName -and $ProfilePath.TrimEnd('\') -ieq ('C:\Users\' + $expectedName) -and
        $ScriptRoot -ieq $InputPath) 'The standard-account guest requires its exact run, native profile and sealed script root.'
    return 'StandardUser'
}
function Get-AcceptanceNumericVersion([string]$Tag) {
    $number='(?:0|[1-9][0-9]*)'; $identifier='(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    Assert-Acceptance ($Tag.Length -le 80 -and $Tag -cmatch ('^v(?<base>' + $number + '\.' + $number + '\.' + $number + ')(?:-' + $identifier + '(?:\.' + $identifier + ')*)?$')) 'Expected a strict acceptance version tag.'
    return [Version]$Matches['base']
}
function Get-AcceptanceScenario($Manifest) {
    $property=$Manifest.PSObject.Properties['scenario']
    $scenario=if ($null -eq $property) {'PublicUpgrade'} else {[string]$property.Value}
    Assert-Acceptance ($scenario -cin @('PublicUpgrade','CandidateFirstInstall','CandidateUpgrade')) 'Unexpected clean Windows acceptance scenario.'
    $baseline=Get-AcceptanceNumericVersion $Manifest.baseline.tag
    $target=Get-AcceptanceNumericVersion $Manifest.target.tag
    if ($scenario -ceq 'PublicUpgrade') {
        Assert-Acceptance ($target -gt $baseline) 'Public acceptance requires a genuine newer numeric product version.'
        if ($null -ne $Manifest.PSObject.Properties['localCandidate']) { Assert-Acceptance ($Manifest.localCandidate -is [bool] -and -not $Manifest.localCandidate) 'Public upgrade cannot use a local candidate.' }
    } else {
        Assert-Acceptance ($Manifest.localCandidate -is [bool] -and $Manifest.localCandidate -and $Manifest.sourceHeadCommit -cmatch '^[a-f0-9]{40}$' -and
            $Manifest.workingCopyDirty -is [bool] -and $Manifest.sourceHeadCommit -ceq $Manifest.target.commit) 'Candidate first install requires explicit local source provenance.'
        if ($scenario -ceq 'CandidateFirstInstall') {
            foreach($key in @('tag','fileName','bytes','sha256','commit')) { Assert-Acceptance ($Manifest.baseline.$key -ceq $Manifest.target.$key) 'Candidate first install requires two identical candidate identities.' }
        } else {
            Assert-Acceptance ($target -gt $baseline -and $Manifest.baselinePublicReleaseSha256 -cmatch '^[a-f0-9]{64}$' -and $Manifest.baselinePublicApiSha256 -cmatch '^[a-f0-9]{64}$') 'Candidate upgrade requires a genuinely older, sealed public baseline.'
        }
    }
    return $scenario
}
function Quote-AcceptanceArgument([string]$Value) {
    if ($Value.Contains('"') -or $Value.Contains("`r") -or $Value.Contains("`n")) { throw 'Unexpected command-line characters.' }
    return '"' + $Value.TrimEnd('\') + '"'
}
function Wait-Acceptance([scriptblock]$Condition, [string]$Description, [int]$Seconds = 45) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        try {
            $value = & $Condition
            if ($value) { return $value }
        } catch {
            $transient = $_.Exception.GetBaseException()
            if ($transient -isnot [System.InvalidOperationException] -and
                $transient -isnot [System.Runtime.InteropServices.COMException] -and
                $transient -isnot [System.Windows.Automation.ElementNotAvailableException]) { throw }
        }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description. No process was killed; windows and diagnostics remain."
}
function Test-AcceptanceInboxRuntimePackage($Package, [string]$SystemAppsRoot = 'C:\Windows\SystemApps') {
    foreach ($name in @('Name','Publisher','SignatureKind','NonRemovable','InstallLocation','IsFramework')) {
        if ($null -eq $Package.PSObject.Properties[$name]) { return $false }
    }
    if ($Package.Name -isnot [string] -or $Package.Name -cnotmatch '^Microsoft\.WindowsAppRuntime\.CBS(?:\.[1-9][0-9]*(?:\.[0-9]+)*)?$' -or
        $Package.Publisher -cne 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' -or
        ($Package.SignatureKind -isnot [Enum] -and $Package.SignatureKind -isnot [int] -and $Package.SignatureKind -isnot [long]) -or
        [int]$Package.SignatureKind -ne 4 -or $Package.NonRemovable -isnot [bool] -or -not $Package.NonRemovable -or
        $Package.IsFramework -isnot [bool] -or -not $Package.IsFramework -or $Package.InstallLocation -isnot [string]) { return $false }
    # CBS 1.x is named with a version but ships in the original CBS family;
    # newer CBS families retain their major identity in SystemApps. System
    # signatures and non-removability are required in addition to that path.
    $family = if ($Package.Name -cmatch '^Microsoft\.WindowsAppRuntime\.CBS\.1\.[0-9]+$') { 'Microsoft.WindowsAppRuntime.CBS' } else { $Package.Name }
    $expected = $SystemAppsRoot.TrimEnd('\') + '\' + $family + '_8wekyb3d8bbwe'
    return $Package.InstallLocation.TrimEnd('\') -ieq $expected
}
function Get-AcceptancePayloadRuntimeModules($Modules, [string]$PayloadRoot) {
    $paths = [ordered]@{}
    foreach ($name in @('Microsoft.UI.Xaml.dll','coreclr.dll')) {
        $matched = @($Modules | Where-Object { $_.ModuleName -ieq $name })
        Assert-Acceptance ($matched.Count -eq 1 -and $matched[0].FileName -ieq (Join-Path $PayloadRoot $name)) ('Manager did not load its own version payload runtime: ' + $name)
        $paths[$name] = $matched[0].FileName
    }
    return $paths
}
function Assert-AcceptanceManualAppIdAction($State, [int]$RootProcessId, [int]$ManagerProcessId) {
    $chineseName = (-join @([char]0x624b,[char]0x52a8,[char]0x586b,[char]0x5199)) + ' AppID'
    Assert-Acceptance ($ManagerProcessId -gt 0 -and $RootProcessId -eq $ManagerProcessId -and
        ($State.processId -eq 0 -or $State.processId -eq $ManagerProcessId) -and $State.automationId -ceq 'SecondaryButton' -and
        $State.name -cin @('Enter AppID manually', $chineseName) -and $State.enabled -is [bool] -and $State.enabled) ("The manual AppID action is not the expected Manager dialog. Actual Name='{0}', ProcessId={1}, root ProcessId={2}; expected Manager ProcessId={3}. See manualAppIdDialog evidence for exact UTF-16 text and provider state." -f $State.name, $State.processId, $RootProcessId, $ManagerProcessId)
}
function Retain-AcceptanceProcessHandle($Process) {
    # Kept separate so the inbox Framework attachment behavior can be tested
    # with a harmless child rather than a production Manager or UI operation.
    # Temporary handles used by MainModule/WaitForExit do not retain an
    # attached process's exit status once Windows releases its process ID.
    $handle = $Process.Handle
    Assert-Acceptance ($handle -ne [IntPtr]::Zero) 'Cannot retain the live acceptance process handle.'
}
function Get-AcceptanceExitDiagnostic($ExitCode) {
    $observed = $ExitCode -is [int]
    $unsigned = if ($observed) { if ($ExitCode -lt 0) { [long]$ExitCode + 4294967296L } else { [long]$ExitCode } } else { $null }
    return [ordered]@{ observed=$observed; exitCode=$ExitCode; unsignedExitCode=$unsigned; hexExitCode=$(if ($observed) { '0x{0:X8}' -f $unsigned } else { $null }) }
}
function Read-AcceptanceBoundedDiagnosticFile([string]$Path, [int]$MaximumBytes = 16384) {
    Assert-Acceptance ($MaximumBytes -gt 0 -and $MaximumBytes -le 16384) 'Unexpected diagnostic log read limit.'
    $result = [ordered]@{fileName=[IO.Path]::GetFileName($Path);present=$false;bytes=$null;capturedBytes=0;truncated=$false;text=$null;readError=$null}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    try {
        $file = Get-Item -LiteralPath $Path -Force
        $result.present=$true
        Assert-Acceptance (-not $file.PSIsContainer -and -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Diagnostic log is not a regular file.'
        $ancestor=Get-Item -LiteralPath $file.DirectoryName -Force
        while ($null -ne $ancestor) {
            Assert-Acceptance (-not ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Diagnostic log has a linked ancestor.'
            $ancestor=$ancestor.Parent
        }
        $stream=New-Object IO.FileStream($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $result.bytes=$stream.Length
            $buffer=New-Object byte[] $MaximumBytes
            $count=0
            while ($count -lt $MaximumBytes) {
                $read=$stream.Read($buffer,$count,($MaximumBytes - $count))
                if ($read -eq 0) { break }
                $count+=$read
            }
            $result.capturedBytes=$count; $result.truncated=$stream.Length -gt $count
            $result.text=[Text.Encoding]::UTF8.GetString($buffer,0,$count)
        } finally { $stream.Dispose() }
    } catch { $result.readError=$_.Exception.GetType().FullName }
    return $result
}

# This mode is safe on a development host. It neither reads release input nor
# runs an installer; it only exercises quoting and loads inbox UIA assemblies.
if ($ValidateHelpers) {
    $scenarioAsset=[pscustomobject]@{tag='v0.2.6';fileName='SteamWrapper-v0.2.6-win-x64-setup.exe';bytes=1;sha256=('a' * 64);commit=('b' * 40)}
    $candidateScenario=[pscustomobject]@{scenario='CandidateFirstInstall';localCandidate=$true;sourceHeadCommit=('b' * 40);workingCopyDirty=$true;baseline=$scenarioAsset;target=$scenarioAsset}
    Assert-Acceptance ((Get-AcceptanceScenario $candidateScenario) -ceq 'CandidateFirstInstall') 'Inbox candidate scenario validation failed.'
    $publicScenario=[pscustomobject]@{baseline=[pscustomobject]@{tag='v0.2.4-preview.1'};target=[pscustomobject]@{tag='v0.2.6'}}
    Assert-Acceptance ((Get-AcceptanceScenario $publicScenario) -ceq 'PublicUpgrade') 'Inbox public upgrade scenario validation failed.'
    $unicodePath = 'C:\fixture ' + [char]0x4e2d + [char]0x6587
    Assert-Acceptance ((Quote-AcceptanceArgument ($unicodePath + '\')) -ceq ('"' + $unicodePath + '"')) 'Unicode argument quoting failed.'
    $rejected = $false
    try { $null = Quote-AcceptanceArgument 'C:\unexpected"path' } catch { $rejected = $true }
    Assert-Acceptance $rejected 'An unsafe argument was accepted.'
    $inbox = [pscustomobject]@{ Name='Microsoft.WindowsAppRuntime.CBS.2'; Publisher='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'; SignatureKind=4; NonRemovable=$true; IsFramework=$true; InstallLocation='C:\Windows\SystemApps\Microsoft.WindowsAppRuntime.CBS.2_8wekyb3d8bbwe' }
    Assert-Acceptance (Test-AcceptanceInboxRuntimePackage $inbox) 'Inbox CBS runtime classification failed.'
    $inbox.InstallLocation='C:\Program Files\WindowsApps\Microsoft.WindowsAppRuntime.CBS.2_8wekyb3d8bbwe'
    Assert-Acceptance (-not (Test-AcceptanceInboxRuntimePackage $inbox)) 'An external CBS runtime was accepted.'
    $runtimeRoot='C:\fixture\versions\v0.2.6'
    $modules=@([pscustomobject]@{ModuleName='Microsoft.UI.Xaml.dll';FileName=(Join-Path $runtimeRoot 'Microsoft.UI.Xaml.dll')},[pscustomobject]@{ModuleName='coreclr.dll';FileName=(Join-Path $runtimeRoot 'coreclr.dll')})
    $null = Get-AcceptancePayloadRuntimeModules $modules $runtimeRoot
    $manual = [pscustomobject]@{name='Enter AppID manually';processId=0;automationId='SecondaryButton';enabled=$true}
    Assert-AcceptanceManualAppIdAction $manual 1900 1900
    $rejected=$false
    try { Assert-AcceptanceManualAppIdAction $manual 1800 1900 } catch { $rejected=$true }
    Assert-Acceptance $rejected 'An anonymous child was accepted beneath a foreign root.'
    $helperRoot = Join-Path $env:TEMP ('SteamWrapperCleanHelpers-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($helperRoot) | Out-Null
    $exitFixture = Join-Path $helperRoot 'ExitFixture.exe'
    Add-Type -TypeDefinition @'
public static class SteamWrapperExitObservationFixture {
    public static int Main() { System.Threading.Thread.Sleep(800); return 7; }
}
'@ -OutputAssembly $exitFixture -OutputType ConsoleApplication
    $exitObservations = [ordered]@{ expectedExitCode=7; unretainedExitCode=$null; retainedExitCode=$null; originalExitCode=$null }
    foreach ($retain in @($false,$true)) {
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$exitFixture; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $original = [Diagnostics.Process]::Start($start)
        $attached = [Diagnostics.Process]::GetProcessById($original.Id)
        try {
            if ($retain) { Retain-AcceptanceProcessHandle $attached }
            $null = $attached.MainModule.FileName
            $null = $attached.WorkingSet64
            Assert-Acceptance ($attached.WaitForExit(5000)) 'Harmless exit fixture did not finish; it was not killed.'
            $actual = $attached.ExitCode
            if ($retain) {
                $exitObservations.retainedExitCode=$actual
                $exitObservations.originalExitCode=$original.ExitCode
                Assert-Acceptance ($actual -is [int] -and $actual -eq 7 -and $original.ExitCode -eq 7) 'Retained inbox Framework attachment lost the harmless child actual exit code.'
            } else { $exitObservations.unretainedExitCode=$actual }
        } finally { $attached.Dispose(); $original.Dispose() }
    }
    $boundedLog=Join-Path $helperRoot 'bounded-diagnostic.log'
    [IO.File]::WriteAllText($boundedLog,('A' * 32768))
    $logDiagnostic=Read-AcceptanceBoundedDiagnosticFile $boundedLog 16
    Assert-Acceptance ($logDiagnostic.capturedBytes -eq 16 -and $logDiagnostic.truncated -and $logDiagnostic.text.Length -eq 16) 'Inbox bounded diagnostic file capture failed.'
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    [ordered]@{
        passed = $true
        productionInstallerExecuted = $false
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        uiaAssembly = [System.Windows.Automation.AutomationElement].Assembly.Location
        inboxRuntimeClassifier = $true; payloadRuntimeModulesValidator = $true
        manualAppIdProviderValidator = $true
        processExitObservation = $exitObservations
        boundedDiagnosticLogCapture = $true
    } | ConvertTo-Json
    return
}

# Fail closed before making any directory, changing registration or executing
# product bytes. The two mapped folders alone are not proof of a clean guest.
$accountMode=Get-AcceptanceAccountMode $InputDirectory $OutputDirectory $env:USERNAME $env:USERPROFILE $PSScriptRoot
$permissionAccount=$accountMode -ceq 'WDAGStandardPermission'
$standardAccount=$accountMode -cin @('StandardUser','WDAGStandardPermission')
Assert-Acceptance ([Environment]::UserInteractive -and [Diagnostics.Process]::GetCurrentProcess().SessionId -ne 0) 'An interactive Sandbox desktop is required.'
$manifestPath = Join-Path $InputDirectory 'acceptance-input.json'
$inputManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-Acceptance ($inputManifest.schemaVersion -eq 1 -and $inputManifest.sandboxOnly -eq $true -and $inputManifest.networkingDisabled -eq $true) 'Expected the offline Sandbox input manifest.'
$scenario=Get-AcceptanceScenario $inputManifest
$localCandidate=$scenario -cne 'PublicUpgrade'
$candidateUpgrade=$scenario -ceq 'CandidateUpgrade'
$runId = [guid]::Parse([string]$inputManifest.runId).ToString('N')
Assert-Acceptance (-not [string]::IsNullOrWhiteSpace([string]$inputManifest.hostComputerName) -and $env:COMPUTERNAME -ine $inputManifest.hostComputerName) 'Refusing to execute a production installer on the input host.'
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
Assert-Acceptance ($computer.Manufacturer -eq 'Microsoft Corporation' -and $computer.Model -eq 'Virtual Machine') 'The guest is not the expected Microsoft virtual machine.'
Assert-Acceptance ($os.ProductType -eq 1 -and [int]$os.BuildNumber -ge 26100 -and [Environment]::Is64BitProcess) 'A native x64 Windows 11 24H2-or-later client is required.'
Assert-Acceptance (Test-Path -LiteralPath $OutputDirectory -PathType Container) 'The dedicated output mapping is missing.'
foreach ($name in @('STEAMWRAPPER_E2E_ROOT', 'STEAMWRAPPER_DEPLOYMENT_TEST', 'STEAM_DIR')) {
    Assert-Acceptance ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) "Unexpected test environment override: $name"
}
Assert-Acceptance (@(Get-ChildItem Env: | Where-Object Name -like 'STEAMWRAPPER_DEPLOYMENT_*').Count -eq 0) 'An installed-launch override was supplied.'
Assert-Acceptance ($env:LOCALAPPDATA -ieq [Environment]::GetFolderPath('LocalApplicationData')) 'AppData is redirected.'
$standardContext=$null
if ($standardAccount) {
    $standardHelper=Get-Item -LiteralPath (Join-Path $InputDirectory 'StandardUserAcceptance.ps1') -Force
    Assert-Acceptance ($standardHelper -is [IO.FileInfo] -and $standardHelper.Length -gt 0 -and $standardHelper.Length -le 2MB -and
        -not ($standardHelper.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        $inputManifest.standardControllerSha256 -cmatch '^[a-f0-9]{64}$' -and
        (Get-FileHash -LiteralPath $standardHelper.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $inputManifest.standardControllerSha256) 'The guest-local standard-account helper changed.'
    . $standardHelper.FullName -HelpersOnly
    $standardContext=Get-StandardAcceptanceContext
    $standardContext | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue ([SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($env:USERNAME))
    Assert-StandardAcceptanceScopedChildContext $standardContext $inputManifest $InputDirectory $OutputDirectory
    Assert-StandardAcceptanceRegularPath $InputDirectory $true
    Assert-StandardAcceptanceRegularPath $OutputDirectory $true
}

$dataRoot = Join-Path $env:LOCALAPPDATA 'SteamWrapper'
$defaultProgram = Join-Path $env:LOCALAPPDATA 'Programs\SteamWrapper'
# Keep this script ASCII so inbox PowerShell 5.1 does not reinterpret UTF-8
# source literals using the system ANSI code page.
$chineseWord = [string][char]0x4e2d + [char]0x6587
$chineseManualButton = (-join @([char]0x624b, [char]0x52a8, [char]0x586b, [char]0x5199)) + ' AppID'
$profileName = 'Clean Windows fixture ' + $chineseWord
$customProgram = Join-Path $env:USERPROFILE ('Apps\SteamWrapper ' + $chineseWord)
$registration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1'
Assert-Acceptance (-not (Test-Path -LiteralPath $dataRoot) -and -not (Test-Path -LiteralPath $defaultProgram) -and -not (Test-Path -LiteralPath $customProgram) -and -not (Test-Path -LiteralPath $registration)) 'The Sandbox already contains SteamWrapper; start a fresh instance.'
Assert-Acceptance (@(Get-Process -Name steam, SteamWrapper, SteamWrapper.Manager, SteamWrapperRunner -ErrorAction SilentlyContinue).Count -eq 0) 'The guest already has Steam or SteamWrapper processes.'
Assert-Acceptance (-not (Test-Path -LiteralPath 'HKCU:\Software\Valve\Steam') -and
    -not (Test-Path -LiteralPath 'C:\Program Files (x86)\Steam')) 'The guest already has a Steam installation.'
$existingOutput = @(Get-ChildItem -LiteralPath $OutputDirectory -Force)
Assert-Acceptance (@($existingOutput | Where-Object {
    $_ -isnot [IO.FileInfo] -or
        ($_.Name -cne 'guest-launch.log' -and (-not $standardAccount -or $_.Name -cne 'standard-user-diagnostic.json')) -or
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
}).Count -eq 0) 'Use a fresh acceptance output folder containing at most its new guest-launch.log.'
if ($standardAccount) {
    $diagnosticPath=Join-Path $OutputDirectory 'standard-user-diagnostic.json'
    Assert-StandardAcceptanceRegularPath $diagnosticPath $false
    Assert-Acceptance ((Get-Item -LiteralPath $diagnosticPath).Length -le 65536) 'The standard-account prelude exceeds its read limit.'
    $prelude=Get-Content -LiteralPath $diagnosticPath -Raw | ConvertFrom-Json
    Assert-Acceptance ($prelude.runId -ceq $runId -and $prelude.result -ceq 'passed' -and $prelude.standardAccount -is [bool] -and $prelude.standardAccount -and
        $prelude.desktop.windowStation -ceq 'WinSta0' -and $prelude.desktop.name -ceq 'Default' -and
        $prelude.desktop.inputDesktopReadable -is [bool] -and $prelude.desktop.inputDesktopReadable) 'The exact standard-account token/desktop prelude did not pass.'
    Assert-StandardAcceptanceScopedChildContext $prelude.context $inputManifest $InputDirectory $OutputDirectory
}

$taskRoot = Join-Path $env:TEMP ('SteamWrapperClean-' + $runId)
Assert-Acceptance (-not (Test-Path -LiteralPath $taskRoot)) 'The guest work directory is not fresh.'
$events = New-Object 'System.Collections.Generic.List[object]'
$ownedManagers = New-Object 'System.Collections.Generic.List[object]'
$managerCloseDiagnostics = New-Object 'System.Collections.Generic.List[object]'
$runnerDiagnostics = New-Object 'System.Collections.Generic.List[object]'
$warnings = New-Object 'System.Collections.Generic.List[string]'
$evidence = [ordered]@{
    schemaVersion = 1; runId = $runId; result = 'running'; startedAt = [DateTime]::UtcNow.ToString('o')
    environment = 'Windows Sandbox'; cleanWindowsClient = $true; independentIsoVm = $false
    build = [string]$os.BuildNumber; caption = [string]$os.Caption; osVersion = [string]$os.Version
    hostBuild = [string]$inputManifest.hostBuild; computerName = $env:COMPUTERNAME
    userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    administrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    accountMode=$accountMode; standardAccount=$standardAccount; standardAccountContext=$standardContext
    freshStandardAccount=($accountMode -ceq 'StandardUser'); permissionAccount=$permissionAccount; primaryStandardSignInTested=$false; twoUserGuiTested=$false
    uiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name; powerShellVersion = $PSVersionTable.PSVersion.ToString()
    nativeDataRoot = $dataRoot; baseline = $inputManifest.baseline; target = $inputManifest.target
    runtimeInventoryBeforeInstallation = $null; externalSdkOrRuntimeInstalled = $false
    realSteamInstalled = $false; productionInstallers = $true; testEnvironmentOverrides = $false
    publicUpdateNetworkTested = $false; networkingDisabled = $true
    scenario=$scenario; localCandidate=$localCandidate; unpublishedCandidate=$localCandidate; numericUpgradeTested=$false; publicSevenAssetsTested=$false
    baselinePublic=($scenario -cne 'CandidateFirstInstall'); stableRunnerUpdated=$false; baselineRunnerOperationalTested=$false
    sourceHeadCommit=$(if ($localCandidate) {$inputManifest.sourceHeadCommit} else {$null}); workingCopyDirty=$(if ($localCandidate) {$inputManifest.workingCopyDirty} else {$null})
    candidateInstallerBuild=$(if ($localCandidate) {$inputManifest.candidateInstallerBuild} else {$null})
    steps = $events; ownedManagers = $ownedManagers; warnings = $warnings; managerCloseDiagnostics = $managerCloseDiagnostics; runnerDiagnostics = $runnerDiagnostics
}
$evidencePath = Join-Path $OutputDirectory 'evidence.json'
$utf8 = New-Object Text.UTF8Encoding($false)
function Write-AcceptanceEvidence {
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 14), $utf8)
}
function Record-Acceptance([string]$Name, $Details) {
    $events.Add([ordered]@{ name = $Name; passed = $true; observedAt = [DateTime]::UtcNow.ToString('o'); details = $Details })
    Write-AcceptanceEvidence
}
function Get-AcceptanceProcessSecurity($Process) {
    if (-not $standardAccount) { return $null }
    $token=[SteamWrapperStandardAcceptance.Native]::GetToken($Process.Id)
    Assert-StandardAcceptanceProcessToken $token $inputManifest.expectedStandardUserSid
    if($permissionAccount){Assert-StandardPermissionPrivileges $token}
    Assert-Acceptance ($token.sessionId -eq $standardContext.sessionId) 'A product process escaped the verified standard-account desktop session.'
    if($null -ne $inputManifest.PSObject.Properties['standardExpectedLogonSid']) {
        Assert-Acceptance ($token.logonSid -ceq $inputManifest.standardExpectedLogonSid) 'A product process escaped the exact verified standard-account logon.'
    }
    return [ordered]@{processId=$Process.Id;observed=$true;token=$token}
}
function Read-AcceptanceAsset($Asset) {
    $number = '(?:0|[1-9][0-9]*)'
    $identifier = '(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    $tagPattern = '^v' + $number + '\.' + $number + '\.' + $number + '(?:-' + $identifier + '(?:\.' + $identifier + ')*)?$'
    Assert-Acceptance ([string]$Asset.tag -cmatch $tagPattern -and ([string]$Asset.tag).Length -le 80 -and $Asset.fileName -ceq ('SteamWrapper-' + $Asset.tag + '-win-x64-setup.exe')) 'Installer filename/tag disagree.'
    Assert-Acceptance ([string]$Asset.sha256 -cmatch '^[a-f0-9]{64}$' -and [long]$Asset.bytes -gt 0 -and [long]$Asset.bytes -le 512MB) 'Unexpected installer digest or size.'
    $path = Join-Path $InputDirectory $Asset.fileName
    $file = Get-Item -LiteralPath $path
    Assert-Acceptance (-not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $file.Length -eq [long]$Asset.bytes) 'Installer size or file type changed.'
    Assert-Acceptance ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Asset.sha256) 'Installer hash changed after host staging.'
    $destination = Join-Path $taskRoot $file.Name
    Copy-Item -LiteralPath $path -Destination $destination
    Assert-Acceptance ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Asset.sha256) 'The guest installer copy changed.'
    return $destination
}
function Invoke-AcceptanceInstaller([string]$Executable, [string]$Name, [string[]]$Additional = @()) {
    $log = Join-Path $OutputDirectory ($Name + '.log')
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/LANG=english', ('/LOG=' + (Quote-AcceptanceArgument $log))) + $Additional
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.Arguments = $arguments -join ' '
    $process = [Diagnostics.Process]::Start($start)
    try {
        $processSecurity=Get-AcceptanceProcessSecurity $process
        Assert-Acceptance ($process.WaitForExit(180000)) "$Name did not exit. It was not killed."
        Assert-Acceptance ($process.ExitCode -eq 0) "$Name exited with code $($process.ExitCode). See its preserved log."
        Record-Acceptance $Name ([ordered]@{ actualInstaller = $true; silentInstaller = $true; exitCode = $process.ExitCode; log = [IO.Path]::GetFileName($log); executable = $Executable; processSecurity=$processSecurity })
    } finally { $process.Dispose() }
}
function Read-AcceptanceInstallation([string]$Program, [string]$Tag) {
    $state = Get-Content -LiteralPath (Join-Path $Program 'installation.json') -Raw | ConvertFrom-Json
    Assert-Acceptance ($state.schemaVersion -eq 1 -and $state.appId -ceq 'SteamWrapper' -and $state.current.tag -ceq $Tag) 'Installation activated an unexpected product/version.'
    $registered = (Get-ItemProperty -LiteralPath $registration).InstallLocation.TrimEnd('\')
    Assert-Acceptance ($registered -ieq $Program) 'The per-user registered installation location is incorrect.'
    return $state
}
function Get-AcceptanceFirstInstallSize([string]$Program) {
    $pending=New-Object 'Collections.Generic.Stack[IO.DirectoryInfo]'
    $root=Get-Item -LiteralPath $Program -Force
    Assert-Acceptance ($root -is [IO.DirectoryInfo] -and -not ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'The fresh installed size root is not a regular directory.'
    $pending.Push($root);$count=0;$bytes=0L;$entries=0
    while($pending.Count -gt 0) {
        foreach($item in $pending.Pop().GetFileSystemInfos()) {
            $entries++;Assert-Acceptance ($entries -le 5000 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Refusing a linked or unbounded fresh installed-size tree.'
            if($item -is [IO.DirectoryInfo]){$pending.Push($item)}else{$count++;$bytes+=$item.Length;Assert-Acceptance ($bytes -le 512MB) 'Fresh installed program size exceeded its bounded measurement.'}
        }
    }
    return [ordered]@{installationRoot=$Program;fileCount=$count;bytes=$bytes;includesMaintenanceAndUninstaller=$true;freshBeforeUnknownFixtures=$true;dataRootIncluded=$false}
}
function Get-AcceptanceDataHashes {
    $hashes = [ordered]@{}
    foreach ($relative in @('profiles.toml', 'ui-settings.json', 'bin\SteamWrapperRunner.exe', 'bin\runner-manifest.json')) {
        $path = Join-Path $dataRoot $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { $hashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return $hashes
}
function Assert-AcceptanceDataHashes($Expected) {
    foreach ($entry in $Expected.GetEnumerator()) {
        $path = Join-Path $dataRoot $entry.Key
        Assert-Acceptance ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $entry.Value) "Player fixture data changed: $($entry.Key)"
    }
}
function Get-AcceptanceShortcuts {
    return @((Join-Path ([Environment]::GetFolderPath('Programs')) 'SteamWrapper\SteamWrapper.lnk'), (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'SteamWrapper.lnk'))
}
function Assert-AcceptanceShortcuts([string]$Program, [bool]$Present) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($path in Get-AcceptanceShortcuts) {
        Assert-Acceptance ((Test-Path -LiteralPath $path) -eq $Present) "Shortcut presence differs: $path"
        if ($Present) { Assert-Acceptance ($shell.CreateShortcut($path).TargetPath -ieq (Join-Path $Program 'SteamWrapper.exe')) 'A shortcut does not target the installed native launcher.' }
    }
}
function Find-AcceptanceElement($Window, [string]$Id) {
    return $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)))
}
function Wait-AcceptanceElement($Window, [string]$Id) {
    return Wait-Acceptance { Find-AcceptanceElement $Window $Id } ('UI element ' + $Id)
}
function Invoke-AcceptanceElement($Element) {
    Assert-Acceptance $Element.Current.IsEnabled 'The requested UI action is disabled.'
    ([System.Windows.Automation.InvokePattern]$Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
    Start-Sleep -Milliseconds 200
}
function Set-AcceptanceValue($Window, [string]$Id, [string]$Value) {
    $element = Wait-AcceptanceElement $Window $Id
    ([System.Windows.Automation.ValuePattern]$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).SetValue($Value)
    $null = Wait-Acceptance { ([System.Windows.Automation.ValuePattern]$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $Value } ('edited ' + $Id)
    Start-Sleep -Milliseconds 150
}
function Capture-AcceptanceWindow($Window, [string]$Name) {
    try {
        $bounds = $Window.Current.BoundingRectangle
        Assert-Acceptance ($bounds.Width -gt 0 -and $bounds.Height -gt 0 -and $bounds.Width -le 4096 -and $bounds.Height -le 4096) 'Unexpected window screenshot dimensions.'
        $bitmap = New-Object Drawing.Bitmap([int]$bounds.Width, [int]$bounds.Height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
            $bitmap.Save((Join-Path $OutputDirectory ($Name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    } catch { $warnings.Add('Screenshot unavailable: ' + $_.Exception.Message) }
}
function Start-AcceptanceManager([string]$Program, [string]$Tag, [string]$Name) {
    $expected = Join-Path $Program ('versions\' + $Tag + '\SteamWrapper.Manager.exe')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $shellSmoke=$standardAccount -and $Name -ceq 'baseline-manager-first-launch' -and
        $null -ne $inputManifest.PSObject.Properties['standardExplorerShortcut'] -and $inputManifest.standardExplorerShortcut -eq $true
    $installedShortcutSmoke=$standardAccount -and $Name -ceq 'baseline-manager-first-launch' -and
        $null -ne $inputManifest.PSObject.Properties['standardInstalledShortcut'] -and $inputManifest.standardInstalledShortcut -eq $true
    Assert-Acceptance (-not ($shellSmoke -and $installedShortcutSmoke)) 'The separate shortcut and Explorer acceptance lanes cannot be combined.'
    if($shellSmoke) {
        $shellLaunch=Start-StandardAcceptanceExplorerManager $standardContext $inputManifest $Program $Tag
        $manager=$shellLaunch.Process
        $evidence['standardExplorerShortcut']=$shellLaunch.Observation
        Write-AcceptanceEvidence
    } elseif($installedShortcutSmoke) {
        $shellLaunch=Start-StandardAcceptanceInstalledShortcutManager $standardContext $inputManifest $Program $Tag
        $manager=$shellLaunch.Process
        $evidence['standardInstalledShortcut']=$shellLaunch.Observation
        $evidence['shellRoute']='standard-token installed shortcut';$evidence['ordinaryExplorerTested']=$false
        Write-AcceptanceEvidence
    } else {
        $launcherStart = New-Object Diagnostics.ProcessStartInfo
        $launcherStart.FileName = Join-Path $Program 'SteamWrapper.exe'; $launcherStart.WorkingDirectory = $Program; $launcherStart.UseShellExecute = $true
        $launcher = [Diagnostics.Process]::Start($launcherStart)
        if ($null -ne $launcher) { $launcher.Dispose() }
        $manager = Wait-Acceptance {
        foreach ($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')) {
            try {
                if ($candidate.MainModule.FileName -ieq $expected -and $candidate.MainWindowHandle -ne [IntPtr]::Zero) { Retain-AcceptanceProcessHandle $candidate; return $candidate }
            } catch { }
            $candidate.Dispose()
        }
        } ('normal installed Manager window: ' + $Name) 60
    }
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($manager.MainWindowHandle)
    Assert-Acceptance ($window.Current.ProcessId -eq $manager.Id) 'The UI window is not owned by the installed Manager.'
    $null = Wait-Acceptance { $button = Find-AcceptanceElement $window 'AddGame'; $button -and $button.Current.IsEnabled } 'Manager initialization'
    $manager.Refresh()
    $runtimeModules = Get-AcceptancePayloadRuntimeModules @($manager.Modules) ([IO.Path]::GetDirectoryName($expected))
    $processSecurity=Get-AcceptanceProcessSecurity $manager
    $timer.Stop()
    $ownedManagers.Add([ordered]@{ processId = $manager.Id; path = $expected; normalLauncher = $true })
    Capture-AcceptanceWindow $window $Name
    Record-Acceptance $Name ([ordered]@{ processId = $manager.Id; executable = $expected; processStartupMilliseconds = $timer.ElapsedMilliseconds; startupWorkingSetBytes = $manager.WorkingSet64; addGameName = (Find-AcceptanceElement $window 'AddGame').Current.Name; payloadRuntimeModules = $runtimeModules; processSecurity=$processSecurity })
    return [pscustomobject]@{ Process = $manager; Window = $window }
}
function Close-AcceptanceManager($Manager) {
    Assert-Acceptance ($Manager.Window.Current.ProcessId -eq $Manager.Process.Id) 'Refusing to close a foreign window.'
    ([System.Windows.Automation.WindowPattern]$Manager.Window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).Close()
    Assert-Acceptance ($Manager.Process.WaitForExit(45000)) 'Manager did not close normally; it was not killed.'
    $diagnostic = Get-AcceptanceExitDiagnostic $Manager.Process.ExitCode
    $managerCloseDiagnostics.Add([ordered]@{processId=$Manager.Process.Id;normalCloseRequested=$true;waitForExitSucceeded=$true;exit=$diagnostic;observer='retained inbox Framework Process handle'})
    Write-AcceptanceEvidence
    Assert-Acceptance ($diagnostic.observed -and $diagnostic.exitCode -eq 0) ("Manager did not report a successful normal exit. Observed={0}, signed ExitCode={1}, unsigned ExitCode={2}, hex ExitCode={3}. See managerCloseDiagnostics evidence." -f $diagnostic.observed, $diagnostic.exitCode, $diagnostic.unsignedExitCode, $diagnostic.hexExitCode)
    $Manager.Process.Dispose()
}
function Invoke-AcceptanceRunner([string]$Name, [string]$Marker, [string]$ExpectedWorkingDirectory) {
    Assert-Acceptance (@(Get-Process -Name SteamWrapper.Manager -ErrorAction SilentlyContinue).Count -eq 0) 'Manager must be closed before headless Runner acceptance.'
    if (Test-Path -LiteralPath $Marker) { [IO.File]::Delete($Marker) }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $dataRoot 'bin\SteamWrapperRunner.exe'; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.Arguments = '--appid "487" -- "unused original Steam command"'
    $runner = [Diagnostics.Process]::Start($start)
    try {
        $processSecurity=Get-AcceptanceProcessSecurity $runner
        $waitSucceeded=$runner.WaitForExit(30000)
        $exit=Get-AcceptanceExitDiagnostic $(if ($waitSucceeded) { $runner.ExitCode } else { $null })
        $logs=@(
            (Read-AcceptanceBoundedDiagnosticFile (Join-Path $dataRoot 'logs\runner-487.log')),
            (Read-AcceptanceBoundedDiagnosticFile (Join-Path $dataRoot 'logs\manager-startup.log'))
        )
        $runnerDiagnostics.Add([ordered]@{name=$Name;processId=$runner.Id;stablePath=$start.FileName;waitSucceeded=$waitSucceeded;exit=$exit;diagnosticLogs=$logs;perLogCaptureLimitBytes=16384;gameMarkerPresent=(Test-Path -LiteralPath $Marker -PathType Leaf)})
        Write-AcceptanceEvidence
        Assert-Acceptance ($waitSucceeded -and $exit.observed -and $exit.exitCode -eq 0) ("Headless Runner failed or did not wait for the fixture. WaitSucceeded={0}, observed ExitCode={1}, signed ExitCode={2}, unsigned ExitCode={3}, hex ExitCode={4}. See runnerDiagnostics evidence; no process was killed." -f $waitSucceeded, $exit.observed, $exit.exitCode, $exit.unsignedExitCode, $exit.hexExitCode)
        Assert-Acceptance ((Test-Path -LiteralPath $Marker) -and [IO.File]::ReadAllText($Marker) -ceq $ExpectedWorkingDirectory) 'Runner did not execute the configured native test program in its game folder.'
        Assert-Acceptance (@(Get-Process -Name SteamWrapper.Manager -ErrorAction SilentlyContinue).Count -eq 0) 'Runner unexpectedly opened Manager.'
        Record-Acceptance $Name ([ordered]@{ exitCode = $runner.ExitCode; stablePath = $start.FileName; managerClosed = $true; harmlessProgramCompleted = $true; realSteam = $false; processSecurity=$processSecurity })
    } finally { $runner.Dispose() }
}

try {
    [IO.Directory]::CreateDirectory($taskRoot) | Out-Null
    $framework = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    $dotnetDirectories = @('C:\Program Files\dotnet', 'C:\Program Files (x86)\dotnet', (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet')) | Where-Object { Test-Path -LiteralPath $_ }
    $appRuntimePackages = @(Get-AppxPackage -Name '*WindowsAppRuntime*' -ErrorAction SilentlyContinue | Select-Object Name, Version, Publisher, SignatureKind, NonRemovable, InstallLocation, IsFramework)
    $inboxRuntimePackages = @($appRuntimePackages | Where-Object { Test-AcceptanceInboxRuntimePackage $_ (Join-Path $env:windir 'SystemApps') })
    $externalRuntimePackages = @($appRuntimePackages | Where-Object { -not (Test-AcceptanceInboxRuntimePackage $_ (Join-Path $env:windir 'SystemApps')) })
    $evidence.runtimeInventoryBeforeInstallation = [ordered]@{
        dotnetDirectories = @($dotnetDirectories); dotnetOnPath = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
        windowsAppRuntimePackages = $appRuntimePackages; netFrameworkRelease = $(if ($null -ne $framework) { $framework.Release } else { $null })
        inboxWindowsAppRuntimePackages = $inboxRuntimePackages; externalWindowsAppRuntimePackages = $externalRuntimePackages
        systemVCRuntime = @(@('vcruntime140.dll','vcruntime140_1.dll') | ForEach-Object {
            $path=Join-Path (Join-Path $env:windir 'System32') $_
            $item=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
            [ordered]@{name=$_;path=$path;present=($null -ne $item);bytes=$(if ($null -ne $item) {$item.Length} else {$null});fileVersion=$(if ($null -ne $item) {$item.VersionInfo.FileVersion} else {$null});productVersion=$(if ($null -ne $item) {$item.VersionInfo.ProductVersion} else {$null})}
        })
    }
    Assert-Acceptance (@($dotnetDirectories).Count -eq 0 -and -not $evidence.runtimeInventoryBeforeInstallation.dotnetOnPath -and $externalRuntimePackages.Count -eq 0) 'The guest already contains a machine .NET runtime/SDK or an external Windows App Runtime; start a pristine Sandbox.'
    Record-Acceptance 'fresh offline Windows client' ([ordered]@{ productAbsent = $true; sdkAbsent = $true; steamAbsent = $true; nativeAppData = $true })
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
    $baselineSetup = Read-AcceptanceAsset $inputManifest.baseline
    $targetSetup = if ($scenario -ceq 'CandidateFirstInstall') {$baselineSetup} else {Read-AcceptanceAsset $inputManifest.target}
    $digestStep=if ($localCandidate) {'unpublished local candidate installer digest verified in guest'} else {'public production installer digests verified in guest'}
    Record-Acceptance $digestStep ([ordered]@{ baselineSha256 = $inputManifest.baseline.sha256; targetSha256 = $inputManifest.target.sha256; localCandidate=$localCandidate })
    if ($localCandidate) {
        foreach($record in @(
            @{name='installer-build.json';hash=$inputManifest.candidateBuildSha256},
            @{name='deployment-manifest.json';hash=$inputManifest.candidateDeploymentManifestSha256}
        )) {
            $item=Get-Item -LiteralPath (Join-Path $InputDirectory $record.name)
            Assert-Acceptance ($item.Length -gt 0 -and $item.Length -le 2MB -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $record.hash) 'The sealed candidate build record changed.'
        }
    }
    if ($candidateUpgrade) {
        foreach($record in @(
            @{name='baseline-release.json';hash=$inputManifest.baselinePublicReleaseSha256},
            @{name='baseline-api.json';hash=$inputManifest.baselinePublicApiSha256}
        )) {
            $item=Get-Item -LiteralPath (Join-Path $InputDirectory $record.name)
            Assert-Acceptance ($item.Length -gt 0 -and $item.Length -le 2MB -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $record.hash) 'The sealed public baseline source record changed.'
        }
        $evidence.baselineRunnerOperationalTested=$false
        $evidence.baselineRunnerLimitation='The historical baseline Runner is not exercised; its missing-VC loader defect is separately recorded. This lane verifies the actual upgrade and updated Runner.'
    }

    $gameDirectory = Join-Path $taskRoot ('Harmless game ' + $chineseWord)
    [IO.Directory]::CreateDirectory($gameDirectory) | Out-Null
    $fixtureExe = Join-Path $gameDirectory 'AcceptanceFixture.exe'
    # This is an inbox .NET Framework compiler producing a disposable test app,
    # never a product build or an external SDK/runtime installation.
    Add-Type -TypeDefinition @'
public static class SteamWrapperCleanFixture {
    public static int Main() {
        System.Threading.Thread.Sleep(300);
        System.IO.File.WriteAllText("runner-completed.txt", System.Environment.CurrentDirectory,
            new System.Text.UTF8Encoding(false));
        return 0;
    }
}
'@ -OutputAssembly $fixtureExe -OutputType ConsoleApplication
    $fixtureHash = (Get-FileHash -LiteralPath $fixtureExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $marker = Join-Path $gameDirectory 'runner-completed.txt'
    Record-Acceptance 'inbox Framework harmless fixture created' ([ordered]@{ file = $fixtureExe; sha256 = $fixtureHash; externalToolchainInstalled = $false })

    # The older production installer has a fixed default directory. Do not
    # pretend it supports the target release's new directory picker.
    Invoke-AcceptanceInstaller $baselineSetup 'baseline-first-install' @('/TASKS="startmenuicon,desktopicon"')
    $null = Read-AcceptanceInstallation $defaultProgram $inputManifest.baseline.tag
    $evidence['firstInstalledProgramSize']=Get-AcceptanceFirstInstallSize $defaultProgram
    Write-AcceptanceEvidence
    Assert-AcceptanceShortcuts $defaultProgram $true
    $manager = Start-AcceptanceManager $defaultProgram $inputManifest.baseline.tag 'baseline-manager-first-launch'
    $window = $manager.Window
    Invoke-AcceptanceElement (Wait-AcceptanceElement $window 'AddGame')
    $manual = Wait-AcceptanceElement $window 'SecondaryButton'
    $manualName = [string]$manual.Current.Name
    $manualState = [ordered]@{
        name = $manualName; processId = [int]$manual.Current.ProcessId; rootProcessId = $window.Current.ProcessId
        expectedProcessId = $manager.Process.Id; expectedNames = @('Enter AppID manually', $chineseManualButton)
        nameCodeUnits = @($manualName.ToCharArray() | ForEach-Object { [int]$_ })
        automationId = $manual.Current.AutomationId; enabled = $manual.Current.IsEnabled; offscreen = $manual.Current.IsOffscreen
    }
    $evidence['manualAppIdDialog'] = $manualState
    Write-AcceptanceEvidence
    Assert-AcceptanceManualAppIdAction $manualState $window.Current.ProcessId $manager.Process.Id
    Invoke-AcceptanceElement $manual
    $null = Wait-AcceptanceElement $window 'AppId'
    Set-AcceptanceValue $window 'ProfileName' $profileName
    Set-AcceptanceValue $window 'AppId' '487'
    Set-AcceptanceValue $window 'GameDirectory' $gameDirectory
    Set-AcceptanceValue $window 'Target' 'AcceptanceFixture.exe'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $window 'SaveProfile')
    $launch = Wait-AcceptanceElement $window 'LaunchOptions'
    $null = Wait-Acceptance { (Find-AcceptanceElement $window 'SaveProfile').Current.IsEnabled } 'profile save completion'
    $expectedLaunch = '"' + (Join-Path $dataRoot 'bin\SteamWrapperRunner.exe') + '" --appid "487" -- %command%'
    Assert-Acceptance (([System.Windows.Automation.ValuePattern]$launch.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $expectedLaunch) 'Saved launch options do not reference the shared stable Runner.'
    $runnerManifest = Get-Content -LiteralPath (Join-Path $dataRoot 'bin\runner-manifest.json') -Raw | ConvertFrom-Json
    Assert-Acceptance ($runnerManifest.contractVersion -eq 2 -and (Get-FileHash -LiteralPath (Join-Path $dataRoot 'bin\SteamWrapperRunner.exe') -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $runnerManifest.sha256) 'Manager did not install a verified stable Runner.'
    Capture-AcceptanceWindow $window 'baseline-ui-profile-saved'
    Close-AcceptanceManager $manager
    $preserved = Get-AcceptanceDataHashes
    Assert-Acceptance ($preserved.Contains('profiles.toml') -and $preserved.Contains('bin\SteamWrapperRunner.exe')) 'UI save did not create profiles and Runner.'
    Record-Acceptance 'native UI profile save and stable Runner installation' ([ordered]@{ launchOptions = $expectedLaunch; retainedDataHashes = $preserved; profileEditedThroughUi = $true })
    if (-not $candidateUpgrade) {
        Invoke-AcceptanceRunner 'baseline-headless-Runner' $marker $gameDirectory
        $evidence.baselineRunnerOperationalTested=$true
    }

    Invoke-AcceptanceInstaller $baselineSetup 'baseline-normal-repair'
    $null = Read-AcceptanceInstallation $defaultProgram $inputManifest.baseline.tag
    Assert-AcceptanceShortcuts $defaultProgram $true
    Assert-AcceptanceDataHashes $preserved
    if ($scenario -cne 'CandidateFirstInstall') {
    Invoke-AcceptanceInstaller $targetSetup 'target-genuine-in-place-upgrade'
    $state = Read-AcceptanceInstallation $defaultProgram $inputManifest.target.tag
    Assert-Acceptance ($state.previous.tag -ceq $inputManifest.baseline.tag) 'Upgrade did not retain the genuine previous version.'
    Assert-AcceptanceShortcuts $defaultProgram $true
    Assert-AcceptanceDataHashes $preserved
    $manager = Start-AcceptanceManager $defaultProgram $inputManifest.target.tag 'target-upgraded-manager'
    if ($candidateUpgrade) {
        $bundle=Get-Content -LiteralPath (Join-Path $defaultProgram ('versions\' + $inputManifest.target.tag + '\Runner\runner-manifest.json')) -Raw | ConvertFrom-Json
        $deployment=Get-Content -LiteralPath (Join-Path $InputDirectory 'deployment-manifest.json') -Raw | ConvertFrom-Json
        $expectedRunner=@($deployment.files | Where-Object path -IEQ 'Runner/SteamWrapperRunner.exe')
        Assert-Acceptance ($expectedRunner.Count -eq 1 -and $bundle.schemaVersion -eq 1 -and $bundle.contractVersion -eq 2 -and
            $bundle.sha256 -ceq $expectedRunner[0].sha256 -and $bundle.sha256 -cne $preserved['bin\SteamWrapperRunner.exe']) 'The upgrade does not supply a genuinely new verified Runner.'
        $profiles=Wait-AcceptanceElement $manager.Window 'Profiles'
        $conditions=New-Object System.Windows.Automation.AndCondition -ArgumentList @(
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$profileName)),
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem))
        )
        $configured=Wait-Acceptance { $profiles.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$conditions) } 'retained upgrade profile'
        ([System.Windows.Automation.SelectionItemPattern]$configured.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
        $null=Wait-Acceptance {
            $name=Find-AcceptanceElement $manager.Window 'ProfileName'
            $null -ne $name -and ([System.Windows.Automation.ValuePattern]$name.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $profileName
        } 'retained profile editor after selection'
        $null=Wait-AcceptanceElement $manager.Window 'SaveProfile'
        Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'SaveProfile')
        $null=Wait-Acceptance {
            (Find-AcceptanceElement $manager.Window 'SaveProfile').Current.IsEnabled -and
            (Get-FileHash -LiteralPath (Join-Path $dataRoot 'bin\SteamWrapperRunner.exe') -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $bundle.sha256
        } 'updated stable Runner after saving retained profile'
        foreach($key in @('profiles.toml','ui-settings.json')) {
            if ($preserved.Contains($key)) { Assert-Acceptance ((Get-FileHash -LiteralPath (Join-Path $dataRoot $key) -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $preserved[$key]) 'Saving the retained profile changed prior configuration bytes.' }
        }
        $updatedManifest=Get-Content -LiteralPath (Join-Path $dataRoot 'bin\runner-manifest.json') -Raw | ConvertFrom-Json
        Assert-Acceptance ($updatedManifest.sha256 -ceq $bundle.sha256 -and $updatedManifest.version -ceq $bundle.version) 'The updated stable Runner manifest differs from the sealed bundle.'
        $updatedLaunch=Wait-AcceptanceElement $manager.Window 'LaunchOptions'
        Assert-Acceptance (([System.Windows.Automation.ValuePattern]$updatedLaunch.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $expectedLaunch) 'Saving the retained profile changed its stable Launch Options.'
        $preserved=Get-AcceptanceDataHashes
        $evidence.stableRunnerUpdated=$true
        Record-Acceptance 'retained profile saved and stable Runner updated' ([ordered]@{profileBytesUnchanged=$true;runnerSha256=$bundle.sha256;runnerVersion=$bundle.version;oldLaunchOptionsStillValid=$true})
    }
    Close-AcceptanceManager $manager
    Assert-AcceptanceDataHashes $preserved
    $state = Read-AcceptanceInstallation $defaultProgram $inputManifest.target.tag
    Assert-Acceptance $state.healthy 'The new Manager did not acknowledge healthy startup.'
    Invoke-AcceptanceRunner 'Runner-after-Manager-upgrade' $marker $gameDirectory
    Record-Acceptance 'genuine upgrade preserved profiles and stable Runner' ([ordered]@{ previousTag = $state.previous.tag; currentTag = $state.current.tag; healthy = $state.healthy; dataHashes = $preserved })
    $evidence.numericUpgradeTested=$true
    }

    Invoke-AcceptanceInstaller (Join-Path $defaultProgram 'unins000.exe') 'default-uninstall-keeps-data'
    Assert-Acceptance (-not (Test-Path -LiteralPath (Join-Path $defaultProgram 'SteamWrapper.exe')) -and -not (Test-Path -LiteralPath $registration)) 'Default uninstall retained Manager or its installation registration.'
    Assert-Acceptance (-not (Test-Path -LiteralPath (Join-Path $defaultProgram ('versions\' + $inputManifest.baseline.tag))) -and
        -not (Test-Path -LiteralPath (Join-Path $defaultProgram ('versions\' + $inputManifest.target.tag)))) 'Default uninstall retained an owned Manager version.'
    Assert-AcceptanceShortcuts $defaultProgram $false
    Assert-AcceptanceDataHashes $preserved
    Invoke-AcceptanceRunner 'Runner-after-Manager-uninstall' $marker $gameDirectory
    $null = Wait-Acceptance { -not (Test-Path -LiteralPath (Join-Path $defaultProgram 'unins000.exe')) } 'uninstaller normal self-removal' 30

    Invoke-AcceptanceInstaller $targetSetup 'target-custom-folder-reinstall' @(('/DIR=' + (Quote-AcceptanceArgument $customProgram)), '/TASKS="startmenuicon,desktopicon"')
    $null = Read-AcceptanceInstallation $customProgram $inputManifest.target.tag
    Assert-AcceptanceShortcuts $customProgram $true
    Assert-AcceptanceDataHashes $preserved
    $manager = Start-AcceptanceManager $customProgram $inputManifest.target.tag 'target-custom-folder-manager'
    $profiles = Wait-AcceptanceElement $manager.Window 'Profiles'
    $configured = $profiles.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $profileName)))
    Assert-Acceptance ($null -ne $configured) 'Reinstalled Manager did not load the retained profile.'
    Close-AcceptanceManager $manager
    Assert-AcceptanceDataHashes $preserved
    Invoke-AcceptanceRunner 'Runner-after-Manager-relocation' $marker $gameDirectory
    Invoke-AcceptanceInstaller (Join-Path $customProgram 'unins000.exe') 'final-default-uninstall'
    Assert-Acceptance (-not (Test-Path -LiteralPath (Join-Path $customProgram 'SteamWrapper.exe')) -and -not (Test-Path -LiteralPath $registration)) 'Final uninstall retained Manager or registration.'
    Assert-Acceptance (-not (Test-Path -LiteralPath (Join-Path $customProgram ('versions\' + $inputManifest.target.tag)))) 'Final uninstall retained its owned Manager version.'
    Assert-AcceptanceShortcuts $customProgram $false
    Assert-AcceptanceDataHashes $preserved
    $null = Wait-Acceptance { -not (Test-Path -LiteralPath (Join-Path $customProgram 'unins000.exe')) } 'final uninstaller normal self-removal' 30
    Assert-Acceptance ((Get-FileHash -LiteralPath $fixtureExe -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $fixtureHash) 'A product operation changed the test game binary.'
    $evidence.result = 'passed'
    $evidence.finalDataHashes = $preserved
    $evidence.gameFixtureSha256 = $fixtureHash
    $evidence.installationLocations = @($defaultProgram, $customProgram)
} catch {
    $evidence.result = 'failed'
    $evidence.error = $_.Exception.ToString()
    $evidence['errorLocation']=[ordered]@{script=$_.InvocationInfo.ScriptName;line=$_.InvocationInfo.ScriptLineNumber;scriptStack=$_.ScriptStackTrace}
    try {
        foreach ($entry in $ownedManagers) {
            $process = Get-Process -Id $entry.processId -ErrorAction SilentlyContinue
            if ($null -ne $process -and $process.MainModule.FileName -ieq $entry.path -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
                Capture-AcceptanceWindow ([System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)) ('failure-' + $entry.processId)
            }
        }
    } catch { $warnings.Add('Failure screenshot unavailable: ' + $_.Exception.Message) }
} finally {
    $evidence.completedAt = [DateTime]::UtcNow.ToString('o')
    Write-AcceptanceEvidence
}
if ($evidence.result -ne 'passed') { Write-Error ('Clean Windows acceptance failed. See ' + $evidencePath); exit 1 }
Write-Output ('Clean Windows Sandbox acceptance passed: ' + $evidencePath)
