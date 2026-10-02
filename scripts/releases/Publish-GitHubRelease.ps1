[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$Repository = 'YangYuS8/SteamWrapper',
    [string]$GhExecutable = 'gh'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub repository.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$package = [IO.Path]::GetFullPath($PackageDirectory)
$metadata = & (Join-Path $repoRoot 'scripts/windows/Test-WinUIReleasePackage.ps1') -PackageDirectory $package
$tag = $metadata.tag

function Invoke-ReleaseGh([string[]]$Arguments, [switch]$AllowMissing) {
    $global:LASTEXITCODE = 0
    $output = & $GhExecutable @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        if ($AllowMissing -and $output -match '(release not found|HTTP 404)') { return $null }
        throw "GitHub release command failed: $($Arguments[0..1] -join ' '). No release was replaced."
    }
    return $output.Trim()
}

function Get-ReleaseState {
    $json = Invoke-ReleaseGh -Arguments @('release', 'view', $tag, '--repo', $Repository, '--json', 'tagName,targetCommitish,isDraft,isPrerelease,assets') -AllowMissing
    if ($null -eq $json) { return $null }
    return $json | ConvertFrom-Json
}

# Resolve through the API again to detect a tag moved after the build began.
$remoteCommit = Invoke-ReleaseGh -Arguments @('api', "repos/$Repository/commits/$tag", '--jq', '.sha')
if ($remoteCommit -ne $metadata.commit) { throw 'The remote GitHub tag no longer matches the built commit.' }
$release = Get-ReleaseState
$assetNames = @($metadata.archive.fileName, "$tag.en.md", "$tag.zh-CN.md", 'release.json', 'SHA256SUMS')
$verifyRoot = Join-Path $repoRoot ('target/github-release-verification/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verifyRoot -Force | Out-Null

function Assert-RemoteAsset($Asset) {
    $localFile = Join-Path $package $Asset.name
    if ($Asset.size -ne (Get-Item -LiteralPath $localFile).Length) { throw "Existing release asset has different bytes: $($Asset.name)." }
    $assetDirectory = Join-Path $verifyRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $assetDirectory | Out-Null
    $null = Invoke-ReleaseGh -Arguments @('release', 'download', $tag, '--repo', $Repository, '--pattern', $Asset.name, '--dir', $assetDirectory)
    $download = Join-Path $assetDirectory $Asset.name
    if (-not (Test-Path -LiteralPath $download -PathType Leaf) -or
        (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash) {
        throw "Downloaded GitHub asset does not match the package: $($Asset.name)."
    }
}

if ($null -ne $release) {
    if ($release.tagName -ne $tag -or -not $release.isPrerelease) { throw 'Existing release is not the expected WinUI prerelease.' }
    if ($release.isDraft -and $release.targetCommitish -ne $metadata.commit) { throw 'Existing draft targets a different source revision.' }
    $seenAssets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($asset in $release.assets) {
        if (-not $seenAssets.Add($asset.name)) { throw 'Existing release contains duplicate asset names; refusing to modify it.' }
        if ($asset.name -cnotin $assetNames) { throw 'Existing release contains an unexpected asset; refusing to replace it.' }
        Assert-RemoteAsset $asset
    }
    if (-not $release.isDraft) {
        if (@($release.assets).Count -ne $assetNames.Count) { throw 'Published release is incomplete; it will not be modified automatically.' }
        Write-Output "Published GitHub prerelease $tag already matches every package asset."
        return
    }
} else {
    $notesPath = Join-Path $verifyRoot 'release-notes.md'
    $notes = [IO.File]::ReadAllText((Join-Path $package "$tag.en.md")) + "`n`n---`n`n" + [IO.File]::ReadAllText((Join-Path $package "$tag.zh-CN.md"))
    [IO.File]::WriteAllText($notesPath, $notes, [Text.UTF8Encoding]::new($false))
    $null = Invoke-ReleaseGh -Arguments @('release', 'create', $tag, '--repo', $Repository, '--verify-tag', '--target', $metadata.commit, '--draft', '--prerelease', '--latest=false', '--title', "SteamWrapper $tag (Windows preview)", '--notes-file', $notesPath)
    $release = Get-ReleaseState
    if ($null -eq $release -or $release.tagName -cne $tag -or -not $release.isDraft -or -not $release.isPrerelease -or $release.targetCommitish -ne $metadata.commit) { throw 'GitHub did not create the expected draft prerelease.' }
}

# Never clobber an existing attachment. A failed upload can resume using the
# unchanged build artifact by rerunning only the failed publishing job.
foreach ($name in $assetNames) {
    if ($name -cnotin @($release.assets | ForEach-Object name)) {
        $null = Invoke-ReleaseGh -Arguments @('release', 'upload', $tag, (Join-Path $package $name), '--repo', $Repository)
    }
}
$release = Get-ReleaseState
if ($null -eq $release -or $release.tagName -cne $tag -or $release.targetCommitish -ne $metadata.commit -or -not $release.isDraft -or -not $release.isPrerelease -or @($release.assets).Count -ne $assetNames.Count) { throw 'Draft identity or asset upload is incomplete; the release remains unpublished.' }
$seenAssets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($asset in $release.assets) {
    if (-not $seenAssets.Add($asset.name)) { throw 'Duplicate draft asset; the release remains unpublished.' }
    if ($asset.name -cnotin $assetNames) { throw 'Unexpected draft asset; the release remains unpublished.' }
    Assert-RemoteAsset $asset
}
$remoteCommit = Invoke-ReleaseGh -Arguments @('api', "repos/$Repository/commits/$tag", '--jq', '.sha')
if ($remoteCommit -ne $metadata.commit) { throw 'The remote GitHub tag no longer matches the built commit; the release remains unpublished.' }
$null = Invoke-ReleaseGh -Arguments @('release', 'edit', $tag, '--repo', $Repository, '--draft=false', '--prerelease', '--latest=false')
$release = Get-ReleaseState
if ($null -eq $release -or $release.tagName -cne $tag -or $release.isDraft -or -not $release.isPrerelease) { throw 'GitHub prerelease publication could not be confirmed.' }
Write-Output "GitHub prerelease $tag published with five download-verified assets."
