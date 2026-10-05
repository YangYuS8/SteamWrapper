# Official CNB OpenAPI: upload_token and asset_path are two opaque path
# parameters; ttl=0 retains assets permanently. Real API responses include
# once-encoded storage paths and may already include the permanent TTL query.
function Get-CnbUploadConfirmationUri {
    param([AllowEmptyString()][string]$VerifyUrl, [string]$ExpectedPrefix)
    $failure = 'Unsafe CNB upload confirmation URL; upload refused.'
    $uri = $null
    $prefix = $null
    if ([string]::IsNullOrEmpty($VerifyUrl) -or [Text.Encoding]::UTF8.GetByteCount($VerifyUrl) -gt 8KB -or
        $VerifyUrl -match '[\\\x00-\x20\x7f]|%(?![a-fA-F0-9]{2})' -or
        -not [Uri]::TryCreate($ExpectedPrefix, [UriKind]::Absolute, [ref]$prefix) -or
        $prefix.Scheme -cne 'https' -or $prefix.Host -cne 'api.cnb.cool' -or $prefix.Port -ne 443 -or
        $prefix.UserInfo -ne '' -or $prefix.Query -ne '' -or $prefix.Fragment -ne '' -or
        -not $prefix.AbsolutePath.EndsWith('/asset-upload-confirmation/', [StringComparison]::Ordinal) -or
        -not [Uri]::TryCreate($VerifyUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or $uri.Host -cne 'api.cnb.cool' -or $uri.Port -ne 443 -or
        $uri.UserInfo -ne '' -or $uri.Fragment -ne '' -or $uri.Query -cnotin @('', '?ttl=0') -or
        -not $uri.AbsolutePath.StartsWith($prefix.AbsolutePath, [StringComparison]::Ordinal) -or
        -not $uri.OriginalString.StartsWith($ExpectedPrefix, [StringComparison]::Ordinal)) { throw $failure }
    # Inspect the original path before System.Uri normalizes ./ or ../ routes.
    $suffix = $VerifyUrl.Substring($ExpectedPrefix.Length)
    if ($uri.Query -ceq '?ttl=0') { $suffix = $suffix.Substring(0, $suffix.Length - '?ttl=0'.Length) }
    $parameters = $suffix.Split('/')
    if ($parameters.Count -ne 2) { throw $failure }
    foreach ($parameter in $parameters) {
        # Validate one decoding only; preserve original escaped parameters in the
        # outgoing URI. Base64 tokens can contain encoded +, / and = characters.
        if ($parameter.Length -lt 1 -or $parameter.Length -gt 6KB) { throw $failure }
        try { $decoded = [Uri]::UnescapeDataString($parameter) }
        catch { throw $failure }
        if ($decoded.Length -gt 4KB -or $decoded -cnotmatch '^[A-Za-z0-9._~+/=-]+$' -or
            @($decoded.Split('/') | Where-Object { $_ -cin @('.', '..') }).Count -gt 0) { throw $failure }
    }
    # Never append a second query to the API's existing ?ttl=0 response.
    return [Uri]($uri.GetLeftPart([UriPartial]::Path) + '?ttl=0')
}
