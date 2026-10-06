# Verification of publicly downloaded releases is deliberately separate from
# the complete internal package validator. A three-asset download cannot prove
# an internal payload inventory or deployment/Runner contracts.
. (Join-Path $PSScriptRoot 'ProjectUpdates.ps1')

function Assert-WinUIPublicReleaseState {
    param($ReleaseState, [string]$Tag, [string]$Commit, [string[]]$AssetNames, [switch]$RequireDigest, [switch]$SkipReleaseTarget)
    $identity = Get-WinUIReleaseTag $Tag
    if ($Commit -cnotmatch '^[a-f0-9]{40}$') { throw 'Public release verification requires an exact lowercase source commit.' }
    if ($ReleaseState -isnot [pscustomobject]) { throw 'Public release API state must be a JSON object.' }
    foreach ($name in @('tag_name', 'target_commitish', 'draft', 'prerelease', 'assets')) {
        if ($null -eq $ReleaseState.PSObject.Properties[$name]) { throw "Public release API state is missing $name." }
    }
    if ($ReleaseState.tag_name -cne $Tag -or (-not $SkipReleaseTarget -and $ReleaseState.target_commitish -cne $Commit) -or
        $ReleaseState.draft -isnot [bool] -or $ReleaseState.draft -or
        $ReleaseState.prerelease -isnot [bool] -or $ReleaseState.prerelease -ne $identity.Prerelease -or
        @($ReleaseState.assets).Count -ne $AssetNames.Count) { throw 'Public release identity, channel or complete asset inventory does not match the selected release.' }
    $found = @{}
    foreach ($asset in $ReleaseState.assets) {
        if ($asset -isnot [pscustomobject]) { throw 'Public release API assets must be JSON objects.' }
        foreach ($name in @('name', 'size', 'state')) {
            if ($null -eq $asset.PSObject.Properties[$name]) { throw "Public release API asset is missing $name." }
        }
        if ($asset.name -isnot [string] -or $asset.name -cnotin $AssetNames -or $found.ContainsKey($asset.name) -or
            ($asset.size -isnot [int] -and $asset.size -isnot [long]) -or $asset.size -lt 1 -or
            $asset.state -cne 'uploaded') { throw 'Public release API assets contain an unexpected/duplicate name, invalid size or incomplete upload.' }
        $limit = if ($asset.name -ceq 'SHA256SUMS') { 16KB }
        elseif ($asset.name.EndsWith('-setup.exe', [StringComparison]::Ordinal)) { 512MB }
        elseif ($asset.name.EndsWith('.md', [StringComparison]::Ordinal)) { 256KB }
        elseif ($asset.name.EndsWith('.json', [StringComparison]::Ordinal)) { 2MB }
        else { 1GB }
        if ($asset.size -gt $limit) { throw 'Public release API asset exceeds its bounded size limit.' }
        $digest = $asset.PSObject.Properties['digest']
        if ($RequireDigest -or ($null -ne $digest -and $null -ne $digest.Value)) {
            if ($null -eq $digest -or $digest.Value -isnot [string] -or $digest.Value -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'Public release API assets require exact SHA-256 digests.' }
        }
        $found[$asset.name] = $asset
    }
    return $found
}

