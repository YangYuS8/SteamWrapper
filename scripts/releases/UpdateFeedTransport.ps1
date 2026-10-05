# CNB's official OpenAPI contracts (also exposed by cnb-cli): create-tag,
# post-release, post-release-asset-upload-url and upload confirmation.
function Invoke-CnbUpdateHttp {
    param([string]$Method, [Uri]$Uri, $Json, [string]$File, [switch]$Authenticated,
        [long]$MaximumBytes = 1MB, [Net.Http.HttpClient]$Client)
    if ($Uri.Scheme -ne 'https' -or $Uri.Port -ne 443 -or $Uri.UserInfo -ne '' -or $Uri.Fragment -ne '' -or $Uri.IsLoopback -or $Uri.HostNameType -ne [UriHostNameType]::Dns) { throw 'Unsafe CNB update URL.' }
    if ($Authenticated -and ($Uri.Host -cne 'api.cnb.cool' -or -not $Uri.AbsolutePath.StartsWith('/Nesoriel/SteamWrapper/-/', [StringComparison]::Ordinal))) { throw 'CNB update authentication is restricted to the official repository API.' }
    $owned = $null -eq $Client
    if ($owned) {
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $handler.UseCookies = $false
        $Client = [Net.Http.HttpClient]::new($handler)
        $Client.Timeout = [TimeSpan]::FromMinutes(10)
    }
    if ($null -ne $Client.DefaultRequestHeaders.Authorization) { throw 'CNB transport must not use default authorization.' }
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    $response = $null
    try {
        if ($Authenticated) {
            if ([string]::IsNullOrWhiteSpace($env:CNB_RELEASE_TOKEN)) { throw 'CNB release credentials are not configured.' }
            $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $env:CNB_RELEASE_TOKEN)
            $request.Headers.Accept.ParseAdd('application/vnd.cnb.api+json')
        }
        if ($null -ne $Json) { $request.Content = [Net.Http.StringContent]::new(($Json | ConvertTo-Json -Depth 8 -Compress), [Text.Encoding]::UTF8, 'application/json') }
        if ($File) { $request.Content = [Net.Http.StreamContent]::new([IO.File]::OpenRead($File)); $request.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream') }
        try { $response = $Client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult() }
        catch { throw 'CNB update request failed; credentials and storage URLs are omitted.' }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $memory = [IO.MemoryStream]::new()
        try {
            if ($response.Content.Headers.ContentLength -gt $MaximumBytes) { throw 'CNB update response exceeds its size limit.' }
            $buffer = [byte[]]::new(65536)
            while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($memory.Length + $count -gt $MaximumBytes) { throw 'CNB update response exceeds its size limit.' }
                $memory.Write($buffer, 0, $count)
            }
            return [pscustomobject]@{ Status = [int]$response.StatusCode; Bytes = $memory.ToArray(); Location = $response.Headers.Location }
        } finally { $memory.Dispose(); $stream.Dispose() }
    } finally { if ($null -ne $response) { $response.Dispose() }; $request.Dispose(); if ($owned) { $Client.Dispose() } }
}

function Get-CnbUpdateDownload {
    param([Uri]$Uri, [long]$MaximumBytes, [Net.Http.HttpClient]$Client)
    for ($redirects = 0; $redirects -le 3; $redirects++) {
        # Public download requests never carry repository credentials to storage.
        $reply = Invoke-CnbUpdateHttp -Method GET -Uri $Uri -MaximumBytes $MaximumBytes -Client $Client
        if ($reply.Status -eq 200) { return ,$reply.Bytes }
        if ($reply.Status -notin @(301, 302, 303, 307, 308) -or $null -eq $reply.Location -or -not $reply.Location.IsAbsoluteUri) { throw "CNB update download returned HTTP $($reply.Status)." }
        $Uri = $reply.Location
    }
    throw 'CNB update download exceeded its redirect limit.'
}

function Assert-CnbUpdateInstaller {
    param($Artifact, [Net.Http.HttpClient]$Client)
    if ($Artifact.mirrorUrl -notlike 'https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/*') { throw 'CNB installer URL is not the official mirror.' }
    $bytes = Get-CnbUpdateDownload -Uri $Artifact.mirrorUrl -MaximumBytes $Artifact.bytes -Client $Client
    if ($bytes.Length -ne $Artifact.bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() -cne $Artifact.sha256) { throw 'The CNB installer does not match the signed build.' }
}

