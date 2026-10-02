[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path $repoRoot ('target/winui/release-tests/' + [Guid]::NewGuid().ToString('N'))
$commit = '0123456789abcdef0123456789abcdef01234567'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $rejected = $false
    try { $null = & $Action }
    catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Expected rejection: $Pattern" }
}

Assert-Rejected { Get-WinUIReleasePlan -Tag 'main' -Commit $commit -RepositoryRoot $fixture } 'Release tag must be*'
Write-Output 'PASS: arbitrary refs cannot become releases.'

$source = Join-Path $fixture 'source'
$publish = Join-Path $source 'target/winui/publish'
$releases = Join-Path $source 'target/winui/releases'
New-Item -ItemType Directory -Path (Join-Path $source 'apps/manager-winui/SteamWrapper.Manager'), (Join-Path $source 'crates/core'), (Join-Path $source 'crates/runner'), (Join-Path $source 'releases'), $publish -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $source 'apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj'), '<Project><PropertyGroup><Version>0.2.0</Version></PropertyGroup></Project>')
foreach ($crate in @('core', 'runner')) { [IO.File]::WriteAllText((Join-Path $source "crates/$crate/Cargo.toml"), "[package]`nversion = `"0.2.0`"`n") }
[IO.File]::WriteAllText((Join-Path $source 'LICENSE'), 'Fixture license text.')
foreach ($tag in @('v0.2.0', 'v0.2.0-rc.1')) {
    foreach ($language in @('en', 'zh-CN')) { [IO.File]::WriteAllText((Join-Path $source "releases/$tag.$language.md"), "# $tag`n`nUnsigned Windows preview / 未签名 Windows 预览。`n") }
}
foreach ($tag in @('v01.2.0', 'v1.02.3', 'v1.2.03', 'v1.2.3-01', 'v1.2.3-rc..1', 'v1.2.3+build', 'v1.2.3-rc_1', 'v1.2.3-', 'v1.2.3 ', 'V1.2.3')) {
    Assert-Rejected { Get-WinUIReleasePlan -Tag $tag -Commit $commit -RepositoryRoot $source } 'Release tag must be*'
}
Write-Output 'PASS: invalid numeric versions, prerelease labels, build metadata and ref characters are rejected.'
foreach ($tag in @('v0.2.0', 'v0.2.0-rc.1')) {
    $plan = Get-WinUIReleasePlan -Tag $tag -Commit $commit -RepositoryRoot $source
    if ($plan.Version -ne '0.2.0' -or $plan.Commit -ne $commit -or -not $plan.GitHubPrerelease -or $plan.Signed) { throw 'The exact version/commit/preview policy was lost.' }
}
Write-Output 'PASS: numeric and prerelease tags retain exact metadata and remain unsigned previews.'
Assert-Rejected { Get-WinUIReleasePlan -Tag 'v0.2.0' -Commit 'main' -RepositoryRoot $source } 'Release commit must be*'
Assert-Rejected { Get-WinUIReleasePlan -Tag 'v0.3.0' -Commit $commit -RepositoryRoot $source } 'Release base version*Manager*'
$corePath = Join-Path $source 'crates/core/Cargo.toml'
$coreText = [IO.File]::ReadAllText($corePath)
[IO.File]::WriteAllText($corePath, $coreText.Replace('0.2.0', '0.2.1'))
Assert-Rejected { Get-WinUIReleasePlan -Tag 'v0.2.0' -Commit $commit -RepositoryRoot $source } 'Release base version*core*'
[IO.File]::WriteAllText($corePath, $coreText)
Write-Output 'PASS: ambiguous commits and cross-language version mismatches are rejected.'
$chineseNotes = Join-Path $source 'releases/v0.2.0.zh-CN.md'
$notesText = [IO.File]::ReadAllText($chineseNotes)
Remove-Item -LiteralPath $chineseNotes
Assert-Rejected { Get-WinUIReleasePlan -Tag 'v0.2.0' -Commit $commit -RepositoryRoot $source } 'Release input is missing*'
[IO.File]::WriteAllText($chineseNotes, '# v0.2.0')
Assert-Rejected { Get-WinUIReleasePlan -Tag 'v0.2.0' -Commit $commit -RepositoryRoot $source } 'Release notes require*'
[IO.File]::WriteAllText($chineseNotes, $notesText)
Write-Output 'PASS: both language notes and real note bodies are required before building.'

$requiredFiles = @(
    'SteamWrapper.Manager.exe', 'SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll', 'SteamWrapper.Manager.pri',
    'SteamWrapper.Manager.runtimeconfig.json', 'SteamWrapper.Manager.deps.json',
    'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'System.Private.CoreLib.dll',
    'Microsoft.UI.Xaml.dll', 'Microsoft.WindowsAppRuntime.dll', 'Microsoft.Windows.Storage.Pickers.Projection.dll',
    'Runner/SteamWrapperRunner.exe', 'Runner/runner-manifest.json',
    'Assets/steamwrapper.svg', 'Assets/steamwrapper.ico', 'zh-CN/SteamWrapper.Application.resources.dll',
    'extra-runtime-dependency.dll'
)
foreach ($relative in $requiredFiles) {
    $path = Join-Path $publish $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($path)) -Force | Out-Null
    [IO.File]::WriteAllText($path, "Fixture bytes for $relative")
}
$runnerPath = Join-Path $publish 'Runner/SteamWrapperRunner.exe'
$manifestPath = Join-Path $publish 'Runner/runner-manifest.json'
$runnerHash = (Get-FileHash -LiteralPath $runnerPath).Hash.ToLowerInvariant()
$manifest = @{ schemaVersion = 1; contractVersion = 2; version = '0.2.0'; sha256 = $runnerHash } | ConvertTo-Json
[IO.File]::WriteAllText($manifestPath, $manifest)
$runtimePath = Join-Path $publish 'SteamWrapper.Manager.runtimeconfig.json'
$runtime = '{"runtimeOptions":{"includedFrameworks":[{"name":"Microsoft.NETCore.App","version":"10.0.0"}]}}'
[IO.File]::WriteAllText($runtimePath, $runtime)
$output = Join-Path $releases 'valid'
function Invoke-FixturePackage([string]$Destination = $output) {
    New-WinUIReleasePackage -Tag 'v0.2.0' -Commit $commit -RepositoryRoot $source -PublishDirectory $publish -OutputDirectory $Destination
}
$localizedPath = Join-Path $publish 'zh-CN/SteamWrapper.Application.resources.dll'
$localizedText = [IO.File]::ReadAllText($localizedPath)
Remove-Item -LiteralPath $localizedPath
Assert-Rejected { Invoke-FixturePackage } 'Release is missing*zh-CN*'
[IO.File]::WriteAllText($localizedPath, $localizedText)
[IO.File]::WriteAllText($manifestPath, $manifest.Replace($runnerHash, ('f' * 64)))
Assert-Rejected { Invoke-FixturePackage } 'Runner manifest schema*'
[IO.File]::WriteAllText($manifestPath, $manifest.Replace('"contractVersion": 2', '"contractVersion": 3'))
Assert-Rejected { Invoke-FixturePackage } 'Runner manifest schema*'
[IO.File]::WriteAllText($manifestPath, $manifest)
[IO.File]::WriteAllText($runtimePath, '{"runtimeOptions":{"framework":{"name":"Microsoft.NETCore.App"}}}')
Assert-Rejected { Invoke-FixturePackage } 'Release Manager runtime configuration*'
[IO.File]::WriteAllText($runtimePath, $runtime)
Write-Output 'PASS: incomplete localization, wrong Runner bytes/contracts and framework-dependent output are rejected.'
$secretPath = Join-Path $publish '.env'
[IO.File]::WriteAllText($secretPath, 'A disposable fixture, not credentials.')
Assert-Rejected { Invoke-FixturePackage } 'Release publish directory contains private*'
Remove-Item -LiteralPath $secretPath
Assert-Rejected { Invoke-FixturePackage (Join-Path $fixture 'outside-output') } 'Release path is outside*'
Write-Output 'PASS: private runtime data and unsafe output directories are rejected before packaging.'

if ($IsWindows) {
    $protected = Join-Path $fixture 'protected'
    New-Item -ItemType Directory -Path $protected -Force | Out-Null
    $sentinel = Join-Path $protected 'sentinel.txt'
    [IO.File]::WriteAllText($sentinel, 'Must remain unchanged.')
    $link = Join-Path $publish 'redirect'
    New-Item -ItemType Junction -Path $link -Target $protected | Out-Null
    Assert-Rejected { Invoke-FixturePackage } 'Release contents must not contain reparse*'
    Remove-Item -LiteralPath $link
    New-Item -ItemType Directory -Path $releases -Force | Out-Null
    $outputLink = Join-Path $releases 'redirect'
    New-Item -ItemType Junction -Path $outputLink -Target $protected | Out-Null
    Assert-Rejected { Invoke-FixturePackage (Join-Path $outputLink 'new') } 'Release paths must not contain reparse*'
    Remove-Item -LiteralPath $outputLink
    if ([IO.File]::ReadAllText($sentinel) -ne 'Must remain unchanged.' -or @(Get-ChildItem -LiteralPath $protected).Count -ne 1) { throw 'A linked target was changed by release packaging.' }
    Write-Output 'PASS: publish/output junctions are rejected and their target files are preserved.'
}
$before = @(Get-WinUIReleaseFiles $publish $source | ForEach-Object { "$($_.Path):$($_.Sha256)" })
$result = Invoke-FixturePackage
$after = @(Get-WinUIReleaseFiles $publish $source | ForEach-Object { "$($_.Path):$($_.Sha256)" })
if (@(Compare-Object $before $after).Count -ne 0) { throw 'Packaging modified the publish files.' }
$checked = Test-WinUIReleasePackageDirectory -PackageDirectory $result.Directory
if ($checked.commit -ne $commit -or $checked.files.Count -ne $requiredFiles.Count + 3 -or
    @($checked.files | Where-Object { $_.path -eq 'extra-runtime-dependency.dll' }).Count -ne 1) {
    throw 'The complete directory, notes or license were not recorded in the archive.'
}
Write-Output 'PASS: the whole publish directory, both notes and LICENSE are archived and every compressed file/hash is verified.'
$archiveHash = (Get-FileHash -LiteralPath $result.Archive).Hash
Assert-Rejected { Invoke-FixturePackage } 'Release output must be a fresh child*'
if ((Get-FileHash -LiteralPath $result.Archive).Hash -ne $archiveHash) { throw 'Existing output was overwritten.' }
Write-Output 'PASS: existing release output is never replaced.'
$tampered = Join-Path $releases 'tampered'
Copy-Item -LiteralPath $result.Directory -Destination $tampered -Recurse
[IO.File]::AppendAllText((Join-Path $tampered 'v0.2.0.en.md'), 'Changed after packaging.')
Assert-Rejected { Test-WinUIReleasePackageDirectory $tampered } 'Release asset checksum mismatch*'
$unsafe = Join-Path $releases 'unsafe-checksum'
Copy-Item -LiteralPath $result.Directory -Destination $unsafe -Recurse
[IO.File]::WriteAllText((Join-Path $unsafe 'SHA256SUMS'), "$('0' * 64)  ../outside.zip`n")
Assert-Rejected { Test-WinUIReleasePackageDirectory $unsafe } 'Release checksums contain an unsafe filename*'
Write-Output 'PASS: post-download asset tampering and checksum path traversal are rejected.'
function Update-FixtureChecksums([string]$Directory) {
    @(Get-ChildItem -LiteralPath $Directory -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name |
        ForEach-Object { "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)" }) |
        Set-Content -LiteralPath (Join-Path $Directory 'SHA256SUMS') -Encoding utf8NoBOM
}
$badZip = Join-Path $releases 'bad-zip'
Copy-Item -LiteralPath $result.Directory -Destination $badZip -Recurse
$badZipPath = Join-Path $badZip 'SteamWrapper-v0.2.0-win-x64.zip'
$zipUpdate = [IO.Compression.ZipFile]::Open($badZipPath, [IO.Compression.ZipArchiveMode]::Update)
try {
    $zipUpdate.GetEntry('SteamWrapper-v0.2.0-win-x64/extra-runtime-dependency.dll').Delete()
    $stream = [IO.StreamWriter]::new($zipUpdate.CreateEntry('SteamWrapper-v0.2.0-win-x64/extra-runtime-dependency.dll').Open())
    try { $stream.Write('Changed dependency inside the ZIP.') } finally { $stream.Dispose() }
} finally { $zipUpdate.Dispose() }
$badMetadataPath = Join-Path $badZip 'release.json'
$badMetadata = [IO.File]::ReadAllText($badMetadataPath) | ConvertFrom-Json
$badMetadata.archive.sha256 = (Get-FileHash -LiteralPath $badZipPath).Hash.ToLowerInvariant()
$badMetadata.archive.bytes = (Get-Item -LiteralPath $badZipPath).Length
$badMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badMetadataPath -Encoding utf8NoBOM
Update-FixtureChecksums $badZip
Assert-Rejected { Test-WinUIReleasePackageDirectory $badZip } 'Release ZIP entry*'
$badInventory = Join-Path $releases 'bad-inventory'
Copy-Item -LiteralPath $result.Directory -Destination $badInventory -Recurse
$badInventoryPath = Join-Path $badInventory 'release.json'
$badMetadata = [IO.File]::ReadAllText($badInventoryPath) | ConvertFrom-Json
$badMetadata.files[0].path = '../outside.dll'
$badMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badInventoryPath -Encoding utf8NoBOM
Update-FixtureChecksums $badInventory
Assert-Rejected { Test-WinUIReleasePackageDirectory $badInventory } 'Release file inventory contains an unsafe path*'
Write-Output 'PASS: rehashed outer assets still reject altered internal ZIP bytes and unsafe inventory paths.'
Write-Output "Release regression fixtures: $fixture"