function New-WinUIPublicInstallerDescriptor {
    [CmdletBinding(DefaultParameterSetName = 'Signed')]
    param(
        [Parameter(Mandatory)]$ReleaseState, [Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory, ParameterSetName = 'Baseline')][switch]$BaselineOnly,
        [Parameter(ParameterSetName = 'Signed')][string]$EnvelopePath,
        [Parameter(ParameterSetName = 'Signed')][string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json')
    )
    $identity = Get-WinUIReleaseTag $Tag
    if ([Version]$identity.Version -lt [Version]'0.2.8') { throw 'PublicApiInstaller descriptors start at version 0.2.8; historical complete metadata remains separate.' }
    $archiveName = "SteamWrapper-$Tag-win-x64.zip"; $installerName = "SteamWrapper-$Tag-win-x64-setup.exe"
    $assets = Assert-WinUIPublicReleaseState -ReleaseState $ReleaseState -Tag $Tag -Commit $Commit -AssetNames @($archiveName, $installerName, 'SHA256SUMS') -RequireDigest
    if ($PSCmdlet.ParameterSetName -ceq 'Signed') {
        if ([string]::IsNullOrWhiteSpace($EnvelopePath)) { throw 'Current public installer targets require an existing signed update envelope; API-only evidence needs explicit baseline-only scope.' }
        # Current target acceptance must never fall back to historical API-only
        # evidence after a missing, expired, invalid or mismatched signature.
        $payload = Read-ProjectUpdateEnvelope -Path $EnvelopePath -TrustPath $TrustPath
        if ($payload.release.tag -cne $Tag -or $payload.release.commit -cne $Commit -or $payload.release.version -cne $identity.Version -or
            $payload.release.minimumWindowsVersion -cne '10.0.26100.0' -or $payload.release.artifact.bytes -ne $assets[$installerName].size -or
            $payload.release.artifact.sha256 -cne $assets[$installerName].digest.Substring(7)) { throw 'Current public installer target differs from its project-signed update authorization.' }
    } elseif (-not $BaselineOnly) { throw 'API-only historical installer evidence requires explicit baseline-only scope.' }
    # This API receipt describes a public installer. It deliberately does not
    # impersonate private release.json, build metadata or a signed update feed.
    return [pscustomobject][ordered]@{
        schemaVersion = 1; kind = 'PublicApiInstaller'; publicAssetLayout = 3
        verificationKind = $(if ($BaselineOnly) { 'public-api-baseline' } else { 'project-signature' })
        baselineScope = [bool]$BaselineOnly; signatureVerified = -not [bool]$BaselineOnly
        tag = $Tag; version = $identity.Version; commit = $Commit; releaseChannel = $identity.Channel
        archive = [pscustomobject]@{ fileName = $archiveName; bytes = $assets[$archiveName].size; sha256 = $assets[$archiveName].digest.Substring(7) }
        installerAsset = [pscustomobject]@{ fileName = $installerName; bytes = $assets[$installerName].size; sha256 = $assets[$installerName].digest.Substring(7) }
    }
}

function Assert-WinUIPublicAssetBytes {
    param([string]$PackageDirectory, $Assets)
    $directory = [IO.Path]::GetFullPath($PackageDirectory)
    $null = Assert-WinUIReleasePath $directory $directory
    $files = @(Get-ChildItem -LiteralPath $directory -Force)
    if ($files.Count -ne $Assets.Count) { throw 'Public download directory must contain exactly the complete expected asset inventory.' }
    foreach ($file in $files) {
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $Assets.ContainsKey($file.Name) -or $file.Name -cne $Assets[$file.Name].name) { throw 'Public download assets must be the exact regular, non-linked API files.' }
        $asset = $Assets[$file.Name]
        if ($file.Length -ne $asset.size -or $file.Length -lt 1) { throw 'Public download bytes differ from the GitHub API size.' }
        $digest = $asset.PSObject.Properties['digest']
        if ($null -ne $digest -and $null -ne $digest.Value -and
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $digest.Value.Substring(7)) { throw 'Public download bytes differ from the GitHub API SHA-256 digest.' }
    }
}