function Publish-CnbUpdateFeed {
    param([string]$ManifestPath, $Payload, [string]$TrustPath, [Net.Http.HttpClient]$Client)
    $base = 'https://api.cnb.cool/Nesoriel/SteamWrapper/-/'
    $publicBase = 'https://cnb.cool/Nesoriel/SteamWrapper/-/'
    $tag = 'update-' + $Payload.channel
    if ($tag -cnotin @('update-preview', 'update-stable')) { throw 'Only the dedicated update feeds can be overwritten.' }
    $name = 'SteamWrapper-update.json'
    function Invoke-FeedApi([string]$Method, [string]$Path, $Body = $null, [switch]$Missing) {
        $reply = Invoke-CnbUpdateHttp -Method $Method -Uri ($base + $Path) -Json $Body -Authenticated -Client $Client
        if ($Missing -and $reply.Status -eq 404) { return $null }
        if ($reply.Status -lt 200 -or $reply.Status -ge 300) { throw "CNB update API returned HTTP $($reply.Status)." }
        if ($reply.Bytes.Length -eq 0) { return $null }
        return [Text.Encoding]::UTF8.GetString($reply.Bytes) | ConvertFrom-Json
    }
    $remoteTag = Invoke-FeedApi GET "git/tags/$tag" -Missing
    if ($null -eq $remoteTag) { $null = Invoke-FeedApi POST 'git/tags' @{ name = $tag; target = $Payload.release.commit } }
    $state = Invoke-FeedApi GET "releases/tags/$tag" -Missing
    if ($null -eq $state) {
        $state = Invoke-FeedApi POST 'releases' @{ tag_name = $tag; target_commitish = $Payload.release.commit; name = "SteamWrapper $($Payload.channel) update feed"; body = 'Project-signed update metadata; application installers remain in versioned releases.'; draft = $true; prerelease = $true; make_latest = 'false' }
    }
    if ($state.tag_name -cne $tag -or $state.id -notmatch '^[A-Za-z0-9_-]+$' -or -not $state.prerelease -or @($state.assets).Count -gt 1 -or
        (@($state.assets).Count -eq 1 -and $state.assets[0].name -cne $name)) { throw 'Unexpected CNB update release identity or assets; overwrite refused.' }
    if (@($state.assets).Count -eq 1) {
        $oldBytes = Get-CnbUpdateDownload -Uri ($publicBase + "releases/download/$tag/$name") -MaximumBytes 512KB -Client $Client
        $oldPath = Join-Path ([IO.Path]::GetDirectoryName($ManifestPath)) 'cnb-previous.json'
        [IO.File]::WriteAllBytes($oldPath, $oldBytes)
        $old = Read-ProjectUpdateEnvelope -Path $oldPath -TrustPath $TrustPath -AllowExpired
        if ($old.channel -cne $Payload.channel -or [Version]$old.release.version -gt [Version]$Payload.release.version -or $old.sequence -ge $Payload.sequence -or
            ($old.release.version -ceq $Payload.release.version -and ($old.release.tag -cne $Payload.release.tag -or $old.release.artifact.sha256 -cne $Payload.release.artifact.sha256))) { throw 'CNB update metadata is newer or belongs to another release; overwrite refused.' }
    }
    $id = $state.id
    $upload = Invoke-FeedApi POST "releases/$id/asset-upload-url" @{ asset_name = $name; size = (Get-Item -LiteralPath $ManifestPath).Length; overwrite = $true; ttl = 0 }
    $confirmation = $null
    $prefix = $base + "releases/$id/asset-upload-confirmation/"
    if (-not [Uri]::TryCreate($upload.verify_url, [UriKind]::Absolute, [ref]$confirmation) -or -not $confirmation.AbsoluteUri.StartsWith($prefix, [StringComparison]::Ordinal) -or $confirmation.Query -ne '' -or $confirmation.Fragment -ne '' -or
        $confirmation.AbsolutePath -match '(?i)%2e|%2f|%5c' -or $confirmation.AbsoluteUri.Substring($prefix.Length).Split('/').Count -ne 2) {
        # Diagnostic output contains only booleans/counts, never signed URL data.
        $prefixMatches = $null -ne $confirmation -and $confirmation.AbsoluteUri.StartsWith($prefix, [StringComparison]::Ordinal)
        $structure = [ordered]@{
            apiOrigin = $null -ne $confirmation -and $confirmation.Scheme -ceq 'https' -and $confirmation.Host -ceq 'api.cnb.cool' -and $confirmation.Port -eq 443 -and $confirmation.UserInfo -eq ''
            expectedPrefix = $prefixMatches
            suffixSegmentCount = if ($prefixMatches) { $confirmation.AbsolutePath.Substring(([Uri]$prefix).AbsolutePath.Length).Split('/').Count } else { 0 }
            queryEmpty = $null -ne $confirmation -and $confirmation.Query -eq ''
            queryTtlZeroOnly = $null -ne $confirmation -and $confirmation.Query -ceq '?ttl=0'
            unsafeEncoding = $null -ne $confirmation -and $confirmation.AbsolutePath -match '(?i)%2e|%2f|%5c'
        }
        throw ('Unsafe CNB update upload confirmation. Safe structure: ' + ($structure | ConvertTo-Json -Compress))
    }
    $reply = Invoke-CnbUpdateHttp -Method PUT -Uri $upload.upload_url -File $ManifestPath -Client $Client
    if ($reply.Status -lt 200 -or $reply.Status -ge 300) { throw 'CNB update metadata upload failed.' }
    $confirmPath = $confirmation.AbsoluteUri.Substring($base.Length) + '?ttl=0'
    $null = Invoke-FeedApi POST $confirmPath
    $download = Get-CnbUpdateDownload -Uri ($publicBase + "releases/download/$tag/$name") -MaximumBytes 512KB -Client $Client
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($download)) -cne (Get-FileHash -LiteralPath $ManifestPath).Hash) { throw 'CNB update metadata download differs from the signed bytes.' }
    $null = Invoke-FeedApi PATCH "releases/$id" @{ draft = $false; prerelease = $true; make_latest = 'false' }
}
