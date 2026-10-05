[CmdletBinding(DefaultParameterSetName = 'Release')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Release')][string]$PackageDirectory,
    [Parameter(Mandatory, ParameterSetName = 'Refresh')][switch]$Refresh,
    [Parameter(ParameterSetName = 'Refresh')][switch]$SkipMissingFeed,
    [ValidateSet('preview', 'stable')][string]$Channel = 'preview',
    [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
    [switch]$IncludeCnbMirror,
    [Parameter(ParameterSetName = 'Release')][switch]$RequireCurrentRelease,
    [string]$GhExecutable = 'gh'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProjectUpdates.ps1')
. (Join-Path $PSScriptRoot 'UpdateFeedTransport.ps1')
$trust = Read-ProjectUpdateTrust $TrustPath
$repository = $trust.githubRepository
if (-not $Refresh) {
    $metadata = & (Join-Path $PSScriptRoot '../windows/Test-WinUIReleasePackage.ps1') -PackageDirectory $PackageDirectory
    if (-not $PSBoundParameters.ContainsKey('Channel')) { $Channel = $metadata.releaseChannel }
    if ($metadata.releaseChannel -cne $Channel -and -not ($metadata.releaseChannel -ceq 'stable' -and $Channel -ceq 'preview')) { throw 'Package and selected update channel differ.' }
}
$feedTag = "update-$Channel"
$name = 'SteamWrapper-update.json'
$root = Join-Path ([IO.Path]::GetTempPath()) ('steamwrapper-update-publish-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$old = $null
function Invoke-UpdateGh([string[]]$Arguments, [switch]$AllowMissing) {
    $global:LASTEXITCODE = 0
    $output = & $GhExecutable @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        if ($AllowMissing -and $output -match '(release not found|HTTP 404)') {
            # GitHub's pwsh wrapper exits with LASTEXITCODE after the script.
            # A handled missing channel must not leave a failing native status.
            $global:LASTEXITCODE = 0
            return $null
        }
        throw "GitHub update command failed: $($Arguments[0..1] -join ' ')."
    }
    return $output.Trim()
}
$stateText = Invoke-UpdateGh @('release', 'view', $feedTag, '--repo', $repository, '--json', 'tagName,isDraft,isPrerelease,assets') -AllowMissing
if ($null -ne $stateText) {
    $state = $stateText | ConvertFrom-Json
    if ($state.tagName -cne $feedTag -or -not $state.isPrerelease -or @($state.assets).Count -gt 1 -or
        (@($state.assets).Count -eq 1 -and ($state.assets[0].name -cne $name -or $state.assets[0].size -gt 512KB))) { throw 'The rolling metadata release has unexpected identity or assets.' }
    if (@($state.assets).Count -eq 1) {
        $null = Invoke-UpdateGh @('release', 'download', $feedTag, '--repo', $repository, '--pattern', $name, '--dir', $root)
        $old = Read-ProjectUpdateEnvelope -Path (Join-Path $root $name) -TrustPath $TrustPath -AllowExpired
        if ($old.channel -cne $Channel) { throw 'Existing metadata belongs to another channel.' }
    }
}
if ($Refresh) {
    if ($SkipMissingFeed -and $null -eq $stateText) {
        Write-Output "No $Channel update feed has been published yet; scheduled refresh skipped."
        return
    }
    if ($null -eq $old) { throw 'No previously signed channel metadata exists to refresh. Publish a version first.' }
    # Renew only previously authorized bytes; never select or sign an arbitrary
    # latest GitHub release during a scheduled run.
    $payload = Update-ProjectUpdateFreshness -Payload $old
    $IncludeCnbMirror = $null -ne $payload.release.artifact.mirrorUrl
} else {
    $payload = New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust -Channel $Channel -IncludeCnbMirror:$IncludeCnbMirror
    # The manual mirror workflow must never promote its selected historical tag
    # over a release published while it waited for the shared feed lock.
    if ($RequireCurrentRelease) {
        if (-not $IncludeCnbMirror) { throw 'Current-release maintenance must add a verified CNB mirror.' }
        Assert-ProjectUpdateCurrentRelease -Payload $payload -ExistingPayload $old
    }
    if ($null -ne $old) {
        $comparison = ([Version]$payload.release.version).CompareTo([Version]$old.release.version)
        if ($comparison -lt 0 -or ($comparison -eq 0 -and ($payload.release.tag -cne $old.release.tag -or
            $payload.release.commit -cne $old.release.commit -or $payload.release.artifact.sha256 -cne $old.release.artifact.sha256 -or
            $payload.release.artifact.bytes -ne $old.release.artifact.bytes))) { throw 'The update feed cannot roll back or replace bytes under an existing numeric version.' }
        if ($payload.sequence -le $old.sequence) { $payload.sequence = [long]$old.sequence + 1 }
    }
    $remoteCommit = Invoke-UpdateGh @('api', "repos/$repository/commits/$($metadata.tag)", '--jq', '.sha')
    if ($remoteCommit -cne $metadata.commit) { throw 'The released tag no longer matches the installer source commit.' }
    $download = Join-Path $root 'installer'
    [IO.Directory]::CreateDirectory($download) | Out-Null
    $null = Invoke-UpdateGh @('release', 'download', $metadata.tag, '--repo', $repository, '--pattern', $metadata.installerAsset.fileName, '--dir', $download)
    $installer = Get-Item -LiteralPath (Join-Path $download $metadata.installerAsset.fileName)
    if ($installer.Length -ne $payload.release.artifact.bytes -or (Get-FileHash -LiteralPath $installer.FullName).Hash.ToLowerInvariant() -cne $payload.release.artifact.sha256) { throw 'Published installer bytes do not match the update descriptor.' }
}
if ($IncludeCnbMirror -and [string]::IsNullOrWhiteSpace($env:CNB_RELEASE_TOKEN)) { throw 'A mirrored feed requires configured CNB release credentials.' }
if ($IncludeCnbMirror -and -not $Refresh) {
    # The workflow also awaits successful full-bundle mirror verification. Check
    # this selected installer again before advertising CNB to installed clients.
    Assert-CnbUpdateInstaller -Artifact $payload.release.artifact
}
$secret = $env:STEAMWRAPPER_UPDATE_PRIVATE_KEY
if ([string]::IsNullOrWhiteSpace($secret)) { throw 'STEAMWRAPPER_UPDATE_PRIVATE_KEY is required; the feed will not be published unsigned.' }
$key = [Security.Cryptography.ECDsa]::Create()
$privateBytes = $null
try {
    try {
        $privateBytes = [Convert]::FromBase64String($secret)
        $read = 0
        $key.ImportPkcs8PrivateKey($privateBytes, [ref]$read)
        if ($read -ne $privateBytes.Length) { throw 'Trailing bytes.' }
    } catch { throw 'The configured project signing key is invalid; secret values are omitted.' }
    $public = [Convert]::ToBase64String($key.ExportSubjectPublicKeyInfo())
    $configured = @($trust.keys | Where-Object subjectPublicKeyInfo -CEQ $public)
    if ($configured.Count -ne 1) { throw 'The signing secret does not match a configured public trust key.' }
    $manifest = Join-Path $root $name
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId $configured[0].keyId -Path $manifest
    $null = Read-ProjectUpdateEnvelope -Path $manifest -TrustPath $TrustPath
} finally {
    if ($null -ne $privateBytes) { [Array]::Clear($privateBytes, 0, $privateBytes.Length) }
    $secret = $null
    $key.Dispose()
}
if ($IncludeCnbMirror) { Publish-CnbUpdateFeed -ManifestPath $manifest -Payload $payload -TrustPath $TrustPath }
if ($null -eq $stateText) {
    $notes = Join-Path $root 'notes.md'
    [IO.File]::WriteAllText($notes, 'Machine-readable project-signed update metadata. Download application installers from versioned releases. This channel is refreshed weekly; it is not a software version.')
    # This tag identifies metadata, not an installer revision. A historical
    # workflow target can require workflow-write permission unavailable to
    # GITHUB_TOKEN. Software identity remains bound inside the signed payload.
    $null = Invoke-UpdateGh @('release', 'create', $feedTag, '--repo', $repository, '--target', 'main', '--draft', '--prerelease', '--latest=false', '--title', "SteamWrapper $Channel update feed", '--notes-file', $notes)
}
# This is the sole mutable asset and lives under update-*, never a version tag.
$null = Invoke-UpdateGh @('release', 'upload', $feedTag, $manifest, '--repo', $repository, '--clobber')
$check = Join-Path $root 'verify'
[IO.Directory]::CreateDirectory($check) | Out-Null
$null = Invoke-UpdateGh @('release', 'download', $feedTag, '--repo', $repository, '--pattern', $name, '--dir', $check)
if ((Get-FileHash -LiteralPath (Join-Path $check $name)).Hash -cne (Get-FileHash -LiteralPath $manifest).Hash) { throw 'Downloaded update metadata differs from the signed bytes.' }
if ($null -eq $stateText -or $state.isDraft) {
    $null = Invoke-UpdateGh @('release', 'edit', $feedTag, '--repo', $repository, '--target', 'main', '--draft=false', '--prerelease', '--latest=false')
}
Write-Output "Published verified $Channel update metadata for $($payload.release.tag), sequence $($payload.sequence)."
