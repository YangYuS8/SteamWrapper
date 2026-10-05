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

# This mode is safe on a development host. It neither reads release input nor
# runs an installer; it only exercises quoting and loads inbox UIA assemblies.
if ($ValidateHelpers) {
    $unicodePath = 'C:\fixture ' + [char]0x4e2d + [char]0x6587
    Assert-Acceptance ((Quote-AcceptanceArgument ($unicodePath + '\')) -ceq ('"' + $unicodePath + '"')) 'Unicode argument quoting failed.'
    $rejected = $false
    try { $null = Quote-AcceptanceArgument 'C:\unexpected"path' } catch { $rejected = $true }
    Assert-Acceptance $rejected 'An unsafe argument was accepted.'
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    [ordered]@{
        passed = $true
        productionInstallerExecuted = $false
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        uiaAssembly = [System.Windows.Automation.AutomationElement].Assembly.Location
    } | ConvertTo-Json
    return
}

# Fail closed before making any directory, changing registration or executing
# product bytes. The two mapped folders alone are not proof of a clean guest.
Assert-Acceptance ($InputDirectory -ceq 'C:\AcceptanceInput' -and $OutputDirectory -ceq 'C:\AcceptanceOutput') 'Expected the dedicated Sandbox mappings.'
Assert-Acceptance ($env:USERNAME -ieq 'WDAGUtilityAccount') 'Production acceptance is allowed only for Windows Sandbox WDAGUtilityAccount.'
Assert-Acceptance ($env:USERPROFILE.TrimEnd('\') -ieq 'C:\Users\WDAGUtilityAccount') 'Unexpected Sandbox user profile.'
Assert-Acceptance ([Environment]::UserInteractive -and [Diagnostics.Process]::GetCurrentProcess().SessionId -ne 0) 'An interactive Sandbox desktop is required.'
$manifestPath = Join-Path $InputDirectory 'acceptance-input.json'
$inputManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-Acceptance ($inputManifest.schemaVersion -eq 1 -and $inputManifest.sandboxOnly -eq $true -and $inputManifest.networkingDisabled -eq $true) 'Expected the offline Sandbox input manifest.'
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
    $_ -isnot [IO.FileInfo] -or $_.Name -cne 'guest-launch.log' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
}).Count -eq 0) 'Use a fresh acceptance output folder containing at most its new guest-launch.log.'

$taskRoot = Join-Path $env:TEMP ('SteamWrapperClean-' + $runId)
Assert-Acceptance (-not (Test-Path -LiteralPath $taskRoot)) 'The guest work directory is not fresh.'
$events = New-Object 'System.Collections.Generic.List[object]'
$ownedManagers = New-Object 'System.Collections.Generic.List[object]'
$warnings = New-Object 'System.Collections.Generic.List[string]'
$evidence = [ordered]@{
    schemaVersion = 1; runId = $runId; result = 'running'; startedAt = [DateTime]::UtcNow.ToString('o')
    environment = 'Windows Sandbox'; cleanWindowsClient = $true; independentIsoVm = $false
    build = [string]$os.BuildNumber; caption = [string]$os.Caption; osVersion = [string]$os.Version
    hostBuild = [string]$inputManifest.hostBuild; computerName = $env:COMPUTERNAME
    userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    administrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    uiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name; powerShellVersion = $PSVersionTable.PSVersion.ToString()
    nativeDataRoot = $dataRoot; baseline = $inputManifest.baseline; target = $inputManifest.target
    runtimeInventoryBeforeInstallation = $null; externalSdkOrRuntimeInstalled = $false
    realSteamInstalled = $false; productionInstallers = $true; testEnvironmentOverrides = $false
    publicUpdateNetworkTested = $false; networkingDisabled = $true
    steps = $events; ownedManagers = $ownedManagers; warnings = $warnings
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
function Read-AcceptanceAsset($Asset) {
    Assert-Acceptance ([string]$Asset.fileName -cmatch '^SteamWrapper-v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+-win-x64-setup\.exe$') 'Unexpected installer filename.'
    Assert-Acceptance ([string]$Asset.tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$' -and $Asset.fileName -ceq ('SteamWrapper-' + $Asset.tag + '-win-x64-setup.exe')) 'Installer filename/tag disagree.'
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
        Assert-Acceptance ($process.WaitForExit(180000)) "$Name did not exit. It was not killed."
        Assert-Acceptance ($process.ExitCode -eq 0) "$Name exited with code $($process.ExitCode). See its preserved log."
        Record-Acceptance $Name ([ordered]@{ actualInstaller = $true; silentInstaller = $true; exitCode = $process.ExitCode; log = [IO.Path]::GetFileName($log); executable = $Executable })
    } finally { $process.Dispose() }
}
function Read-AcceptanceInstallation([string]$Program, [string]$Tag) {
    $state = Get-Content -LiteralPath (Join-Path $Program 'installation.json') -Raw | ConvertFrom-Json
    Assert-Acceptance ($state.schemaVersion -eq 1 -and $state.appId -ceq 'SteamWrapper' -and $state.current.tag -ceq $Tag) 'Installation activated an unexpected product/version.'
    $registered = (Get-ItemProperty -LiteralPath $registration).InstallLocation.TrimEnd('\')
    Assert-Acceptance ($registered -ieq $Program) 'The per-user registered installation location is incorrect.'
    return $state
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
    $launcherStart = New-Object Diagnostics.ProcessStartInfo
    $launcherStart.FileName = Join-Path $Program 'SteamWrapper.exe'; $launcherStart.WorkingDirectory = $Program; $launcherStart.UseShellExecute = $true
    $launcher = [Diagnostics.Process]::Start($launcherStart)
    if ($null -ne $launcher) { $launcher.Dispose() }
    $manager = Wait-Acceptance {
        foreach ($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')) {
            try {
                if ($candidate.MainModule.FileName -ieq $expected -and $candidate.MainWindowHandle -ne [IntPtr]::Zero) { return $candidate }
            } catch { }
            $candidate.Dispose()
        }
    } ('normal installed Manager window: ' + $Name) 60
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($manager.MainWindowHandle)
    Assert-Acceptance ($window.Current.ProcessId -eq $manager.Id) 'The UI window is not owned by the installed Manager.'
    $null = Wait-Acceptance { $button = Find-AcceptanceElement $window 'AddGame'; $button -and $button.Current.IsEnabled } 'Manager initialization'
    $timer.Stop()
    $ownedManagers.Add([ordered]@{ processId = $manager.Id; path = $expected; normalLauncher = $true })
    Capture-AcceptanceWindow $window $Name
    Record-Acceptance $Name ([ordered]@{ processId = $manager.Id; executable = $expected; processStartupMilliseconds = $timer.ElapsedMilliseconds; startupWorkingSetBytes = $manager.WorkingSet64; addGameName = (Find-AcceptanceElement $window 'AddGame').Current.Name })
    return [pscustomobject]@{ Process = $manager; Window = $window }
}
function Close-AcceptanceManager($Manager) {
    Assert-Acceptance ($Manager.Window.Current.ProcessId -eq $Manager.Process.Id) 'Refusing to close a foreign window.'
    ([System.Windows.Automation.WindowPattern]$Manager.Window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).Close()
    Assert-Acceptance ($Manager.Process.WaitForExit(45000)) 'Manager did not close normally; it was not killed.'
    Assert-Acceptance ($Manager.Process.ExitCode -eq 0) 'Manager exited unsuccessfully.'
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
        Assert-Acceptance ($runner.WaitForExit(30000) -and $runner.ExitCode -eq 0) 'Headless Runner failed or did not wait for the fixture; no process was killed.'
        Assert-Acceptance ((Test-Path -LiteralPath $Marker) -and [IO.File]::ReadAllText($Marker) -ceq $ExpectedWorkingDirectory) 'Runner did not execute the configured native test program in its game folder.'
        Assert-Acceptance (@(Get-Process -Name SteamWrapper.Manager -ErrorAction SilentlyContinue).Count -eq 0) 'Runner unexpectedly opened Manager.'
        Record-Acceptance $Name ([ordered]@{ exitCode = $runner.ExitCode; stablePath = $start.FileName; managerClosed = $true; harmlessProgramCompleted = $true; realSteam = $false })
    } finally { $runner.Dispose() }
}

try {
    [IO.Directory]::CreateDirectory($taskRoot) | Out-Null
    $framework = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    $dotnetDirectories = @('C:\Program Files\dotnet', 'C:\Program Files (x86)\dotnet', (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet')) | Where-Object { Test-Path -LiteralPath $_ }
    $appRuntimePackages = @(Get-AppxPackage -Name '*WindowsAppRuntime*' -ErrorAction SilentlyContinue | Select-Object Name, Version)
    $evidence.runtimeInventoryBeforeInstallation = [ordered]@{
        dotnetDirectories = @($dotnetDirectories); dotnetOnPath = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
        windowsAppRuntimePackages = $appRuntimePackages; netFrameworkRelease = $(if ($null -ne $framework) { $framework.Release } else { $null })
    }
    Assert-Acceptance (@($dotnetDirectories).Count -eq 0 -and -not $evidence.runtimeInventoryBeforeInstallation.dotnetOnPath -and $appRuntimePackages.Count -eq 0) 'The guest already contains a machine .NET runtime/SDK or Windows App Runtime; start a pristine Sandbox.'
    Record-Acceptance 'fresh offline Windows client' ([ordered]@{ productAbsent = $true; sdkAbsent = $true; steamAbsent = $true; nativeAppData = $true })
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
    $baselineSetup = Read-AcceptanceAsset $inputManifest.baseline
    $targetSetup = Read-AcceptanceAsset $inputManifest.target
    Record-Acceptance 'public production installer digests verified in guest' ([ordered]@{ baselineSha256 = $inputManifest.baseline.sha256; targetSha256 = $inputManifest.target.sha256 })

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
    Assert-AcceptanceShortcuts $defaultProgram $true
    $manager = Start-AcceptanceManager $defaultProgram $inputManifest.baseline.tag 'baseline-manager-first-launch'
    $window = $manager.Window
    Invoke-AcceptanceElement (Wait-AcceptanceElement $window 'AddGame')
    $manual = Wait-AcceptanceElement $window 'SecondaryButton'
    Assert-Acceptance ($manual.Current.ProcessId -eq $manager.Process.Id -and $manual.Current.Name -in @('Enter AppID manually', $chineseManualButton)) 'The manual AppID action is not the expected Manager dialog.'
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
    Invoke-AcceptanceRunner 'baseline-headless-Runner' $marker $gameDirectory

    Invoke-AcceptanceInstaller $baselineSetup 'baseline-normal-repair'
    $null = Read-AcceptanceInstallation $defaultProgram $inputManifest.baseline.tag
    Assert-AcceptanceShortcuts $defaultProgram $true
    Assert-AcceptanceDataHashes $preserved
    Invoke-AcceptanceInstaller $targetSetup 'target-genuine-in-place-upgrade'
    $state = Read-AcceptanceInstallation $defaultProgram $inputManifest.target.tag
    Assert-Acceptance ($state.previous.tag -ceq $inputManifest.baseline.tag) 'Upgrade did not retain the genuine previous version.'
    Assert-AcceptanceShortcuts $defaultProgram $true
    Assert-AcceptanceDataHashes $preserved
    $manager = Start-AcceptanceManager $defaultProgram $inputManifest.target.tag 'target-upgraded-manager'
    Close-AcceptanceManager $manager
    Assert-AcceptanceDataHashes $preserved
    $state = Read-AcceptanceInstallation $defaultProgram $inputManifest.target.tag
    Assert-Acceptance $state.healthy 'The new Manager did not acknowledge healthy startup.'
    Invoke-AcceptanceRunner 'Runner-after-Manager-upgrade' $marker $gameDirectory
    Record-Acceptance 'genuine upgrade preserved profiles and stable Runner' ([ordered]@{ previousTag = $state.previous.tag; currentTag = $state.current.tag; healthy = $state.healthy; dataHashes = $preserved })

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
