# Project-owned ECDSA signatures authorize exact installer bytes independently
# of Windows Authenticode. This is a separate contract from release.json.
. (Join-Path $PSScriptRoot '../windows/WinUIInstallableRelease.ps1')

function ConvertFrom-ProjectUpdateJson([string]$Text) {
    $result = ConvertFrom-WinUIInstallableJson $Text
    # PowerShell 7.4 lacks -DateKind. Read the two signed timestamp strings
    # from the JSON DOM rather than letting ConvertFrom-Json coerce DateTime.
    $document = [Text.Json.JsonDocument]::Parse($Text)
    try {
        $result.issuedAt = $document.RootElement.GetProperty('issuedAt').GetString()
        $result.expiresAt = $document.RootElement.GetProperty('expiresAt').GetString()
    } finally { $document.Dispose() }
    return $result
}

function Read-ProjectUpdateTrust([string]$Path) {
    $trust = ConvertFrom-WinUIInstallableJson ([IO.File]::ReadAllText($Path))
    Assert-WinUIInstallableFields $trust @('schemaVersion', 'keys', 'githubRepository', 'cnbRepository')
    if ($trust.schemaVersion -ne 1 -or @($trust.keys).Count -lt 1 -or @($trust.keys).Count -gt 16 -or
        $trust.githubRepository -cne 'YangYuS8/SteamWrapper' -or $trust.cnbRepository -cne 'Nesoriel/SteamWrapper') { throw 'Update trust must contain configured project keys and official repositories.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $trust.keys) {
        Assert-WinUIInstallableFields $item @('keyId', 'subjectPublicKeyInfo')
        if ($item.keyId -notmatch '^[A-Za-z0-9_-]{1,64}$' -or -not $seen.Add($item.keyId)) { throw 'Invalid or duplicate update key ID.' }
        $key = [Security.Cryptography.ECDsa]::Create()
        try {
            $bytes = [Convert]::FromBase64String($item.subjectPublicKeyInfo)
            $read = 0
            $key.ImportSubjectPublicKeyInfo($bytes, [ref]$read)
            if ($read -ne $bytes.Length -or $key.KeySize -ne 256 -or $key.ExportParameters($false).Curve.Oid.Value -ne '1.2.840.10045.3.1.7') { throw 'Update keys must use ECDSA P-256.' }
        } finally { $key.Dispose() }
    }
    return $trust
}

function New-ProjectUpdatePayload {
    param($ReleaseMetadata, $Trust, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow, [switch]$IncludeCnbMirror)
    $metadata = $ReleaseMetadata
    if ($metadata.schemaVersion -ne 2 -or $metadata.releaseChannel -notin @('preview', 'stable') -or
        $metadata.tag -notmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$' -or
        $metadata.commit -notmatch '^[a-f0-9]{40}$') { throw 'Project updates require a versioned installable release.' }
    $tag = $metadata.tag
    $name = "SteamWrapper-$tag-win-x64-setup.exe"
    if ($metadata.installerAsset.fileName -cne $name -or $metadata.installerAsset.bytes -lt 1 -or $metadata.installerAsset.bytes -gt 512MB -or $metadata.installerAsset.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid update installer descriptor.' }
    $mirror = if ($IncludeCnbMirror) { "https://cnb.cool/$($Trust.cnbRepository)/-/releases/download/$tag/$name" } else { $null }
    return [pscustomobject][ordered]@{
        schemaVersion = 2; appId = 'SteamWrapper'; platform = 'win-x64'; channel = $metadata.releaseChannel
        sequence = $Now.ToUnixTimeMilliseconds(); issuedAt = $Now.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        expiresAt = $Now.AddDays(28).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        release = [pscustomobject][ordered]@{
            tag = $tag; version = $metadata.version; commit = $metadata.commit; minimumWindowsVersion = $metadata.minimumWindowsVersion
            profileContract = 2; runnerContract = 2; deploymentProtocol = 1
            artifact = [pscustomobject][ordered]@{ type = 'installer'; url = "https://github.com/$($Trust.githubRepository)/releases/download/$tag/$name"; mirrorUrl = $mirror; sha256 = $metadata.installerAsset.sha256; bytes = $metadata.installerAsset.bytes; trust = 'project-signature' }
        }
    }
}

function Update-ProjectUpdateFreshness {
    param($Payload, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    $copy = ConvertFrom-ProjectUpdateJson ($Payload | ConvertTo-Json -Depth 12 -Compress)
    $copy.sequence = [Math]::Max($Now.ToUnixTimeMilliseconds(), [long]$Payload.sequence + 1)
    $copy.issuedAt = $Now.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $copy.expiresAt = $Now.AddDays(28).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    return $copy
}

function Assert-ProjectUpdateCurrentRelease {
    param($Payload, $ExistingPayload)
    if ($null -eq $ExistingPayload) { throw 'Mirror maintenance requires the exact currently authorized release.' }
    foreach ($field in @('tag', 'version', 'commit', 'minimumWindowsVersion', 'profileContract', 'runnerContract', 'deploymentProtocol')) {
        if ($Payload.release.$field -cne $ExistingPayload.release.$field) { throw 'Mirror maintenance requires the exact currently authorized release.' }
    }
    foreach ($field in @('type', 'url', 'sha256', 'bytes', 'trust')) {
        if ($Payload.release.artifact.$field -cne $ExistingPayload.release.artifact.$field) { throw 'Mirror maintenance requires the exact currently authorized release.' }
    }
    if ($Payload.channel -cne $ExistingPayload.channel) { throw 'Mirror maintenance requires the exact currently authorized release.' }
}

function Write-ProjectUpdateEnvelope {
    param($Payload, [Security.Cryptography.ECDsa]$Key, [string]$KeyId, [string]$Path)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Payload | ConvertTo-Json -Depth 12 -Compress))
    $signature = $Key.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)
    $envelope = [ordered]@{ schemaVersion = 1; keyId = $KeyId; payload = [Convert]::ToBase64String($bytes); signature = [Convert]::ToBase64String($signature) }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), ($envelope | ConvertTo-Json -Compress) + "`n", [Text.UTF8Encoding]::new($false))
}

