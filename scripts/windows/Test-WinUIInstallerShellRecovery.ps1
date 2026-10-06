[CmdletBinding()]
param([string]$PublishDirectory,[string]$Tag,[string]$FixtureRoot,[switch]$ResumeOwnRegistryFailure)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Actual Inno shell recovery acceptance requires Windows.' }
. (Join-Path $PSScriptRoot 'InstallerBoundaryAcceptance.ps1')
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $PublishDirectory) { $PublishDirectory=Join-Path $repo 'target/winui/publish' }
$publish=Assert-WinUIInstallerPath $PublishDirectory
if (-not $Tag) { $Tag='v' + (Get-Content -LiteralPath (Join-Path $publish 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version + '-preview.1' }
$null=Assert-WinUIInstallerTag $Tag
if ($ResumeOwnRegistryFailure -and -not $FixtureRoot) { throw 'Resume requires the explicit previously owned fixture.' }
if (-not $FixtureRoot) { $FixtureRoot=Get-InstallerBoundaryRoot $repo ([Guid]::NewGuid().ToString('N')) }
Assert-InstallerBoundaryRoot $FixtureRoot $repo
$root=[IO.Path]::GetFullPath($FixtureRoot)
if (-not $ResumeOwnRegistryFailure -and (Test-Path -LiteralPath $root) -and @(Get-ChildItem -LiteralPath $root -Force | Select-Object -First 1).Count) { throw 'Choose a fresh fixture; existing evidence is preserved.' }
$keyName=Get-InstallerBoundaryRegistryKey $root $repo
$keyPath='Registry::HKEY_CURRENT_USER\' + $keyName
if (-not $ResumeOwnRegistryFailure) { Assert-InstallerBoundary (-not (Test-Path -LiteralPath $keyPath)) 'The isolated AppId registry key already exists; it is preserved.' }
[IO.Directory]::CreateDirectory($root) | Out-Null
$program=Join-Path $root 'program'; $data=Join-Path $root 'data/SteamWrapper'
[IO.Directory]::CreateDirectory($data) | Out-Null
$sentinel=Join-Path $data 'profiles.toml'
if (-not $ResumeOwnRegistryFailure) { [IO.File]::WriteAllText($sentinel,'Disposable player configuration; always preserved.',[Text.UTF8Encoding]::new($false)) }
else { Assert-InstallerBoundary ([IO.File]::ReadAllText($sentinel) -ceq 'Disposable player configuration; always preserved.') 'The existing failed-fixture player sentinel changed.' }
$sentinelHash=(Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
$setup=if ($ResumeOwnRegistryFailure) { Join-Path $root ('setup/SteamWrapper-' + $Tag + '-win-x64-setup.exe') } else {
    & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') -Tag $Tag -PublishDirectory $publish -IsolatedRoot $program -OutputDirectory (Join-Path $root 'setup')
}
$build=Get-Content -LiteralPath (Join-Path $root 'setup/installer-build.json') -Raw | ConvertFrom-Json
Assert-InstallerBoundary ($build.isolated -is [bool] -and $build.isolated) 'Failure acceptance never executes a production installer.'
Assert-InstallerBoundary ($build.tag -ceq $Tag -and (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $build.installer.sha256) 'The existing or new isolated Setup differs from its sealed identity.'
$nativeHost=Join-Path $publish 'Deployment/SteamWrapper.exe'
$saved=@{}; $records=[Collections.Generic.List[object]]::new(); $passed=$false; $originalAcl=$null; $registryFault=$null
foreach ($name in @('LOCALAPPDATA','STEAMWRAPPER_DEPLOYMENT_TEST','STEAMWRAPPER_E2E_ROOT','STEAM_DIR')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$env:LOCALAPPDATA=Join-Path $root 'data'; $env:STEAMWRAPPER_DEPLOYMENT_TEST='1'; $env:STEAMWRAPPER_E2E_ROOT=$root; $env:STEAM_DIR=Join-Path $root 'steam-fixture'
function Invoke-ShellFixture([string]$Executable,[string]$Name,[string[]]$Arguments) {
    $start=[Diagnostics.ProcessStartInfo]::new($Executable); $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    foreach ($arg in $Arguments) { $start.ArgumentList.Add($arg) }
    $process=[Diagnostics.Process]::Start($start)
    try { Assert-InstallerBoundary ($process.WaitForExit(120000)) ('Fixture timed out: ' + $Name + '. No process was killed.'); return $process.ExitCode }
    finally { $process.Dispose() }
}
function Get-ShellSetupArguments([string]$Name) {
    return @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/LANG=english','/TASKS=startmenuicon,desktopicon',('/LOG=' + (Join-Path $root ($Name + '.log'))))
}
function Assert-ShellCompletePayload {
    $state=Get-Content -LiteralPath (Join-Path $program 'installation.json') -Raw | ConvertFrom-Json
    Assert-InstallerBoundary ($state.current.tag -ceq $Tag) 'The failed shell phase lost the complete activated Manager state.'
    $version=Join-Path $program ('versions/' + $Tag)
    $manifest=Get-Content -LiteralPath (Join-Path $version 'deployment-manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path=Join-Path $version $file.path
        Assert-InstallerBoundary ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -eq $file.bytes -and
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $file.sha256) 'A shell failure changed a complete owned Manager payload.'
    }
    Assert-InstallerBoundary ((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ceq $sentinelHash) 'Player data changed during shell failure or recovery.'
}
function Restore-ShellFixtureRegistryAcl {
    if ($null -ne $originalAcl -and (Test-Path -LiteralPath $keyPath)) {
        $restorer=[SteamWrapperBoundaryRegistryFault]::new($program,$keyName,$originalAcl.GetSecurityDescriptorBinaryForm())
        $restorer.SetOwnDescriptor($originalAcl.GetSecurityDescriptorBinaryForm())
        Assert-InstallerBoundary ((Get-Acl -LiteralPath $keyPath).Sddl -ceq $originalAcl.Sddl) 'The isolated registry descriptor was not restored exactly.'
    }
}
try {
    if ($ResumeOwnRegistryFailure) {
        $previous=Get-Content -LiteralPath (Join-Path $root 'shell-recovery-evidence.json') -Raw | ConvertFrom-Json
        Assert-InstallerBoundary ($previous.result -ceq 'failed' -and $previous.fixtureRoot -ceq $root -and $previous.setupSha256 -ceq $build.installer.sha256 -and
            $previous.cases.Count -le 1) 'Only the exact prior own-key restoration failure may be resumed.'
        if ($previous.cases.Count -eq 1) {
            Assert-InstallerBoundary ($previous.cases[0].scenario -ceq 'shortcut' -and $previous.cases[0].defaultUninstallPassed) 'The prior scope is not a completed own shortcut scenario.'
            $records.Add($previous.cases[0])
        }
    }
    $scenarios=if($ResumeOwnRegistryFailure){@('registration')}else{@('shortcut','registration')}
    foreach ($scenario in $scenarios) {
        $blocker=Join-Path $root 'shell-fixture/Desktop'
        if ($ResumeOwnRegistryFailure) {
            $observed=Get-Content -LiteralPath (Join-Path $root 'registration-fault-observation.json') -Raw | ConvertFrom-Json
            Assert-InstallerBoundary ($observed.stateSeen -and $observed.applied -and -not $observed.failure -and $observed.innoExitCode -ne 0 -and $observed.onlyOwnNewAppIdKey) 'The prior native Inno registration failure was not actually observed.'
            $failedExit=$observed.innoExitCode
            Assert-ShellCompletePayload
        } elseif ($scenario -ceq 'shortcut') {
            [IO.Directory]::CreateDirectory((Split-Path $blocker)) | Out-Null
            [IO.File]::WriteAllText($blocker,'Own fixture blocks only the isolated desktop directory.')
        } else {
            Assert-InstallerBoundary (-not (Test-Path -LiteralPath $keyPath)) 'The isolated registration key was not removed by the prior normal uninstall.'
            Assert-InstallerBoundary (-not (Test-Path -LiteralPath (Join-Path $program 'installation.json'))) 'Begin the registration fault only before a new actual activation.'
            $nativeKey=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($keyName)
            $nativeKey.Dispose()
            $originalAcl=Get-Acl -LiteralPath $keyPath
            [IO.File]::WriteAllText((Join-Path $root 'original-own-registry-acl.sddl'),$originalAcl.Sddl,[Text.UTF8Encoding]::new($false))
            $denyAcl=[Security.AccessControl.RegistrySecurity]::new()
            $denyAcl.SetSecurityDescriptorSddlForm($originalAcl.Sddl)
            # Inno removes a previous own uninstall key before writing it again.
            # Deny deletion as well, so that recreating the key cannot erase the
            # deliberately late fault. Its parent/siblings are never changed.
            $rights=[Security.AccessControl.RegistryRights]::SetValue -bor [Security.AccessControl.RegistryRights]::CreateSubKey -bor [Security.AccessControl.RegistryRights]::Delete
            $rule=[Security.AccessControl.RegistryAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User,$rights,
                [Security.AccessControl.InheritanceFlags]::None,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Deny)
            $denyAcl.AddAccessRule($rule)
            Add-Type -TypeDefinition (Get-InstallerBoundaryRegistryFaultSource)
            $registryFault=[SteamWrapperBoundaryRegistryFault]::new($program,$keyName,$denyAcl.GetSecurityDescriptorBinaryForm())
            $registryFault.Start()
        }
        if (-not $ResumeOwnRegistryFailure) { try {
            $failedExit=Invoke-ShellFixture $setup ($scenario + '-failure') (Get-ShellSetupArguments ($scenario + '-failure'))
            if ($null -ne $registryFault) {
                $registryFault.Stop()
                [IO.File]::WriteAllText((Join-Path $root 'registration-fault-observation.json'),([ordered]@{stateSeen=$registryFault.StateSeen;applied=$registryFault.Applied;failure=$registryFault.Failure;innoExitCode=$failedExit;onlyOwnNewAppIdKey=$true} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
                Assert-InstallerBoundary ($registryFault.StateSeen -and $registryFault.Applied -and -not $registryFault.Failure) 'The own registration failure was not injected after a real Manager activation; no late-phase pass is claimed.'
            }
            if ($scenario -ceq 'shortcut') {
                $log=[IO.File]::ReadAllText((Join-Path $root 'shortcut-failure.log'))
                Assert-InstallerBoundary ($log.Contains('Setup was unable to create the directory') -and $log.Contains($blocker) -and
                    -not (Test-Path -LiteralPath (Join-Path $blocker 'SteamWrapper.lnk'))) 'Inno did not record the actual blocked optional shortcut creation.'
            } else { Assert-InstallerBoundary ($failedExit -ne 0) 'Inno did not report the deliberately blocked own-fixture registration phase.' }
            Assert-ShellCompletePayload
        } finally {
            if ($null -ne $registryFault) { $registryFault.Stop(); $registryFault=$null }
            if ($scenario -ceq 'shortcut' -and (Test-Path -LiteralPath $blocker -PathType Leaf)) { [IO.File]::Delete($blocker) }
            if ($null -ne $originalAcl) {
                Restore-ShellFixtureRegistryAcl
                $originalAcl=$null
            }
        } }
        $repairExit=Invoke-ShellFixture $nativeHost ($scenario + '-native-repair') @('--repair','--root',$program,'--test-root','--language','en')
        Assert-InstallerBoundary ($repairExit -eq 0) 'The actual NativeAOT Host could not repair the complete Manager after shell failure.'
        Assert-InstallerBoundary ((Invoke-ShellFixture $setup ($scenario + '-reinstall') (Get-ShellSetupArguments ($scenario + '-reinstall'))) -eq 0) 'The matching actual Inno Setup could not complete registration after removing the own-fixture blocker.'
        Assert-ShellCompletePayload
        foreach ($path in @('shell-fixture/StartMenu/SteamWrapper.lnk','shell-fixture/Desktop/SteamWrapper.lnk')) {
            Assert-InstallerBoundary (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf) 'Normal recovery did not create the selected fixture shortcut.'
        }
        Assert-InstallerBoundary ((Get-ItemProperty -LiteralPath $keyPath -Name InstallLocation).InstallLocation.TrimEnd('\') -ieq $program.TrimEnd('\')) 'Normal recovery did not register the exact isolated Manager directory.'
        $uninstaller=Join-Path $program 'unins000.exe'
        Assert-InstallerBoundary ((Invoke-ShellFixture $uninstaller ($scenario + '-default-uninstall') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG=' + (Join-Path $root ($scenario + '-uninstall.log'))))) -eq 0) 'Default uninstall after recovery failed.'
        Assert-InstallerBoundary (-not (Test-Path -LiteralPath $keyPath) -and -not (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe'))) 'Default uninstall left the owned program or isolated registration.'
        Assert-InstallerBoundary ((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ceq $sentinelHash) 'Default uninstall changed retained player data.'
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        while ((Test-Path -LiteralPath $uninstaller) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Assert-InstallerBoundary (-not (Test-Path -LiteralPath $uninstaller)) 'The isolated uninstaller did not finish; it was not killed.'
        $records.Add([ordered]@{scenario=$scenario;failureExitCode=$failedExit;actualInnoFailure=$true;suppressedOptionalShortcutWarning=($scenario -ceq 'shortcut');completeManagerPayloadPreserved=$true;nativeRepairExitCode=$repairExit;matchingInstallerRecovered=$true;defaultUninstallPassed=$true;dataUnchanged=$true;onlyOwnNewRegistryKeyDescriptorChanged=($scenario -ceq 'registration');existingRegistryDescriptorsChanged=$false;resumedAfterTestRestorationFailure=[bool]$ResumeOwnRegistryFailure})
    }
    $passed=$true
} finally {
    try {
        if ($null -ne $registryFault) { $registryFault.Stop() }
        Restore-ShellFixtureRegistryAcl
    } finally {
        foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key,$item.Value,'Process') }
        [IO.File]::WriteAllText((Join-Path $root 'shell-recovery-evidence.json'),([ordered]@{schemaVersion=1;result=$(if($passed){'passed'}else{'failed'});scope=$(if($ResumeOwnRegistryFailure -and $records.Count -le 1){'registration-recovery-only'}else{'shortcut-and-registration'});fixtureRoot=$root;isolated=$true;cleanVm=$false;tag=$Tag;setupSha256=$build.installer.sha256;cases=$records.ToArray();noProcessesKilled=$true;existingDesktopAclChanged=$false;machinePolicyChanged=$false} | ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
    }
}
Write-Output "Actual Inno shell/registration recovery passed: $root"
