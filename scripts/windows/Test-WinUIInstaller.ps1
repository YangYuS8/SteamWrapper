[CmdletBinding()]
param(
    [string]$PublishDirectory,
    [string]$DeploymentDirectory,
    [string]$UpgradePublishDirectory,
    [string]$Compiler,
    [string]$Tag,
    [string]$UpgradeTag
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Real installer acceptance requires Windows.' }
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $repoRoot 'target/winui/publish' }
if (-not $Tag) { $runnerVersion = (Get-Content -LiteralPath (Join-Path $PublishDirectory 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version; $Tag = "v$runnerVersion-installertest.1" }
if (-not $UpgradeTag) { $currentVersion = [Version](Assert-WinUIInstallerTag $Tag); $UpgradeTag = "v$($currentVersion.Major).$($currentVersion.Minor).$($currentVersion.Build + 1)-installertest.1" }
$null = Assert-WinUIInstallerTag $UpgradeTag
if ($UpgradePublishDirectory) {
    # An explicitly supplied directory is genuine-version evidence only after
    # inspecting the actual products. JSON-only version edits are insufficient.
    $initialPublish = Assert-WinUIInstallerPath $PublishDirectory
    $upgradePublish = Assert-WinUIInstallerPath $UpgradePublishDirectory
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIProductMetadata.ps1') -PublishDirectory $initialPublish -ExpectedVersion (Assert-WinUIInstallerTag $Tag)
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIProductMetadata.ps1') -PublishDirectory $upgradePublish -ExpectedVersion (Assert-WinUIInstallerTag $UpgradeTag)
}
$root = Assert-WinUIInstallerPath (Join-Path $repoRoot ("target/winui/installer acceptance 中文 ' " + [Guid]::NewGuid().ToString('N'))) -Output
$program = Join-Path $root 'program'
$data = Join-Path $root 'data/SteamWrapper'
[IO.Directory]::CreateDirectory((Join-Path $data 'bin')) | Out-Null
foreach ($relative in @('profiles.toml', 'ui-settings.json', 'bin/SteamWrapperRunner.exe', 'backups/keep.txt', 'cache/covers/keep.txt', 'logs/keep.txt')) {
    $path = Join-Path $data $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllText($path, "preserve fixture $relative 中文")
}
$preserved = @{}
foreach ($file in Get-ChildItem -LiteralPath $data -Recurse -File) { $preserved[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
$oldTest = $env:STEAMWRAPPER_DEPLOYMENT_TEST
$oldLocal = $env:LOCALAPPDATA
$oldSandbox = $env:STEAMWRAPPER_E2E_ROOT
$env:STEAMWRAPPER_DEPLOYMENT_TEST = '1'
$env:LOCALAPPDATA = Join-Path $root 'data'
$env:STEAMWRAPPER_E2E_ROOT = $root
$events = [Collections.Generic.List[object]]::new()

function Invoke-IsolatedInstaller {
    param([string]$Executable, [string[]]$Arguments, [string]$Name, [switch]$ExpectFailure)
    $log = Join-Path $root "$Name.log"
    $all = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/LOG="' + $log + '"')) + $Arguments
    $process = Start-Process -FilePath $Executable -ArgumentList $all -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { throw "Isolated installer $Name did not exit within its acceptance timeout. Its process was not killed." }
    $events.Add([pscustomobject]@{ name = $Name; exitCode = $process.ExitCode; log = $log })
    if ($ExpectFailure) {
        if ($process.ExitCode -eq 0) { throw "Isolated installer $Name unexpectedly succeeded." }
    } elseif ($process.ExitCode -ne 0) { throw "Isolated installer $Name failed with exit code $($process.ExitCode); see $log." }
}

function Invoke-IsolatedRollback {
    param([string]$Executable, [string]$Name)
    $log = Join-Path $root "$Name.log"
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('--rollback', '--root', $program, '--test-root', '--language', 'en')) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Isolated maintenance $Name did not start." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { throw "Isolated maintenance $Name did not exit within its acceptance timeout. Its process was not killed." }
        $diagnostics = "stdout:`n" + $stdout.GetAwaiter().GetResult() + "`nstderr:`n" + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($log, $diagnostics, [Text.UTF8Encoding]::new($false))
        $events.Add([pscustomobject]@{ name = $Name; kind = 'maintenance'; operation = 'rollback'; exitCode = $process.ExitCode; log = $log })
        if ($process.ExitCode -ne 0) { throw "Isolated maintenance $Name failed with exit code $($process.ExitCode); see $log." }
    } finally { $process.Dispose() }
}

function Assert-PreservedData {
    foreach ($entry in $preserved.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf) -or (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash -ne $entry.Value) { throw 'Installer acceptance changed a profile, stable Runner, backup, log or cover fixture.' }
    }
}

function Read-Installation {
    $state = Get-Content -LiteralPath (Join-Path $program 'installation.json') -Raw | ConvertFrom-Json
    if ($state.appId -ne 'SteamWrapper' -or $state.schemaVersion -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe'))) { throw 'The deployed Manager installation is incomplete.' }
    return $state
}

try {
    $build = @{ Tag = $Tag; OutputDirectory = (Join-Path $root 'setup-initial'); IsolatedRoot = $program }
    if ($PublishDirectory) { $build.PublishDirectory = $PublishDirectory }
    if ($DeploymentDirectory) { $build.DeploymentDirectory = $DeploymentDirectory }
    if ($Compiler) { $build.Compiler = $Compiler }
    $setup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @build
    Invoke-IsolatedInstaller -Executable $setup -Arguments @('/LANG=chinesesimplified', ('/DIR="' + (Join-Path $root 'wrong-root') + '"')) -Name wrong-root -ExpectFailure
    if (Test-Path -LiteralPath (Join-Path $root 'wrong-root/installation.json')) { throw 'A command-line directory override mutated another installation root.' }
    if ((Get-Content -LiteralPath (Join-Path $root 'wrong-root.log') -Raw) -notmatch '不能选择其他目录') { throw 'The compiled Chinese installer did not report its localized fixed-root safeguard.' }

    Invoke-IsolatedInstaller -Executable $setup -Arguments @('/LANG=english', '/TASKS=desktopicon') -Name install-english
    $state = Read-Installation
    if ($state.current.tag -ne $Tag) { throw 'The initial setup activated the wrong release.' }
    $desktopShortcut = Join-Path $root 'shell-fixture/Desktop/SteamWrapper.lnk'
    $startShortcut = Join-Path $root 'shell-fixture/StartMenu/SteamWrapper.lnk'
    if (-not (Test-Path -LiteralPath $desktopShortcut) -or -not (Test-Path -LiteralPath $startShortcut)) { throw 'The isolated setup did not create its actual fixture shortcuts.' }
    if ((Get-Content -LiteralPath (Join-Path $root 'install-english.log') -Raw) -notmatch 'Isolated Run-phase lease probe passed') { throw 'The real Inno Run phase did not confirm an independently acquired deployment lease.' }
    Assert-PreservedData

    $beforeBusy = (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash
    $lease = [IO.FileStream]::new((Join-Path $program '.installation.lock'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { Invoke-IsolatedInstaller -Executable $setup -Arguments @('/LANG=english') -Name install-busy -ExpectFailure }
    finally { $lease.Dispose() }
    if ($beforeBusy -ne (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash) { throw 'A busy installation changed its activation state.' }
    Assert-PreservedData

    [IO.File]::Delete((Join-Path $program 'SteamWrapper.exe'))
    Invoke-IsolatedInstaller -Executable $setup -Arguments @('/LANG=chinesesimplified') -Name repair-chinese
    if ((Read-Installation).current.tag -ne $Tag) { throw 'Repair changed the active version.' }
    $initialState = Read-Installation
    $initialLauncherHash = (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash
    Assert-PreservedData

    $syntheticUpgrade = -not $UpgradePublishDirectory
    if ($syntheticUpgrade) {
        # Test only the deployment transaction for a next numeric version. This is
        # explicitly an isolated metadata fixture, not a real next-version build.
        $UpgradePublishDirectory = Join-Path $root 'synthetic-upgrade-publish'
        [IO.Directory]::CreateDirectory($UpgradePublishDirectory) | Out-Null
        foreach ($entry in Get-ChildItem -LiteralPath $PublishDirectory -Force) { Copy-Item -LiteralPath $entry.FullName -Destination $UpgradePublishDirectory -Recurse -Force }
        $runnerManifestPath = Join-Path $UpgradePublishDirectory 'Runner/runner-manifest.json'
        $runnerManifest = Get-Content -LiteralPath $runnerManifestPath -Raw | ConvertFrom-Json
        $runnerManifest.version = Assert-WinUIInstallerTag $UpgradeTag
        [IO.File]::WriteAllText($runnerManifestPath, ($runnerManifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    $build.Tag = $UpgradeTag
    $build.PublishDirectory = $UpgradePublishDirectory
    $build.OutputDirectory = Join-Path $root 'setup-upgrade'
    $upgrade = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @build
    Invoke-IsolatedInstaller -Executable $upgrade -Arguments @('/LANG=chinesesimplified', '/NOICONS', '/TASKS=""') -Name upgrade-chinese
    $state = Read-Installation
    if ($state.current.tag -ne $UpgradeTag -or $state.previous.tag -ne $Tag) { throw 'Upgrade did not retain and identify the previous complete version.' }
    Assert-PreservedData

    # Exercise the actual compatible rollback CLI after a real Inno upgrade,
    # keeping both complete payloads and all independently owned Inno files.
    $upgradeState = $state
    $rollbackOwnedHashes = @{}
    $versionFiles = @(Get-ChildItem -LiteralPath (Join-Path $program 'versions') -Recurse -File)
    $maintenance = Join-Path $program 'maintenance/SteamWrapper.Deployment.exe'
    $innoFiles = @(Get-ChildItem -LiteralPath $program -Filter 'unins*' -File)
    foreach ($file in $versionFiles + $innoFiles) { $rollbackOwnedHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    foreach ($path in @($maintenance, $desktopShortcut, $startShortcut)) { $rollbackOwnedHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    if ($rollbackOwnedHashes[$maintenance] -ne $upgradeState.launcherSha256) { throw 'The rollback maintenance executable is not the verified upgraded payload Host.' }
    Invoke-IsolatedRollback -Executable $maintenance -Name rollback-to-previous
    $rollbackState = Read-Installation
    foreach ($field in @('tag', 'version', 'manifestSha256')) {
        if ($rollbackState.current.$field -ne $initialState.current.$field -or $rollbackState.previous.$field -ne $upgradeState.current.$field) { throw 'Compatible rollback did not swap the verified current and previous version identities.' }
    }
    $restoredLauncherHash = (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash
    if ($restoredLauncherHash -ne $initialLauncherHash -or $restoredLauncherHash -ne $rollbackState.launcherSha256) { throw 'Compatible rollback did not restore the verified previous launcher bytes.' }
    if ($rollbackState.transaction -eq $upgradeState.transaction -or $rollbackState.healthy -or (Test-Path -LiteralPath (Join-Path $program 'installation-journal.json'))) { throw 'Compatible rollback retained an old health acknowledgment or an incomplete deployment transaction.' }
    if (@(Get-ChildItem -LiteralPath (Join-Path $program 'versions') -Recurse -File).Count -ne $versionFiles.Count) { throw 'Compatible rollback changed the complete owned version file set.' }
    foreach ($entry in $rollbackOwnedHashes.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf) -or $entry.Value -ne (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash) { throw 'Compatible rollback changed a complete owned version, maintenance Host, uninstaller or fixture shortcut.' }
    }
    Assert-PreservedData
    # Restore the same verified upgrade via Inno before the existing uninstall
    # rejection/removal checks. Rollback is never implemented as a downgrade setup.
    Invoke-IsolatedInstaller -Executable $upgrade -Arguments @('/LANG=chinesesimplified', '/NOICONS', '/TASKS=""') -Name upgrade-after-rollback
    $state = Read-Installation
    if ($state.current.tag -ne $UpgradeTag -or $state.current.version -ne $upgradeState.current.version -or $state.current.manifestSha256 -ne $upgradeState.current.manifestSha256 -or $state.previous.tag -ne $Tag) { throw 'The real installer did not reactivate the exact upgraded payload after compatible rollback.' }
    Assert-PreservedData

    $uninstallers = @(Get-ChildItem -LiteralPath $program -Filter 'unins*.exe' -File)
    if ($uninstallers.Count -ne 1) { throw 'Upgrade created multiple unrelated uninstallers instead of maintaining one installation identity.' }
    $ownedVersionHashes = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $program 'versions') -Recurse -File) { $ownedVersionHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    $beforeUninstallState = (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash
    $beforeUninstallLauncher = (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash
    $lockedResource = [IO.FileStream]::new((Join-Path $program "versions/$UpgradeTag/zh-CN/SteamWrapper.Application.resources.dll"), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { Invoke-IsolatedInstaller -Executable $uninstallers[0].FullName -Arguments @() -Name uninstall-locked-owned-file -ExpectFailure }
    finally { $lockedResource.Dispose() }
    if ($beforeUninstallState -ne (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash -or $beforeUninstallLauncher -ne (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash -or -not (Test-Path -LiteralPath $uninstallers[0].FullName)) { throw 'A locked owned file left the failed uninstall partially deactivated.' }
    foreach ($entry in $ownedVersionHashes.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key) -or $entry.Value -ne (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash) { throw 'A rejected uninstall partially deleted a complete owned version.' }
    }
    Assert-PreservedData
    Invoke-IsolatedInstaller -Executable $upgrade -Arguments @('/LANG=chinesesimplified', '/NOICONS', '/TASKS=""') -Name repair-after-locked-uninstall
    if ((Read-Installation).current.tag -ne $UpgradeTag) { throw 'Repair after the locked-file rejection changed the active release.' }
    $unknown = Join-Path $program 'player-notes.txt'
    [IO.File]::WriteAllText($unknown, 'keep unrelated installation-root notes')
    Invoke-IsolatedInstaller -Executable $uninstallers[0].FullName -Arguments @() -Name uninstall-unknown -ExpectFailure
    if ([IO.File]::ReadAllText($unknown) -ne 'keep unrelated installation-root notes' -or -not (Test-Path -LiteralPath $uninstallers[0].FullName) -or (Read-Installation).current.tag -ne $UpgradeTag) { throw 'Rejected uninstall removed or changed the preserved installation.' }
    # Delete only the exact fixture created above, after verifying its value.
    [IO.File]::Delete($unknown)
    Invoke-IsolatedInstaller -Executable $uninstallers[0].FullName -Arguments @() -Name uninstall
    if ((Test-Path -LiteralPath $desktopShortcut) -or (Test-Path -LiteralPath $startShortcut)) { throw 'Upgrade discarded previous shortcut ownership and left an owned fixture shortcut after uninstall.' }
    if (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe')) { throw 'Uninstall retained the owned Manager launcher.' }
    if ((Test-Path -LiteralPath (Join-Path $program "versions/$Tag")) -or (Test-Path -LiteralPath (Join-Path $program "versions/$UpgradeTag"))) { throw 'Uninstall retained owned application versions.' }
    Assert-PreservedData
    Invoke-IsolatedInstaller -Executable $upgrade -Arguments @('/LANG=english', '/NOICONS', '/TASKS=""') -Name reinstall-after-uninstall
    if ((Read-Installation).current.tag -ne $UpgradeTag) { throw 'Reinstall did not recover the removed installation root safely.' }
    Assert-PreservedData
    Invoke-IsolatedInstaller -Executable (Join-Path $program 'unins000.exe') -Arguments @() -Name uninstall-reinstalled
    if (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe')) { throw 'The reinstalled Manager could not be removed cleanly.' }
    Assert-PreservedData
    $rollbackEvidence = [ordered]@{ executedByActualMaintenanceProcess = $true; fromTag = $upgradeState.current.tag; fromVersion = $upgradeState.current.version; toTag = $rollbackState.current.tag; toVersion = $rollbackState.current.version; restoredLauncherSha256 = $restoredLauncherHash.ToLowerInvariant(); preservedOwnedVersionFiles = $versionFiles.Count; preservedMaintenanceUninstallerAndShortcuts = $true; reupgradedWithActualInstaller = $true }
    $evidence = [ordered]@{ schemaVersion = 1; isolatedRoot = $root; programRoot = $program; installationRootExplicitlyIsolated = $true; tests = $events.ToArray(); preservedDataFiles = $preserved.Count; actualFixtureShortcutsRemoved = $true; runPhaseLeaseAcquiredByIndependentProcess = $true; lockedOwnedFilesUninstallRejected = $true; reinstalledAfterOwnedUninstallReceipt = $true; unsigned = $true; cleanVm = $false; numericUpgradeUsesSyntheticMetadataFixture = $syntheticUpgrade; compatibleRollback = $rollbackEvidence }
    [IO.File]::WriteAllText((Join-Path $root 'evidence.json'), ($evidence | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Write-Host "Passed isolated actual Inno install, bilingual repair, upgrade, compatible maintenance rollback and uninstall: $root"
    return (Join-Path $root 'evidence.json')
} finally {
    $env:STEAMWRAPPER_DEPLOYMENT_TEST = $oldTest
    $env:LOCALAPPDATA = $oldLocal
    $env:STEAMWRAPPER_E2E_ROOT = $oldSandbox
}
