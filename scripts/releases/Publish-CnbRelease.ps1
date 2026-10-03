# CNB OpenAPI contracts are also distributed by official @cnbcool/cnb-cli
# 1.16.19: get-tag, get-release-by-tag, post-release-asset-upload-url, and
# post-release-asset-upload-confirmation. See https://api.cnb.cool/.
[CmdletBinding()]
param(
    [string]$PackageDirectory,
    [string]$Repository = 'Nesoriel/SteamWrapper'
)

function Invoke-CnbRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [string]$Repository = 'Nesoriel/SteamWrapper',
        [Net.Http.HttpClient]$Client
    )
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest
    if ($Repository -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+$' -or $Repository.Split('/') -contains '..') { throw 'Invalid CNB repository.' }
    $directory = (Resolve-Path -LiteralPath $PackageDirectory).Path
    if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Release package directory must not be a link.' }
    $metadataPath = Join-Path $directory 'release.json'
    if ((Get-Item -LiteralPath $metadataPath).Length -gt 2MB) { throw 'Release metadata is too large.' }
    # Validate the exact downloaded bundle, including compressed file inventory,
    # Runner contract/hash and included runtime, before any authenticated request.
    $metadata = & (Join-Path $PSScriptRoot '../windows/Test-WinUIReleasePackage.ps1') -PackageDirectory $directory
    . (Join-Path $PSScriptRoot '../windows/WinUIInstallableRelease.ps1')
    if ($metadata.schemaVersion -notin @(1, 2) -or $metadata.tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -or $metadata.commit -notmatch '^[a-f0-9]{40}$' -or $metadata.platform -ne 'win-x64' -or $metadata.releaseChannel -ne 'preview' -or $metadata.githubPrerelease -ne $true -or $metadata.signed -ne $false -or $metadata.installer -ne ($metadata.schemaVersion -eq 2)) { throw 'Unsupported release metadata or preview flags.' }
    $tag = $metadata.tag
    $archiveName = "SteamWrapper-$tag-win-x64.zip"
    if ($metadata.archive.fileName -cne $archiveName) { throw 'Unexpected release archive name.' }
    $assetNames = @(Get-WinUIReleaseAssetNames $metadata)
    $assets = @{}
    foreach ($name in $assetNames) {
        $path = Join-Path $directory $name
        $file = Get-Item -LiteralPath $path
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -le 0 -or $file.Length -gt 1GB) { throw 'Release assets must be regular, nonempty files within the size limit.' }
        $assets[$name] = @{ Path = $path; Bytes = $file.Length; Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    if ($assets['SHA256SUMS'].Bytes -gt 16KB -or $assets["$tag.en.md"].Bytes -gt 256KB -or $assets["$tag.zh-CN.md"].Bytes -gt 256KB) { throw 'Release notes or checksums are too large.' }
    $checksums = @{}
    foreach ($line in [IO.File]::ReadAllLines($assets['SHA256SUMS'].Path)) {
        if ($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$' -or $checksums.ContainsKey($Matches[2])) { throw 'Invalid release checksum file.' }
        $checksums[$Matches[2]] = $Matches[1]
    }
    if ($checksums.Count -ne $assetNames.Count - 1) { throw 'Release checksum file must list every payload/metadata asset exactly once.' }
    foreach ($name in $assetNames | Where-Object { $_ -cne 'SHA256SUMS' }) {
        if (-not $checksums.ContainsKey($name) -or $checksums[$name] -cne $assets[$name].Hash) { throw 'Release checksum mismatch.' }
    }
    if ($metadata.archive.sha256 -cne $assets[$archiveName].Hash -or $metadata.archive.bytes -ne $assets[$archiveName].Bytes) { throw 'Release archive checksum or size mismatch.' }
    $token = $env:CNB_RELEASE_TOKEN
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'CNB_RELEASE_TOKEN is required with repo-release read/write permission.' }
    $base = "https://api.cnb.cool/$Repository/-/"
    $ownedClient = $null -eq $Client
    if ($ownedClient) {
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $handler.UseCookies = $false
        $Client = [Net.Http.HttpClient]::new($handler)
        $Client.Timeout = [TimeSpan]::FromMinutes(10)
    }
    if ($null -ne $Client.DefaultRequestHeaders.Authorization) { throw 'CNB HTTP client must not have default authorization headers.' }
    $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(10))

    function Test-SecureStorageUri([string]$Value) {
        $uri = $null
        if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -ne '' -or $uri.IsLoopback -or $uri.Fragment -ne '' -or [Uri]::CheckHostName($uri.DnsSafeHost) -ne [UriHostNameType]::Dns) { throw 'Invalid CNB storage URL.' }
        return $uri
    }
    function Send-CnbRequest([string]$Method, [Uri]$Uri, [bool]$Authenticate, $Json, [string]$File) {
        if ($Authenticate -and ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'api.cnb.cool' -or $Uri.Port -ne 443 -or $Uri.UserInfo -ne '' -or -not $Uri.AbsoluteUri.StartsWith($base, [StringComparison]::Ordinal))) { throw 'CNB authenticated request URL is outside the selected repository.' }
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
        try {
            if ($Authenticate) {
                $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
                $request.Headers.Accept.ParseAdd('application/vnd.cnb.api+json')
            }
            if ($null -ne $Json) { $request.Content = [Net.Http.StringContent]::new(($Json | ConvertTo-Json -Depth 8 -Compress), [Text.Encoding]::UTF8, 'application/json') }
            if ($File) {
                $request.Content = [Net.Http.StreamContent]::new([IO.File]::OpenRead($File))
                $request.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
            }
            try { return $Client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $deadline.Token).GetAwaiter().GetResult() }
            catch { throw "CNB $Method request failed; credentials and signed URLs are omitted." }
        } finally { $request.Dispose() }
    }
    function Read-CnbJson([string]$Method, [string]$Url, $Json = $null, [switch]$AllowMissing) {
        $response = Send-CnbRequest $Method ([Uri]$Url) $true $Json ''
        try {
            $status = [int]$response.StatusCode
            if ($AllowMissing -and $status -eq 404) { return $null }
            if ($status -lt 200 -or $status -ge 300) { throw "CNB $Method request returned HTTP $status." }
            if ($response.Content.Headers.ContentLength -gt 1MB) { throw 'CNB API JSON exceeds the size limit.' }
            $stream = $response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
            $memory = [IO.MemoryStream]::new()
            try {
                $buffer = [byte[]]::new(8192)
                while (($count = $stream.ReadAsync($buffer, 0, $buffer.Length, $deadline.Token).GetAwaiter().GetResult()) -gt 0) {
                    if ($memory.Length + $count -gt 1MB) { throw 'CNB API JSON exceeds the size limit.' }
                    $memory.Write($buffer, 0, $count)
                }
                $text = [Text.Encoding]::UTF8.GetString($memory.ToArray())
                if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
                try { return $text | ConvertFrom-Json -AsHashtable }
                catch { throw 'CNB API returned invalid JSON.' }
            } finally { $stream.Dispose(); $memory.Dispose() }
        } finally { $response.Dispose() }
    }
    function Assert-CnbDownload([string]$Name) {
        $url = $base + 'releases/download/' + [Uri]::EscapeDataString($tag) + '/' + [Uri]::EscapeDataString($Name)
        $response = Send-CnbRequest 'GET' ([Uri]$url) $true $null ''
        try {
            if ([int]$response.StatusCode -eq 302) {
                $location = $response.Headers.Location
                if ($null -eq $location) { throw 'CNB download redirect has no location.' }
                $storageUri = Test-SecureStorageUri $location.AbsoluteUri
                $response.Dispose()
                # The storage URL is signed. Never send the repository bearer token.
                $response = Send-CnbRequest 'GET' $storageUri $false $null ''
            }
            if ([int]$response.StatusCode -ne 200) { throw "CNB asset download returned HTTP $([int]$response.StatusCode)." }
            $expected = $assets[$Name]
            $stream = $response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
            $hasher = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
            try {
                $buffer = [byte[]]::new(65536)
                $length = 0L
                while (($count = $stream.ReadAsync($buffer, 0, $buffer.Length, $deadline.Token).GetAwaiter().GetResult()) -gt 0) {
                    $length += $count
                    if ($length -gt $expected.Bytes) { throw 'CNB published asset bytes differ; overwrite refused.' }
                    $hasher.AppendData($buffer, 0, $count)
                }
                $hash = [Convert]::ToHexString($hasher.GetHashAndReset()).ToLowerInvariant()
                if ($length -ne $expected.Bytes -or $hash -cne $expected.Hash) { throw 'CNB published asset bytes differ; overwrite refused.' }
            } finally { $stream.Dispose(); $hasher.Dispose() }
        } finally { $response.Dispose() }
    }
    function Get-CnbReleaseAssets($State, [bool]$Complete = $false, [string]$ExpectedId = '', $ExpectedDraft = $null, [switch]$RequirePreview) {
        # CNB returns refs/tags/<tag> for published releases; commit.sha from
        # get-tag is the authoritative resolution of that ref, checked separately.
        if ($null -eq $State -or $State.tag_name -cne $tag -or $State.tag_commitish -cnotin @($metadata.commit, "refs/tags/$tag") -or $State.id -notmatch '^[A-Za-z0-9_-]+$' -or ($ExpectedId -and $State.id -cne $ExpectedId)) { throw 'CNB release identity does not match the tag and package commit.' }
        if ($State.draft -isnot [bool] -or $State.prerelease -isnot [bool] -or ($null -ne $ExpectedDraft -and $State.draft -ne $ExpectedDraft)) { throw 'CNB release draft state does not match the expected publication stage.' }
        if ($RequirePreview -and -not $State.prerelease) { throw 'Existing CNB release is not the expected preview.' }
        $found = @{}
        foreach ($asset in $State.assets) {
            if ($asset.name -cnotin $assetNames) { throw 'CNB release contains an unexpected asset; modification refused.' }
            if ($found.ContainsKey($asset.name)) { throw 'CNB release has duplicate assets.' }
            if ($asset.size -ne $assets[$asset.name].Bytes) { throw 'CNB published asset bytes differ; overwrite refused.' }
            $found[$asset.name] = $asset
        }
        if ($Complete -and $found.Count -ne $assetNames.Count) { throw 'CNB release assets are incomplete; publication refused.' }
        return $found
    }

    try {
        # The source-sync job must have pushed this exact tag first. Resolve the
        # commit through get-tag rather than accepting an arbitrary commitish.
        $remoteTag = Read-CnbJson 'GET' ($base + 'git/tags/' + [Uri]::EscapeDataString($tag))
        if ($remoteTag.name -cne $tag -or $remoteTag.commit.sha -cne $metadata.commit) { throw 'CNB tag commit does not match the package.' }
        $release = Read-CnbJson 'GET' ($base + 'releases/tags/' + [Uri]::EscapeDataString($tag)) -AllowMissing
        $created = $null -eq $release
        $notes = [IO.File]::ReadAllText($assets["$tag.en.md"].Path) + [char]10 + [char]10 + [IO.File]::ReadAllText($assets["$tag.zh-CN.md"].Path)
        $body = @{ tag_name = $tag; target_commitish = $metadata.commit; name = "SteamWrapper $tag (Windows preview)"; body = $notes; draft = $true; prerelease = $true; make_latest = 'false' }
        if ($created) { $release = Read-CnbJson 'POST' ($base + 'releases') $body }
        $existing = Get-CnbReleaseAssets $release
        $id = $release.id
        if ($created) { $null = Get-CnbReleaseAssets $release -ExpectedDraft $true -RequirePreview }
        if (-not $release.draft) {
            if ($existing.Count -eq 0) {
                # Migrate an old notes-only release at this exact source commit.
                # Hide it while adding attachments; never alter a populated release.
                $null = Read-CnbJson 'PATCH' ($base + "releases/$id") @{ draft = $true; prerelease = $true; make_latest = 'false' }
            } else {
                $null = Get-CnbReleaseAssets $release -Complete $true -RequirePreview
                foreach ($name in $assetNames) { Assert-CnbDownload $name }
                return "https://cnb.cool/$Repository/-/releases/tag/$tag"
            }
        } elseif ($existing.Count -gt 0) {
            $null = Get-CnbReleaseAssets $release -RequirePreview
        }
        # Verify every existing expected asset before writing any new asset.
        foreach ($name in $assetNames) {
            if ($existing.ContainsKey($name)) {
                Assert-CnbDownload $name
            }
        }
        $missing = @($assetNames | Where-Object { -not $existing.ContainsKey($_) })
        foreach ($name in $missing) {
            $upload = Read-CnbJson 'POST' ($base + "releases/$id/asset-upload-url") @{ asset_name = $name; size = $assets[$name].Bytes; overwrite = $false; ttl = 0 }
            $storageUri = Test-SecureStorageUri $upload.upload_url
            $confirmation = $null
            $expectedPrefix = $base + "releases/$id/asset-upload-confirmation/"
            if (-not [Uri]::TryCreate($upload.verify_url, [UriKind]::Absolute, [ref]$confirmation) -or $confirmation.Scheme -ne 'https' -or $confirmation.Host -ne 'api.cnb.cool' -or $confirmation.Port -ne 443 -or $confirmation.UserInfo -ne '' -or $confirmation.Query -ne '' -or $confirmation.Fragment -ne '' -or -not $confirmation.AbsoluteUri.StartsWith($expectedPrefix, [StringComparison]::Ordinal) -or $confirmation.AbsolutePath -match '(?i)%2e|%2f|%5c' -or $confirmation.AbsoluteUri.Substring($expectedPrefix.Length).Split('/').Count -ne 2) { throw 'Invalid CNB confirmation URL; upload refused.' }
            $response = Send-CnbRequest 'PUT' $storageUri $false $null $assets[$name].Path
            try { if (-not $response.IsSuccessStatusCode) { throw "CNB asset upload returned HTTP $([int]$response.StatusCode)." } }
            finally { $response.Dispose() }
            $null = Read-CnbJson 'POST' ($confirmation.AbsoluteUri + '?ttl=0')
            Assert-CnbDownload $name
        }
        $release = Read-CnbJson 'GET' ($base + 'releases/tags/' + [Uri]::EscapeDataString($tag))
        $null = Get-CnbReleaseAssets $release -Complete $true -ExpectedId $id -ExpectedDraft $true -RequirePreview
        $remoteTag = Read-CnbJson 'GET' ($base + 'git/tags/' + [Uri]::EscapeDataString($tag))
        if ($remoteTag.name -cne $tag -or $remoteTag.commit.sha -cne $metadata.commit) { throw 'CNB tag commit changed before publication; draft retained.' }
        $body.Remove('tag_name')
        $body.Remove('target_commitish')
        $body.draft = $false
        $null = Read-CnbJson 'PATCH' ($base + "releases/$id") $body
        $release = Read-CnbJson 'GET' ($base + 'releases/tags/' + [Uri]::EscapeDataString($tag))
        $null = Get-CnbReleaseAssets $release -Complete $true -ExpectedId $id -ExpectedDraft $false -RequirePreview
        return "https://cnb.cool/$Repository/-/releases/tag/$tag"
    } finally { $deadline.Dispose(); if ($ownedClient) { $Client.Dispose() } }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($PackageDirectory)) { throw '-PackageDirectory is required.' }
    Invoke-CnbRelease -PackageDirectory $PackageDirectory -Repository $Repository
}
