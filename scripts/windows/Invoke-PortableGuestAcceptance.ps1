# Actual portable client acceptance; inbox PowerShell 5.1, fresh Sandbox only.
# This entry never runs Setup or changes real Steam/game files.
[CmdletBinding()]
param([string]$InputDirectory='C:\AcceptanceInput',[string]$OutputDirectory='C:\AcceptanceOutput')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($InputDirectory -cne 'C:\AcceptanceInput' -or $OutputDirectory -cne 'C:\AcceptanceOutput' -or
    $env:USERNAME -ine 'WDAGUtilityAccount' -or $env:USERPROFILE.TrimEnd('\') -ine 'C:\Users\WDAGUtilityAccount' -or
    -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Portable production acceptance requires the dedicated interactive Windows Sandbox mappings and WDAG profile.' }
. (Join-Path $InputDirectory 'PortableAcceptance.ps1')
$null=Assert-PortableAcceptancePath $InputDirectory;$null=Assert-PortableAcceptancePath $OutputDirectory
Assert-PortableAcceptance (Test-Path -LiteralPath $OutputDirectory -PathType Container) 'Missing acceptance output mapping.'
$inputManifestPath=Join-Path $InputDirectory 'portable-input.json'
Assert-PortableAcceptance ((Get-Item -LiteralPath $inputManifestPath).Length -le 256KB) 'Portable input manifest exceeds its limit.'
$inputManifest=Get-Content -LiteralPath $inputManifestPath -Raw|ConvertFrom-Json
Assert-PortableAcceptance ($inputManifest.schemaVersion -eq 1 -and $inputManifest.scenario -ceq 'PortableCandidate' -and
    $inputManifest.sandboxOnly -is [bool] -and $inputManifest.sandboxOnly -and $inputManifest.networkingDisabled -is [bool] -and $inputManifest.networkingDisabled -and
    $inputManifest.localCandidate -is [bool] -and $inputManifest.localCandidate -and $inputManifest.sourceHeadCommit -cmatch '^[a-f0-9]{40}$' -and
    $inputManifest.workingCopyDirty -is [bool] -and $inputManifest.runId -cmatch '^[a-f0-9]{32}$' -and
    $inputManifest.hostComputerName -is [string] -and -not [string]::IsNullOrWhiteSpace($inputManifest.hostComputerName) -and $env:COMPUTERNAME -ine $inputManifest.hostComputerName) 'Unexpected local portable acceptance identity or host execution attempt.'
foreach($pair in @(@('PortableAcceptance.ps1','portableHelpersSha256'),@('Invoke-PortableGuestAcceptance.ps1','guestScriptSha256'),@('Invoke-CleanWindowsGuestAcceptance.ps1','cleanHelpersSha256'),@('portable-release.json','portableMetadataSha256'))) {
    $path=Assert-PortableAcceptancePath (Join-Path $InputDirectory $pair[0]);$item=Get-Item -LiteralPath $path
    Assert-PortableAcceptance (-not $item.PSIsContainer -and $item.Length -gt 0 -and $item.Length -le 2MB -and $inputManifest.($pair[1]) -cmatch '^[a-f0-9]{64}$' -and
        (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ceq $inputManifest.($pair[1])) ('Pinned portable acceptance input changed: '+$pair[0])
}
. (Get-PortableCleanHelperDefinitions (Join-Path $InputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1'))
# This entry's guards accept only the WDAG desktop. Keep the imported security
# helper's mode explicit; it must never infer standard-account acceptance.
$standardAccount=$false
$metadata=Get-Content -LiteralPath (Join-Path $InputDirectory 'portable-release.json') -Raw|ConvertFrom-Json
Assert-PortableAcceptanceMetadata $metadata
Assert-PortableAcceptance ($metadata.commit -ceq $inputManifest.sourceHeadCommit) 'Portable source commit differs from its recorded local provenance.'
$computer=Get-CimInstance Win32_ComputerSystem;$os=Get-CimInstance Win32_OperatingSystem
Assert-Acceptance ($computer.Manufacturer -ceq 'Microsoft Corporation' -and $computer.Model -ceq 'Virtual Machine' -and $os.ProductType -eq 1 -and [int]$os.BuildNumber -ge 26100 -and [Environment]::Is64BitProcess) 'Expected a native x64 Windows 11 24H2-or-later Sandbox client.'
Assert-Acceptance ($env:LOCALAPPDATA -ieq [Environment]::GetFolderPath('LocalApplicationData')) 'AppData is redirected.'
foreach($name in @('STEAMWRAPPER_E2E_ROOT','STEAMWRAPPER_DEPLOYMENT_TEST','STEAM_DIR')) {Assert-Acceptance ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) ('Unexpected test override: '+$name)}
Assert-Acceptance (@(Get-ChildItem Env:|Where-Object Name -like 'STEAMWRAPPER_DEPLOYMENT_*').Count -eq 0) 'Unexpected installed deployment environment.'
$dataRoot=Join-Path $env:LOCALAPPDATA 'SteamWrapper';$registration='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1'
$chineseWord=[string][char]0x4e2d+[char]0x6587
$program=Join-Path $env:USERPROFILE ('Apps\Portable '+$chineseWord)
$movedProgram=Join-Path $env:USERPROFILE ('Apps\Moved Portable '+$chineseWord)
$taskRoot=Join-Path $env:TEMP ('SteamWrapperPortable-'+$inputManifest.runId)
foreach($path in @($dataRoot,$program,$movedProgram,$taskRoot,(Join-Path $env:LOCALAPPDATA 'Programs\SteamWrapper'),$registration)) {Assert-Acceptance (-not(Test-Path -LiteralPath $path)) 'Sandbox already contains acceptance/product state; use a fresh instance.'}
Assert-Acceptance (@(Get-Process -Name steam,SteamWrapper,SteamWrapper.Manager,SteamWrapperRunner -ErrorAction SilentlyContinue).Count -eq 0) 'Sandbox already has Steam or product processes.'
Assert-Acceptance (-not(Test-Path -LiteralPath 'HKCU:\Software\Valve\Steam') -and -not(Test-Path -LiteralPath 'C:\Program Files (x86)\Steam')) 'Sandbox already contains Steam.'
Assert-Acceptance (@(Get-ChildItem -LiteralPath $OutputDirectory -Force|Where-Object {$_ -isnot [IO.FileInfo] -or $_.Name -cne 'guest-launch.log' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count -eq 0) 'Acceptance output is not fresh.'
$events=New-Object 'Collections.Generic.List[object]';$ownedManagers=New-Object 'Collections.Generic.List[object]';$managerCloseDiagnostics=New-Object 'Collections.Generic.List[object]';$runnerDiagnostics=New-Object 'Collections.Generic.List[object]';$warnings=New-Object 'Collections.Generic.List[string]'
$evidencePath=Join-Path $OutputDirectory 'evidence.json';$utf8=New-Object Text.UTF8Encoding($false)
$evidence=[ordered]@{
    schemaVersion=1;runId=$inputManifest.runId;scenario='PortableCandidate';result='running';startedAt=[DateTime]::UtcNow.ToString('o')
    environment='Windows Sandbox';cleanWindowsClient=$true;independentIsoVm=$false;standardUser=$false
    localCandidate=$true;unpublishedCandidate=$true;sourceHeadCommit=$inputManifest.sourceHeadCommit;workingCopyDirty=$inputManifest.workingCopyDirty
    numericUpgradeTested=$false;productionInstallerExecuted=$false;realSteam=$false;gameFilesTouched=$false
    build=$os.BuildNumber;hostBuild=$inputManifest.hostBuild;powerShellVersion=$PSVersionTable.PSVersion.ToString();tag=$metadata.tag
    archiveSha256=$metadata.archive.sha256;program=$program;movedProgram=$movedProgram;dataRoot=$dataRoot
    steps=$events;ownedManagers=$ownedManagers;managerCloseDiagnostics=$managerCloseDiagnostics;runnerDiagnostics=$runnerDiagnostics;warnings=$warnings
}
function Assert-PortablePayload([string]$Root) {
    foreach($record in @($metadata.files)) {
        $path=Assert-PortableAcceptancePath (Join-Path $Root $record.path.Replace('/','\'))
        Assert-Acceptance ((Get-Item -LiteralPath $path).Length -eq $record.bytes -and (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ceq $record.sha256) ('Portable payload changed: '+$record.path)
    }
    Assert-Acceptance (@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force).Count -eq @($metadata.files).Count) 'Portable payload gained unknown files.'
}
function Start-PortableManager([string]$Root,[string]$Name) {
    $expected=Join-Path $Root 'SteamWrapper.Manager.exe'
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$expected;$start.WorkingDirectory=$Root;$start.UseShellExecute=$true
    $launched=[Diagnostics.Process]::Start($start);if($null -ne $launched){$launched.Dispose()}
    $manager=Wait-Acceptance {
        foreach($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')) {
            try {if($candidate.MainModule.FileName -ieq $expected -and $candidate.MainWindowHandle -ne [IntPtr]::Zero){Retain-AcceptanceProcessHandle $candidate;return $candidate}}catch{}
            $candidate.Dispose()
        }
    } ('native portable Manager window: '+$Name) 60
    $window=[System.Windows.Automation.AutomationElement]::FromHandle($manager.MainWindowHandle)
    Assert-Acceptance ($window.Current.ProcessId -eq $manager.Id) 'Portable window has another process owner.'
    $null=Wait-Acceptance {(Find-AcceptanceElement $window 'AddGame').Current.IsEnabled} 'portable Manager initialization'
    $modules=Get-AcceptancePayloadRuntimeModules @($manager.Modules) $Root
    $ownedManagers.Add([ordered]@{processId=$manager.Id;path=$expected;portable=$true})
    Capture-AcceptanceWindow $window $Name
    Record-Acceptance $Name ([ordered]@{executable=$expected;payloadRuntimeModules=$modules;nativeAppData=$true})
    return [pscustomobject]@{Process=$manager;Window=$window}
}
Write-AcceptanceEvidence
try {
    $dotnetDirectories=@(@('C:\Program Files\dotnet','C:\Program Files (x86)\dotnet',(Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'))|Where-Object {Test-Path -LiteralPath $_})
    $packages=@(Get-AppxPackage -Name '*WindowsAppRuntime*' -ErrorAction SilentlyContinue|Select-Object Name,Version,Publisher,SignatureKind,NonRemovable,InstallLocation,IsFramework)
    $external=@($packages|Where-Object {-not(Test-AcceptanceInboxRuntimePackage $_ (Join-Path $env:windir 'SystemApps'))})
    $evidence.runtimeInventoryBeforeExtraction=[ordered]@{dotnetDirectories=$dotnetDirectories;dotnetOnPath=[bool](Get-Command dotnet -ErrorAction SilentlyContinue);windowsAppRuntimePackages=$packages;externalWindowsAppRuntimePackages=$external}
    Assert-Acceptance ($dotnetDirectories.Count -eq 0 -and -not $evidence.runtimeInventoryBeforeExtraction.dotnetOnPath -and $external.Count -eq 0) 'Sandbox has a machine SDK/runtime or external Windows App Runtime.'
    Record-Acceptance 'fresh offline no-SDK portable client' ([ordered]@{productAbsent=$true;steamAbsent=$true;externalToolchainInstalled=$false})
    Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
    Expand-PortableAcceptanceArchive (Join-Path $InputDirectory $metadata.archive.fileName) $metadata $program
    Assert-PortablePayload $program
    Record-Acceptance 'complete verified portable ZIP extracted to Chinese folder' ([ordered]@{files=@($metadata.files).Count;directory=$program})
    [IO.Directory]::CreateDirectory($taskRoot)|Out-Null
    $gameDirectory=Join-Path $taskRoot ('Harmless game '+$chineseWord);[IO.Directory]::CreateDirectory($gameDirectory)|Out-Null
    $fixtureExe=Join-Path $gameDirectory 'AcceptanceFixture.exe'
    Add-Type -TypeDefinition @'
public static class SteamWrapperPortableFixture {
    public static int Main() {
        System.Threading.Thread.Sleep(300);
        System.IO.File.WriteAllText("runner-completed.txt",System.Environment.CurrentDirectory,new System.Text.UTF8Encoding(false));
        return 0;
    }
}
'@ -OutputAssembly $fixtureExe -OutputType ConsoleApplication
    $fixtureHash=(Get-FileHash -LiteralPath $fixtureExe).Hash.ToLowerInvariant();$marker=Join-Path $gameDirectory 'runner-completed.txt'
    $manager=Start-PortableManager $program 'portable-first-launch';$window=$manager.Window
    Invoke-AcceptanceElement (Wait-AcceptanceElement $window 'AddGame')
    $manual=Wait-AcceptanceElement $window 'SecondaryButton'
    $manualState=[pscustomobject]@{name=[string]$manual.Current.Name;processId=[int]$manual.Current.ProcessId;automationId=$manual.Current.AutomationId;enabled=$manual.Current.IsEnabled}
    Assert-AcceptanceManualAppIdAction $manualState $window.Current.ProcessId $manager.Process.Id
    Invoke-AcceptanceElement $manual
    $profileName='Portable fixture '+$chineseWord
    Set-AcceptanceValue $window 'ProfileName' $profileName;Set-AcceptanceValue $window 'AppId' '487';Set-AcceptanceValue $window 'GameDirectory' $gameDirectory;Set-AcceptanceValue $window 'Target' 'AcceptanceFixture.exe'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $window 'SaveProfile')
    $launch=Wait-AcceptanceElement $window 'LaunchOptions'
    $null=Wait-Acceptance {(Find-AcceptanceElement $window 'SaveProfile').Current.IsEnabled} 'portable profile save'
    $expectedLaunch='"'+(Join-Path $dataRoot 'bin\SteamWrapperRunner.exe')+'" --appid "487" -- %command%'
    Assert-Acceptance (([System.Windows.Automation.ValuePattern]$launch.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $expectedLaunch) 'Portable profile points outside the stable Runner contract.'
    Capture-AcceptanceWindow $window 'portable-profile-saved';Close-AcceptanceManager $manager
    $preserved=Get-AcceptanceDataHashes
    Assert-Acceptance ($preserved.Contains('profiles.toml') -and $preserved.Contains('bin\SteamWrapperRunner.exe')) 'Portable UI failed to save profiles and stable Runner.'
    Assert-Acceptance ($preserved['bin\SteamWrapperRunner.exe'] -ceq $metadata.runner.sha256) 'Portable UI installed another Runner artifact.'
    Record-Acceptance 'portable UI saved Chinese profile and stable Runner' ([ordered]@{launchOptions=$expectedLaunch;dataHashes=$preserved;profileEditedThroughUi=$true})
    Invoke-AcceptanceRunner 'headless Runner with portable Manager closed' $marker $gameDirectory
    Assert-PortablePayload $program
    # Use the actual production helper and a valid operation. Rejection must be
    # the occupied-directory policy, not an unsupported option or bad fixture.
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $program 'Deployment\SteamWrapper.exe';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardError=$true
    $start.Arguments='--install --language en --root '+(Quote-AcceptanceArgument $program)+' --payload '+(Quote-AcceptanceArgument $program)
    $conversion=[Diagnostics.Process]::Start($start)
    try {
        Assert-Acceptance ($conversion.WaitForExit(30000)) 'Portable conversion refusal did not exit; it was not killed.'
        $message=$conversion.StandardError.ReadToEnd()
        Assert-Acceptance ($conversion.ExitCode -eq 11 -and $message -match 'Unknown files are preserved') ('Expected the occupied portable-directory safe-verification refusal. Actual: '+$message)
        Assert-PortablePayload $program;Assert-AcceptanceDataHashes $preserved
        Record-Acceptance 'installer protocol refused overwriting portable directory' ([ordered]@{productionDeploymentHelper=$true;exitCode=$conversion.ExitCode;diagnostic=$message;programAndDataPreserved=$true;setupExecuted=$false})
    }finally{$conversion.Dispose()}
    $null=Assert-PortableAcceptancePath $movedProgram
    [IO.Directory]::Move($program,$movedProgram)
    Assert-Acceptance (-not(Test-Path -LiteralPath $program)) 'Portable move retained its original program directory.'
    Assert-PortablePayload $movedProgram;Assert-AcceptanceDataHashes $preserved
    Record-Acceptance 'closed portable Manager moved without changing stable data' ([ordered]@{previous=$program;current=$movedProgram;stableDataRoot=$dataRoot})
    $manager=Start-PortableManager $movedProgram 'portable-moved-launch'
    $profiles=Wait-AcceptanceElement $manager.Window 'Profiles'
    $configured=$profiles.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$profileName)))
    Assert-Acceptance ($null -ne $configured) 'Moved portable Manager did not load the saved profile.'
    Close-AcceptanceManager $manager;Assert-AcceptanceDataHashes $preserved
    Invoke-AcceptanceRunner 'headless Runner after portable Manager folder move' $marker $gameDirectory
    Assert-PortablePayload $movedProgram
    Assert-Acceptance ((Get-FileHash -LiteralPath $fixtureExe).Hash.ToLowerInvariant() -ceq $fixtureHash -and -not(Test-Path -LiteralPath $registration) -and -not(Test-Path -LiteralPath (Join-Path $movedProgram 'installation.json'))) 'Portable scenario changed fixture bytes or registered an installation.'
    Record-Acceptance 'portable acceptance preserved fixture and left installation unregistered' ([ordered]@{fixtureSha256=$fixtureHash;installedToPortableConversionTested=$false;standardUserTested=$false;realSteam=$false})
    $evidence.result='passed';$evidence.completedAt=[DateTime]::UtcNow.ToString('o');Write-AcceptanceEvidence
    Write-Output 'Portable candidate client acceptance passed. This is not public release, standard-user or installed-to-portable conversion acceptance.'
}catch {
    $evidence.result='failed';$evidence.error=$_.Exception.Message;$evidence.completedAt=[DateTime]::UtcNow.ToString('o');Write-AcceptanceEvidence
    throw
}