function Get-WinUIPublicSourceNotes {
    param([string]$RepositoryRoot, [string]$Tag, [string]$Commit)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $null = Assert-WinUIReleasePath $root $root
    $blob = "$Commit`:releases/$Tag.zh-CN.md"
    # Bound the blob before reading it. git show reads the exact selected commit,
    # so dirty files and a different checkout HEAD cannot supply mirror notes.
    $global:LASTEXITCODE = 0
    $lengthText = & git -C $root cat-file -s $blob 2>$null
    if ($LASTEXITCODE -ne 0 -or @($lengthText).Count -ne 1 -or $lengthText -notmatch '^[0-9]+$' -or [long]$lengthText -lt 1 -or [long]$lengthText -gt 256KB) { throw 'Exact source-commit Chinese release notes are missing or exceed their bounded limit.' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    foreach ($argument in @('-C', $root, 'show', $blob)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
        $null = $process.Start()
        $read = $process.StandardOutput.ReadToEndAsync(); $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Exact source-commit release notes could not be read within the time limit.' }
        $text = $read.GetAwaiter().GetResult(); $null = $errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or [Text.Encoding]::UTF8.GetByteCount($text) -gt 256KB -or
            $text -notmatch ('(?m)^#{1,6}\s+.*' + [regex]::Escape($Tag) + '(?:\s|$)') -or
            @($text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -lt 2) { throw 'Exact source-commit release notes require a matching heading and nonempty body.' }
        return $text
    } finally { $process.Dispose() }
}

function Test-WinUIPublicReleaseDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [Parameter(Mandatory)][string]$EnvelopePath,
        [Parameter(Mandatory)][string]$TrustPath,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)]$ReleaseState,
        [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
        [string]$NotesPath,
        [switch]$VerifyNotes
    )
    $identity = Get-WinUIReleaseTag $Tag
    if ([Version]$identity.Version -lt [Version]'0.2.8') { throw 'Compact public download verification starts at version 0.2.8; historical packages retain their complete validator.' }
    $directory = [IO.Path]::GetFullPath($PackageDirectory)
    $null = Assert-WinUIReleasePath $directory $directory
    foreach ($path in @($EnvelopePath, $TrustPath)) { $null = Assert-WinUIReleasePath $path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))) }
    # A historical mirror may use an expired authorized envelope. Cryptographic
    # signatures, exact URLs/contracts and lifetime shape remain required; feed
    # maintenance separately compares the current authorized release.
    $payload = Read-ProjectUpdateEnvelope -Path $EnvelopePath -TrustPath $TrustPath -AllowExpired
    if ($payload.release.tag -cne $Tag -or $payload.release.commit -cne $Commit -or $payload.release.version -cne $identity.Version -or
        $payload.release.minimumWindowsVersion -cne '10.0.26100.0') { throw 'Signed update authorization does not identify the selected exact tag, commit and Windows release.' }
    $zipName = "SteamWrapper-$Tag-win-x64.zip"
    $setupName = "SteamWrapper-$Tag-win-x64-setup.exe"
    $assets = Assert-WinUIPublicReleaseState -ReleaseState $ReleaseState -Tag $Tag -Commit $Commit -AssetNames @($zipName, $setupName, 'SHA256SUMS') -RequireDigest
    Assert-WinUIPublicAssetBytes -PackageDirectory $directory -Assets $assets
    $setup = $assets[$setupName]
    if ($setup.size -ne $payload.release.artifact.bytes -or $setup.digest.Substring(7) -cne $payload.release.artifact.sha256) { throw 'Public Setup bytes differ from the exact project-signed installer authorization.' }
    $checksums = @{}
    $text = Read-WinUIReleaseText (Join-Path $directory 'SHA256SUMS') $directory 16KB
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $directory 'SHA256SUMS'))) {
        if ($line -cnotmatch '^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$' -or $Matches[2] -cnotin @($zipName, $setupName) -or $checksums.ContainsKey($Matches[2])) { throw 'Compact public checksums must contain exactly the two payload lines, without internal metadata.' }
        $checksums[$Matches[2]] = $Matches[1]
    }
    if ($checksums.Count -ne 2) { throw 'Compact public checksums must contain exactly the two payload lines.' }
    foreach ($name in @($zipName, $setupName)) {
        if (-not $checksums.ContainsKey($name) -or $checksums[$name] -cne $assets[$name].digest.Substring(7)) { throw 'Compact public checksum differs from the downloaded/API payload bytes.' }
    }
    $notes = Get-WinUIPublicSourceNotes -RepositoryRoot $RepositoryRoot -Tag $Tag -Commit $Commit
    if (-not $NotesPath) { $NotesPath = Join-Path ($directory + '-verification') 'notes.zh-CN.md' }
    $notesFull = [IO.Path]::GetFullPath($NotesPath)
    $parent = [IO.Path]::GetDirectoryName($directory)
    $null = Assert-WinUIReleasePath $notesFull $parent
    if ($notesFull.StartsWith($directory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Mirror verification notes must remain outside the public three-asset directory.' }
    if ($VerifyNotes) {
        $saved = Read-WinUIReleaseText $notesFull $parent 256KB
        if ($saved -cne $notes) { throw 'Saved mirror notes differ from the exact source-commit notes.' }
    } else {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($notesFull)) | Out-Null
        [IO.File]::WriteAllText($notesFull, $notes, [Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 3; tag = $Tag; version = $identity.Version; commit = $Commit
        platform = 'win-x64'; minimumWindowsVersion = $payload.release.minimumWindowsVersion
        releaseChannel = $identity.Channel; tagPrerelease = $identity.Prerelease; githubPrerelease = $identity.Prerelease
        signed = $false; installer = $true; portable = $true
        archive = [pscustomobject]@{ fileName = $zipName; bytes = $assets[$zipName].size; sha256 = $assets[$zipName].digest.Substring(7) }
        installerAsset = [pscustomobject]@{ fileName = $setupName; bytes = $setup.size; sha256 = $setup.digest.Substring(7) }
        notesPath = $notesFull
    }
}

function Read-WinUIPublicReleaseVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [Parameter(Mandatory)][string]$VerificationPath,
        [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
        [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..')
    )
    $directory = [IO.Path]::GetFullPath($PackageDirectory)
    $parent = [IO.Path]::GetDirectoryName($directory)
    $receiptPath = Assert-WinUIReleasePath $VerificationPath $parent
    $verification = [IO.Path]::GetDirectoryName($receiptPath)
    if ($receiptPath.StartsWith($directory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Verification receipt must remain outside the public assets.' }
    $receipt = ConvertFrom-WinUIInstallableJson (Read-WinUIReleaseText $receiptPath $parent 16KB)
    Assert-WinUIInstallableFields $receipt @('schemaVersion', 'repository', 'tag', 'commit')
    $trust = Read-ProjectUpdateTrust $TrustPath
    if ($receipt.schemaVersion -ne 1 -or $receipt.repository -cne $trust.githubRepository -or $receipt.tag -isnot [string] -or $receipt.commit -isnot [string]) { throw 'Unsupported public release verification receipt.' }
    $state = ConvertFrom-WinUIInstallableJson (Read-WinUIReleaseText (Join-Path $verification 'release-state.json') $verification 2MB)
    $descriptor = Test-WinUIPublicReleaseDirectory -PackageDirectory $directory -EnvelopePath (Join-Path $verification 'signed-update.json') -TrustPath $TrustPath -Tag $receipt.tag -Commit $receipt.commit -ReleaseState $state -RepositoryRoot $RepositoryRoot -NotesPath (Join-Path $verification 'notes.zh-CN.md') -VerifyNotes
    $descriptor | Add-Member -NotePropertyName verificationPath -NotePropertyValue $receiptPath
    return $descriptor
}

function Get-PublishedReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$PackageDirectory,
        [string]$EnvelopePath,
        [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
        [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
        [string]$VerificationPath,
        [string]$GhExecutable = 'gh'
    )
    $identity = Get-WinUIReleaseTag $Tag
    if ($Commit -cnotmatch '^[a-f0-9]{40}$') { throw 'Published download requires an exact lowercase source commit.' }
    $compact = [Version]$identity.Version -ge [Version]'0.2.8'
    $trust = Read-ProjectUpdateTrust $TrustPath
    $repository = $trust.githubRepository
    $directory = [IO.Path]::GetFullPath($PackageDirectory)
    $null = Assert-WinUIReleasePath $directory $directory
    if (Test-Path -LiteralPath $directory) { throw 'Published release download requires a fresh output directory; existing files are never overwritten.' }
    $receiptPath = $null
    if ($compact) {
        if (-not $EnvelopePath) { throw 'Compact public downloads require an existing project-signed update envelope.' }
        $payload = Read-ProjectUpdateEnvelope -Path $EnvelopePath -TrustPath $TrustPath -AllowExpired
        if ($payload.release.tag -cne $Tag -or $payload.release.commit -cne $Commit) { throw 'Existing signed update envelope does not authorize the selected release.' }
        if (-not $VerificationPath) { $VerificationPath = Join-Path ($directory + '-verification') 'receipt.json' }
        $receiptPath = Assert-WinUIReleasePath $VerificationPath ([IO.Path]::GetDirectoryName($directory))
        $verification = [IO.Path]::GetDirectoryName($receiptPath)
        if ($receiptPath.StartsWith($directory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $verification)) { throw 'Public verification requires a fresh external directory, without overwriting an existing receipt.' }
    }
    function Invoke-PublicReleaseGh([string[]]$Arguments) {
        $global:LASTEXITCODE = 0
        $output = & $GhExecutable @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Read-only GitHub public-release command failed; command output and credentials are omitted.' }
        if ([Text.Encoding]::UTF8.GetByteCount($output) -gt 2MB) { throw 'GitHub public-release response exceeds its bounded limit.' }
        return $output.Trim()
    }
    $endpoint = "repos/$repository/commits/" + [Uri]::EscapeDataString($Tag)
    $remoteCommit = Invoke-PublicReleaseGh @('api', $endpoint, '--jq', '.sha')
    if ($remoteCommit -cne $Commit) { throw 'Published GitHub tag does not resolve to the selected exact source commit.' }
    $stateText = Invoke-PublicReleaseGh @('api', ("repos/$repository/releases/tags/" + [Uri]::EscapeDataString($Tag)), '--method', 'GET')
    $state = ConvertFrom-WinUIInstallableJson $stateText
    $zipName = "SteamWrapper-$Tag-win-x64.zip"; $setupName = "SteamWrapper-$Tag-win-x64-setup.exe"
    $names = if ($compact) { @($zipName, $setupName, 'SHA256SUMS') }
    else { @($zipName, "$Tag.en.md", "$Tag.zh-CN.md", 'release.json', 'SHA256SUMS', 'portable-release.json', $setupName) }
    $assets = Assert-WinUIPublicReleaseState -ReleaseState $state -Tag $Tag -Commit $Commit -AssetNames $names -RequireDigest -SkipReleaseTarget:(-not $compact)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    foreach ($name in $names) {
        $null = Invoke-PublicReleaseGh @('release', 'download', $Tag, '--repo', $repository, '--pattern', $name, '--dir', $directory)
        $file = Get-Item -LiteralPath (Join-Path $directory $name)
        if ($file.PSIsContainer -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint -or $file.Length -ne $assets[$name].size) { throw 'Published asset download is not the exact bounded API file.' }
        $digest = $assets[$name].PSObject.Properties['digest']
        if ($null -ne $digest -and $null -ne $digest.Value -and (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() -cne $digest.Value.Substring(7)) { throw 'Published asset download differs from its GitHub API SHA-256 digest.' }
    }
    Assert-WinUIPublicAssetBytes -PackageDirectory $directory -Assets $assets
    if ((Invoke-PublicReleaseGh @('api', $endpoint, '--jq', '.sha')) -cne $Commit) { throw 'Published GitHub tag moved during public download; verification receipt was not written.' }
    if (-not $compact) {
        $descriptor = Test-WinUIReleaseArtifactDirectory -PackageDirectory $directory
        if ($descriptor.schemaVersion -ne 2 -or $descriptor.tag -cne $Tag -or $descriptor.commit -cne $Commit) { throw 'Historical public assets must remain the original exact-tag schema-2 complete package.' }
        return $descriptor
    }
    $descriptor = Test-WinUIPublicReleaseDirectory -PackageDirectory $directory -EnvelopePath $EnvelopePath -TrustPath $TrustPath -Tag $Tag -Commit $Commit -ReleaseState $state -RepositoryRoot $RepositoryRoot -NotesPath (Join-Path $verification 'notes.zh-CN.md')
    [IO.File]::Copy([IO.Path]::GetFullPath($EnvelopePath), (Join-Path $verification 'signed-update.json'), $false)
    [IO.File]::WriteAllText((Join-Path $verification 'release-state.json'), $stateText, [Text.UTF8Encoding]::new($false))
    $receipt = [ordered]@{ schemaVersion = 1; repository = $repository; tag = $Tag; commit = $Commit }
    [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Compress) + "`n", [Text.UTF8Encoding]::new($false))
    # Re-read the saved evidence rather than returning only the earlier in-memory
    # authorization, so a changed source envelope or colliding path fails here.
    return Read-WinUIPublicReleaseVerification -PackageDirectory $directory -VerificationPath $receiptPath -TrustPath $TrustPath -RepositoryRoot $RepositoryRoot
}