function Read-ProjectUpdateEnvelope {
    param([string]$Path, [string]$TrustPath, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow, [switch]$AllowExpired)
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -lt 1 -or $file.Length -gt 512KB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid update envelope file.' }
    $trust = Read-ProjectUpdateTrust $TrustPath
    $wrapper = ConvertFrom-WinUIInstallableJson ([IO.File]::ReadAllText($file.FullName))
    Assert-WinUIInstallableFields $wrapper @('schemaVersion', 'keyId', 'payload', 'signature')
    if ($wrapper.schemaVersion -ne 1) { throw 'Unsupported update envelope schema.' }
    $configured = @($trust.keys | Where-Object keyId -CEQ $wrapper.keyId)
    if ($configured.Count -ne 1) { throw 'Unknown update signature key.' }
    $key = [Security.Cryptography.ECDsa]::Create()
    try {
        $read = 0
        $key.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($configured[0].subjectPublicKeyInfo), [ref]$read)
        $bytes = [Convert]::FromBase64String($wrapper.payload)
        $signature = [Convert]::FromBase64String($wrapper.signature)
        if ($signature.Length -ne 64 -or -not $key.VerifyData($bytes, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)) { throw 'Update signature verification failed.' }
    } finally { $key.Dispose() }
    $payload = ConvertFrom-ProjectUpdateJson ([Text.UTF8Encoding]::new($false, $true).GetString($bytes))
    Assert-WinUIInstallableFields $payload @('schemaVersion', 'appId', 'platform', 'channel', 'sequence', 'issuedAt', 'expiresAt', 'release')
    if ($payload.schemaVersion -ne 2 -or $payload.appId -cne 'SteamWrapper' -or $payload.platform -cne 'win-x64' -or $payload.channel -cnotin @('preview', 'stable') -or $payload.sequence -lt 1) { throw 'Unsupported signed update payload.' }
    $issued = [DateTimeOffset]::ParseExact($payload.issuedAt, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    $expires = [DateTimeOffset]::ParseExact($payload.expiresAt, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    if ($issued -gt $Now -or $expires -le $issued -or $expires - $issued -gt [TimeSpan]::FromDays(31) -or (-not $AllowExpired -and $expires -le $Now)) { throw 'Update metadata is expired, future-dated or has an invalid lifetime.' }
    $release = $payload.release
    Assert-WinUIInstallableFields $release @('tag', 'version', 'commit', 'minimumWindowsVersion', 'profileContract', 'runnerContract', 'deploymentProtocol', 'artifact')
    $artifact = $release.artifact
    Assert-WinUIInstallableFields $artifact @('type', 'url', 'mirrorUrl', 'sha256', 'bytes', 'trust')
    if ($release.tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -or $release.commit -notmatch '^[a-f0-9]{40}$' -or
        $release.tag -notmatch ('^v' + [Regex]::Escape($release.version) + '(?:-|$)') -or
        $release.profileContract -ne 2 -or $release.runnerContract -ne 2 -or $release.deploymentProtocol -ne 1 -or
        $artifact.type -cne 'installer' -or $artifact.trust -cne 'project-signature' -or $artifact.bytes -lt 1 -or $artifact.bytes -gt 512MB -or $artifact.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid signed update release descriptor.' }
    $name = "SteamWrapper-$($release.tag)-win-x64-setup.exe"
    if ($artifact.url -cne "https://github.com/$($trust.githubRepository)/releases/download/$($release.tag)/$name" -or
        ($null -ne $artifact.mirrorUrl -and $artifact.mirrorUrl -cne "https://cnb.cool/$($trust.cnbRepository)/-/releases/download/$($release.tag)/$name")) { throw 'Update URLs must identify the exact official versioned installer.' }
    return $payload
}
