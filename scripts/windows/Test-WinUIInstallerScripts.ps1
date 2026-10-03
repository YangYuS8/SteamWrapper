[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $repoRoot ('target/winui/installer-script-tests-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $root 'payload'
$outside = Join-Path $root 'outside'
[IO.Directory]::CreateDirectory($payload) | Out-Null
[IO.Directory]::CreateDirectory($outside) | Out-Null
[IO.File]::WriteAllText((Join-Path $payload 'SteamWrapper.Manager.exe'), 'manager fixture')
[IO.File]::WriteAllText((Join-Path $outside 'preserve.txt'), 'unrelated data')
foreach ($relative in Get-WinUIInstallerRequiredFiles) {
    $file = Join-Path $payload $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file)) | Out-Null
    [IO.File]::WriteAllText($file, "fixture $relative")
}
$runner = [ordered]@{ schemaVersion = 1; contractVersion = 2; version = '0.2.1'; sha256 = (Get-FileHash -LiteralPath (Join-Path $payload 'Runner/SteamWrapperRunner.exe') -Algorithm SHA256).Hash.ToLowerInvariant() }
[IO.File]::WriteAllText((Join-Path $payload 'Runner/runner-manifest.json'), ($runner | ConvertTo-Json))
$runtimeConfigPath = Join-Path $payload 'SteamWrapper.Manager.runtimeconfig.json'
$validRuntimeConfig = '{"runtimeOptions":{"tfm":"net10.0","includedFrameworks":[{"name":"Microsoft.NETCore.App","version":"10.0.11"}]}}'
[IO.File]::WriteAllText($runtimeConfigPath, $validRuntimeConfig)
$junction = Join-Path $payload 'redirected'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
$rejected = $false
try {
    try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' }
    catch { $rejected = $true }
} finally {
    # Always remove only this junction entry, including an intentional RED run.
    # Never recurse or follow it into the unrelated target fixture.
    if ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($junction) }
}
if (-not $rejected) { throw 'Installer manifest generation accepted a payload junction outside the package.' }
if ([IO.File]::ReadAllText((Join-Path $outside 'preserve.txt')) -ne 'unrelated data') { throw 'The junction target was modified.' }
$deploymentLibrary = Join-Path $payload 'SteamWrapper.Deployment.dll'
if (Test-Path -LiteralPath $deploymentLibrary) { [IO.File]::Delete($deploymentLibrary) }
$rejected = $false
try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' }
catch { $rejected = $true }
finally { [IO.File]::WriteAllText($deploymentLibrary, 'fixture SteamWrapper.Deployment.dll') }
if (-not $rejected) { throw 'An installer without the Manager deployment library was accepted.' }
$hostFxr = Join-Path $payload 'hostfxr.dll'
if (Test-Path -LiteralPath $hostFxr) { [IO.File]::Delete($hostFxr) }
$rejected = $false
try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' }
catch { $rejected = $true }
finally { [IO.File]::WriteAllText($hostFxr, 'fixture hostfxr.dll') }
if (-not $rejected) { throw 'An installer without its self-contained hostfxr was accepted.' }
foreach ($frameworkKey in @('framework', 'frameworks')) {
    $runtime = $validRuntimeConfig | ConvertFrom-Json -AsHashtable
    $runtime.runtimeOptions[$frameworkKey] = @{ name = 'Microsoft.NETCore.App'; version = '10.0.11' }
    [IO.File]::WriteAllText($runtimeConfigPath, ($runtime | ConvertTo-Json -Depth 5))
    $rejected = $false
    try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' } catch { $rejected = $true }
    finally { [IO.File]::WriteAllText($runtimeConfigPath, $validRuntimeConfig) }
    if (-not $rejected) { throw "An installer that depends on a machine-installed runtime was accepted: $frameworkKey." }
}
foreach ($privateRelative in @('profiles.toml', 'ui-settings.json.bak', '.env', '.env.production', 'logs/fake.txt', 'cache/fake.txt', 'backups/fake.txt', '.git/config')) {
    $privatePath = Join-Path $payload $privateRelative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($privatePath)) | Out-Null
    [IO.File]::WriteAllText($privatePath, 'safe synthetic private-data fixture')
    $rejected = $false
    try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' }
    catch { $rejected = $_.Exception.Message -match 'private or runtime data' }
    finally { [IO.File]::Delete($privatePath); if ($privateRelative.Contains('/')) { [IO.Directory]::Delete([IO.Path]::GetDirectoryName($privatePath)) } }
    if (-not $rejected) { throw "Installer accepted a private-data fixture: $privateRelative." }
}
$manifestPath = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.files.Count -ne (Get-WinUIInstallerRequiredFiles).Count -or $manifest.tag -ne 'v0.2.1-preview.1') { throw 'The generated manifest does not contain the complete expected payload.' }
foreach ($entry in $manifest.files) {
    $file = Join-Path $payload $entry.path
    if ($entry.path.Contains('\') -or $entry.bytes -ne (Get-Item -LiteralPath $file).Length -or $entry.sha256 -ne (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'A manifest path, size or actual digest is incorrect.' }
}
$beforeHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
$rejected = $false
try {
    # Supplying an upgrade directory must not turn text/metadata fixtures into
    # genuine next-version evidence. Reject products before touching the compiler.
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIInstaller.ps1') -PublishDirectory $payload -UpgradePublishDirectory $payload -Tag 'v0.2.1-preview.1' -UpgradeTag 'v0.2.2-preview.1' -Compiler (Join-Path $outside 'missing-compiler.exe')
} catch { $rejected = $_.Exception.Message -match 'Own PE product/version mismatch' }
if (-not $rejected) { throw 'Real-version installer acceptance did not reject synthetic products before compiler/installer execution.' }
$repeatOutput = Join-Path $root 'repeated-output'
[IO.Directory]::CreateDirectory($repeatOutput) | Out-Null
$oldSetup = Join-Path $repeatOutput 'SteamWrapper-v0.2.1-preview.1-win-x64-setup.exe'
[IO.File]::WriteAllText($oldSetup, 'preserve the previously sealed installer fixture')
$rejected = $false
try { $null = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') -Tag 'v0.2.1-preview.1' -PublishDirectory $payload -DeploymentDirectory (Join-Path $payload 'Deployment') -OutputDirectory $repeatOutput }
catch { $rejected = $_.Exception.Message -match 'output directory is not empty' }
if (-not $rejected -or [IO.File]::ReadAllText($oldSetup) -ne 'preserve the previously sealed installer fixture') { throw 'A repeated installer build did not reject an existing sealed output before compilation.' }
foreach ($tag in @('main', 'v01.2.3', 'v0.2.1-01', 'v0.2.1/escape')) {
    $rejected = $false
    try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag $tag } catch { $rejected = $true }
    if (-not $rejected) { throw "Unsafe or invalid installer tag was accepted: $tag." }
}
[IO.File]::AppendAllText((Join-Path $payload 'Runner/SteamWrapperRunner.exe'), 'tamper')
$rejected = $false
try { $null = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag 'v0.2.1-preview.1' } catch { $rejected = $true }
if (-not $rejected -or $beforeHash -ne (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash) { throw 'A changed Runner was accepted or rewrote the valid manifest.' }
$rejected = $false
try { $null = Assert-WinUIInstallerPath (Join-Path $repoRoot 'unsafe-output') -Output } catch { $rejected = $true }
if (-not $rejected) { throw 'An installer output outside target/winui was accepted.' }
Write-Host 'Installer safeguards passed: junction, required libraries, self-contained runtime, private-data names, inventory/digests, sealed output, tags, Runner tamper and output containment.'
