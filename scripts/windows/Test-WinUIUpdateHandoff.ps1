[CmdletBinding()]
param([string]$BaselineDirectory, [string]$PublishDirectory, [string]$Compiler,
    [string]$BaselineTag = 'v0.2.4-preview.1', [string]$Tag = 'v0.2.5-preview.1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'Actual update handoff acceptance requires an interactive Windows desktop.' }
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $BaselineDirectory) { $BaselineDirectory = Join-Path $repoRoot 'target/winui/upgrade-baselines/project-update-v0.2.4' }
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $repoRoot 'target/winui/publish' }
$BaselineDirectory = Assert-WinUIInstallerPath $BaselineDirectory
$PublishDirectory = Assert-WinUIInstallerPath $PublishDirectory
foreach ($pair in @(@($BaselineDirectory, $BaselineTag), @($PublishDirectory, $Tag))) {
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIProductMetadata.ps1') -PublishDirectory $pair[0] -ExpectedVersion (Assert-WinUIInstallerTag $pair[1])
}
if ([Version](Assert-WinUIInstallerTag $Tag) -le [Version](Assert-WinUIInstallerTag $BaselineTag)) { throw 'Update acceptance requires genuinely newer numeric product versions.' }
$fixtureProject = Join-Path $repoRoot 'apps/deployment-windows/SteamWrapper.Deployment.ProcessFixture/SteamWrapper.Deployment.ProcessFixture.csproj'
& dotnet build $fixtureProject --configuration Release --nologo --verbosity quiet
if ($LASTEXITCODE -ne 0) { throw 'Build the controlled deployment process fixture before update acceptance.' }
$fixtureExe = Join-Path ([IO.Path]::GetDirectoryName($fixtureProject)) 'bin/Release/net10.0/SteamWrapper.Deployment.ProcessFixture.exe'
$root = Assert-WinUIInstallerPath (Join-Path $repoRoot ('target/winui/update-handoff-' + [Guid]::NewGuid().ToString('N'))) -Output
$program = Join-Path $root 'program'
$data = Join-Path $root 'data/SteamWrapper'
$cache = Join-Path $data 'cache/updates'
[IO.Directory]::CreateDirectory((Join-Path $data 'bin')) | Out-Null
[IO.Directory]::CreateDirectory($cache) | Out-Null
[IO.File]::WriteAllText((Join-Path $data 'profiles.toml'), "version = 2`n[profiles]`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $data 'ui-settings.json'), '{"language":"en","steamCdnCovers":false,"automaticUpdateChecks":false,"updateSource":"auto"}', [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $BaselineDirectory 'Runner/SteamWrapperRunner.exe') -Destination (Join-Path $data 'bin/SteamWrapperRunner.exe')
$preserved = @{}
foreach ($relative in @('profiles.toml', 'ui-settings.json', 'bin/SteamWrapperRunner.exe')) { $path = Join-Path $data $relative; $preserved[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
$oldEnvironment = @{}
foreach ($name in @('STEAMWRAPPER_DEPLOYMENT_TEST', 'STEAMWRAPPER_E2E_ROOT', 'LOCALAPPDATA', 'STEAM_DIR')) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$parent = $null; $handoff = $null; $manager = $null; $stdout = $null; $stderr = $null
$release = Join-Path $root 'parent-release'
$evidencePath = Join-Path $root 'evidence.json'
$evidence = [ordered]@{ schemaVersion = 1; result = 'failed'; isolatedRoot = $root; programRoot = $program; baselineTag = $BaselineTag; targetTag = $Tag; cleanVm = $false; actualInstaller = $true; signedFeedNetwork = $false }
function Start-FixtureProcess([string]$Executable, [string[]]$Arguments, [switch]$Capture) {
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $start.RedirectStandardError = [bool]$Capture
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    return [Diagnostics.Process]::Start($start)
}
function Read-Installation { return Get-Content -LiteralPath (Join-Path $program 'installation.json') -Raw | ConvertFrom-Json }
function Read-CompletedCapture($Task) {
    if ($Task.IsCompletedSuccessfully) { return $Task.GetAwaiter().GetResult() }
    if ($Task.IsFaulted) { return '[Diagnostic capture failed; inspect installation.log and the retained fixture data/logs.]' }
    return '[Diagnostic pipe is still held by a child process; no process was killed to close it.]'
}
try {
    $env:STEAMWRAPPER_DEPLOYMENT_TEST = '1'
    $env:STEAMWRAPPER_E2E_ROOT = $root
    $env:LOCALAPPDATA = Join-Path $root 'data'
    $env:STEAM_DIR = Join-Path $root 'steam'
    [IO.Directory]::CreateDirectory((Join-Path $env:STEAM_DIR 'steamapps')) | Out-Null
    $build = @{ Tag = $BaselineTag; PublishDirectory = $BaselineDirectory; OutputDirectory = (Join-Path $root 'setup-baseline'); IsolatedRoot = $program }
    if ($Compiler) { $build.Compiler = $Compiler }
    $initialSetup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @build
    $initial = Start-FixtureProcess $initialSetup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/LANG=english', ('/LOG=' + (Join-Path $root 'baseline.log')))
    try { if (-not $initial.WaitForExit(120000) -or $initial.ExitCode -ne 0) { throw 'The isolated baseline installer failed or timed out; no process was killed.' } }
    finally { $initial.Dispose() }
    $before = Read-Installation
    if ($before.current.tag -ne $BaselineTag) { throw 'Baseline installation activated an unexpected release.' }
    $build.Tag = $Tag; $build.PublishDirectory = $PublishDirectory; $build.OutputDirectory = Join-Path $root 'setup-update'
    $setup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @build
    $inspection = & (Join-Path $PSScriptRoot 'Test-WinUIInstallerArtifact.ps1') -SetupPath $setup
    $installer = Join-Path $cache ('setup-' + $inspection.sha256 + '.exe')
    Copy-Item -LiteralPath $setup -Destination $installer
    $helperDirectory = Join-Path $cache ('handoff-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($helperDirectory) | Out-Null
    $helper = Join-Path $helperDirectory 'SteamWrapper.Update.exe'
    Copy-Item -LiteralPath (Join-Path $PublishDirectory 'Deployment/SteamWrapper.exe') -Destination $helper
    $ready = Join-Path $root 'parent-ready'
    $parent = Start-FixtureProcess $fixtureExe @('shared', $program, $ready, $release)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($parent.HasExited -or [DateTime]::UtcNow -ge $deadline) { throw 'The controlled originating process did not acquire its shared lease.' }
        Start-Sleep -Milliseconds 50
    }
    $beforeHash = (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash
    $arguments = @('--apply-update', '--test-root', '--root', $program, '--installer', $installer, '--sha256', $inspection.sha256,
        '--bytes', [string]$inspection.bytes, '--release-tag', $Tag, '--expires', [string][DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds(),
        '--parent-pid', [string]$parent.Id, '--parent-start', [string]$parent.StartTime.ToUniversalTime().Ticks, '--transaction', $before.transaction, '--language', 'en')
    $handoff = Start-FixtureProcess $helper $arguments -Capture
    $stdout = $handoff.StandardOutput.ReadToEndAsync(); $stderr = $handoff.StandardError.ReadToEndAsync()
    Start-Sleep -Milliseconds 300
    if ($handoff.HasExited -or $parent.HasExited -or (Get-FileHash -LiteralPath (Join-Path $program 'installation.json') -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Handoff did not preserve the active installation while its originating process held the shared lease.' }
    [IO.File]::WriteAllText($release, 'normal parent exit')
    if (-not $parent.WaitForExit(10000) -or $parent.ExitCode -ne 0) { throw 'The originating fixture process did not exit normally.' }
    if (-not $handoff.WaitForExit(150000)) { throw 'The actual update handoff timed out; all process and fixture evidence was preserved.' }
    if ($handoff.ExitCode -ne 0) { throw "Actual update handoff failed with exit code $($handoff.ExitCode); see handoff.log." }
    $after = Read-Installation
    if ($after.current.tag -ne $Tag -or $after.previous.tag -ne $BaselineTag -or -not $after.healthy) { throw 'The new Manager was not activated, retained its previous version, and acknowledged healthy startup.' }
    $expectedManager = Join-Path $program "versions/$Tag/SteamWrapper.Manager.exe"
    $owned = @(Get-Process -Name SteamWrapper.Manager -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $expectedManager })
    if ($owned.Count -ne 1) { throw 'Expected exactly one newly launched Manager in this isolated installation.' }
    $manager = $owned[0]
    if (-not $manager.CloseMainWindow() -or -not $manager.WaitForExit(30000)) { throw 'The isolated Manager did not close normally; it was not killed.' }
    foreach ($entry in $preserved.GetEnumerator()) { if ((Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash -ne $entry.Value) { throw 'Update handoff changed the profile, preferences or stable Runner fixture.' } }
    $evidence.activatedCurrentTag = $after.current.tag; $evidence.retainedPreviousTag = $after.previous.tag; $evidence.healthy = $after.healthy
    $uninstall = Start-FixtureProcess (Join-Path $program 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $root 'uninstall.log')))
    try { if (-not $uninstall.WaitForExit(120000) -or $uninstall.ExitCode -ne 0) { throw 'Isolated update acceptance uninstall failed or timed out; diagnostics and processes were preserved.' } }
    finally { $uninstall.Dispose() }
    if (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe')) { throw 'The isolated uninstaller retained its owned Manager launcher.' }
    foreach ($shortcut in @('shell-fixture/StartMenu/SteamWrapper.lnk', 'shell-fixture/Desktop/SteamWrapper.lnk')) {
        if (Test-Path -LiteralPath (Join-Path $root $shortcut)) { throw 'The isolated uninstaller retained a test shortcut.' }
    }
    foreach ($entry in $preserved.GetEnumerator()) { if ((Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash -ne $entry.Value) { throw 'Isolated uninstall changed retained player data.' } }
    $evidence.result = 'passed'
    $evidence.installerSha256 = $inspection.sha256; $evidence.installerBytes = $inspection.bytes
    $evidence.parentExitedNormally = $true; $evidence.managerRelaunchedHealthy = $true; $evidence.managerClosedNormally = $true
    $evidence.profilePreferencesAndStableRunnerPreserved = $true; $evidence.previousReleaseRetained = $true; $evidence.isolatedInstallationUninstalled = $true
    Write-Host "Passed actual isolated installer update handoff and Manager restart: $root"
    return $evidencePath
} finally {
    if ($parent -and -not $parent.HasExited) { [IO.File]::WriteAllText($release, 'normal cleanup exit'); $null = $parent.WaitForExit(10000) }
    if ($stdout -and $stderr) {
        # Manager inherits the Host's redirected pipes. EOF comes only after the
        # fixture Manager closes; failed acceptance must never wait indefinitely.
        if ($manager -and $manager.HasExited) { try { $null = [Threading.Tasks.Task]::WaitAll(@($stdout, $stderr), 5000) } catch { } }
        [IO.File]::WriteAllText((Join-Path $root 'handoff.log'), "stdout:`n" + (Read-CompletedCapture $stdout) + "`nstderr:`n" + (Read-CompletedCapture $stderr), [Text.UTF8Encoding]::new($false))
    }
    foreach ($process in @($parent, $handoff, $manager)) { if ($process) { $process.Dispose() } }
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    foreach ($entry in $oldEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value) }
}
