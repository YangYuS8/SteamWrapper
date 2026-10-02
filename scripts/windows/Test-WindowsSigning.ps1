[CmdletBinding()]
param(
    [string]$RunnerPath = (Join-Path $PSScriptRoot '../../target/release/steamwrapper-runner.exe'),
    [string]$SetupPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Windows signing regressions require Windows.' }
. (Join-Path $PSScriptRoot 'WindowsSigning.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path $repoRoot ('target/winui/signing-tests/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$approved = '3' * 64

function New-SigningFixtureEvidence {
    return [pscustomobject]@{
        TrustStatus = [uint32]0; TimestampTrusted = $true; TimestampRfc3161 = $true
        DigestAlgorithmOid = '2.16.840.1.101.3.4.2.1'; CertificateSha256 = $approved
        SignerName = 'SignPath Foundation'; ProductName = 'SteamWrapper'; ProductVersion = '0.2.1'
        Sha256 = 'a' * 64; Bytes = 42; CacheOnly = $true
    }
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $failed = $false
    try { $null = & $Action }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw }; $failed = $true }
    if (-not $failed) { throw "Expected signing rejection: $Pattern" }
}
function Test-Evidence($Evidence) {
    Assert-WindowsSigningEvidence -Evidence $Evidence -AllowedCertificateSha256 @($approved) -ExpectedProductVersion '0.2.1'
}

$null = Test-Evidence (New-SigningFixtureEvidence)
$missingTimestamp = New-SigningFixtureEvidence
$missingTimestamp.TimestampTrusted = $false
Assert-Rejected { Test-Evidence $missingTimestamp } 'Signing requires a trusted RFC3161 timestamp*'
$legacyTimestamp = New-SigningFixtureEvidence
$legacyTimestamp.TimestampRfc3161 = $false
Assert-Rejected { Test-Evidence $legacyTimestamp } 'Signing requires a trusted RFC3161 timestamp*'
Write-Output 'PASS: a valid Windows trust result without a trusted RFC3161 timestamp is rejected.'

foreach ($case in @(
    @{ Property = 'TrustStatus'; Value = [uint32]2148098064; Pattern = 'Windows Authenticode trust verification failed*' },
    @{ Property = 'CertificateSha256'; Value = '4' * 64; Pattern = 'Signing certificate does not match*' },
    @{ Property = 'SignerName'; Value = 'Another publisher'; Pattern = 'Signing certificate does not match*' },
    @{ Property = 'ProductName'; Value = 'An unrelated Foundation project'; Pattern = 'Signing PE product name/version*' },
    @{ Property = 'ProductVersion'; Value = '0.2.0'; Pattern = 'Signing PE product name/version*' },
    @{ Property = 'DigestAlgorithmOid'; Value = '1.3.14.3.2.26'; Pattern = 'Signing requires the SHA-256*' },
    @{ Property = 'Sha256'; Value = 'invalid'; Pattern = 'Signing input has invalid*' },
    @{ Property = 'Bytes'; Value = 0; Pattern = 'Signing input has invalid*' }
)) {
    $evidence = New-SigningFixtureEvidence
    $evidence.($case.Property) = $case.Value
    Assert-Rejected { Test-Evidence $evidence } $case.Pattern
}
Assert-Rejected { Assert-WindowsSigningEvidence -Evidence (New-SigningFixtureEvidence) -AllowedCertificateSha256 @('not-a-certificate-hash') -ExpectedProductVersion '0.2.1' } 'Signing identity requires*'
Assert-Rejected { Assert-WindowsSigningEvidence -Evidence (New-SigningFixtureEvidence) -AllowedCertificateSha256 @($approved) -ExpectedProductVersion '0.2.1-preview.1' } 'Signing requires a three-part*'
Write-Output 'PASS: wrong trust/identity/product/version/digest and unapproved certificate pins are rejected.'

# Only Windows PE tail padding is normalized at the native resource boundary.
# Policy evidence and the expected version remain exact, including case and whitespace.
$rawPadding = New-SigningFixtureEvidence
$rawPadding.ProductName = "SteamWrapper `0 `0"
$rawPadding.ProductVersion = "0.2.1 `0 `0"
Assert-Rejected { Test-Evidence $rawPadding } 'Signing PE product name/version*'
Assert-Rejected { Assert-WindowsSigningEvidence -Evidence (New-SigningFixtureEvidence) -AllowedCertificateSha256 @($approved) -ExpectedProductVersion "0.2.1 " } 'Signing requires a three-part*'
Assert-Rejected { Assert-WindowsSigningEvidence -Evidence (New-SigningFixtureEvidence) -AllowedCertificateSha256 @($approved) -ExpectedProductVersion "0.2.1`n" } 'Signing requires a three-part*'
Initialize-WindowsSigningTrust
$normalized = New-SigningFixtureEvidence
$normalized.ProductName = [SteamWrapper.Signing.NativeTrust]::NormalizeProductResource($rawPadding.ProductName)
$normalized.ProductVersion = [SteamWrapper.Signing.NativeTrust]::NormalizeProductResource($rawPadding.ProductVersion)
$null = Test-Evidence $normalized
foreach ($name in @(' SteamWrapper ', 'Steam Wrapper ', 'steamwrapper ', "SteamWrapper`t", "SteamWrapper`u{00a0}", "SteamWrapper`0other")) {
    $different = New-SigningFixtureEvidence
    $different.ProductName = [SteamWrapper.Signing.NativeTrust]::NormalizeProductResource($name)
    Assert-Rejected { Test-Evidence $different } 'Signing PE product name/version*'
}
foreach ($version in @(' 0.2.1 ', '0.2. 1 ', '0.2.0 ', "0.2.1`t", "0.2.1`0other")) {
    $different = New-SigningFixtureEvidence
    $different.ProductVersion = [SteamWrapper.Signing.NativeTrust]::NormalizeProductResource($version)
    Assert-Rejected { Test-Evidence $different } 'Signing PE product name/version*'
}
Write-Output 'PASS: PE resource normalization removes only tail spaces/NUL; different names/versions and padded expected versions remain rejected.'

# Only the provider boundary is mocked. The final Runner bytes, hash change
# check, atomic sidecar write, adjacent paths and write failure are real.
$realProvider = ${function:Get-WindowsSigningEvidence}
$runner = Join-Path $fixture 'SteamWrapperRunner.exe'
$manifest = Join-Path $fixture 'runner-manifest.json'
[IO.File]::WriteAllBytes($runner, [byte[]](1..42))
[IO.File]::WriteAllText($manifest, '{"old":"sidecar preserved unless verification succeeds"}')
$originalManifest = [IO.File]::ReadAllText($manifest)
$script:mockEvidence = New-SigningFixtureEvidence
function Get-WindowsSigningEvidence { param($Path, $AllowedRoot, [switch]$OnlineRevocation); return $script:mockEvidence }
try {
    $script:mockEvidence.TimestampTrusted = $false
    Assert-Rejected { Update-RunnerSigningManifest -RunnerPath $runner -ManifestPath $manifest -AllowedRoot $fixture -Version '0.2.1' -AllowedCertificateSha256 @($approved) } 'Signing requires a trusted RFC3161 timestamp*'
    if ([IO.File]::ReadAllText($manifest) -cne $originalManifest) { throw 'Untrusted Runner overwrote the manifest.' }
    $script:mockEvidence = New-SigningFixtureEvidence
    Assert-Rejected { Update-RunnerSigningManifest -RunnerPath $runner -ManifestPath $manifest -AllowedRoot $fixture -Version '0.2.1' -AllowedCertificateSha256 @($approved) } 'Runner bytes changed after signature verification*'
    if ([IO.File]::ReadAllText($manifest) -cne $originalManifest) { throw 'Changed Runner bytes overwrote the manifest.' }
    $script:mockEvidence.Sha256 = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash.ToLowerInvariant()
    $result = Update-RunnerSigningManifest -RunnerPath $runner -ManifestPath $manifest -AllowedRoot $fixture -Version '0.2.1' -AllowedCertificateSha256 @($approved)
    $written = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
    if ($written.schemaVersion -ne 1 -or $written.contractVersion -ne 2 -or $written.version -cne '0.2.1' -or $written.sha256 -cne $result.sha256) { throw 'Post-sign Runner manifest lost the TOML/CLI contract metadata.' }
    $committed = [IO.File]::ReadAllText($manifest)
    $locked = [IO.FileStream]::new($manifest, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { Assert-Rejected { Update-RunnerSigningManifest -RunnerPath $runner -ManifestPath $manifest -AllowedRoot $fixture -Version '0.2.1' -AllowedCertificateSha256 @($approved) } '*being used by another process*' }
    finally { $locked.Dispose() }
    if ([IO.File]::ReadAllText($manifest) -cne $committed -or @(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp' -Force).Count -ne 0) { throw 'Failed atomic commit lost the prior sidecar or retained temporary files.' }
    Assert-Rejected { Update-RunnerSigningManifest -RunnerPath $runner -ManifestPath (Join-Path $repoRoot 'runner-manifest.json') -AllowedRoot $fixture -Version '0.2.1' -AllowedCertificateSha256 @($approved) } 'Signing inputs must be local child files*'
    Write-Output 'PASS: final signed-byte hash rebuilds the sidecar; rejected/changed/locked input preserves the previous manifest.'
} finally { Set-Item -LiteralPath Function:Get-WindowsSigningEvidence -Value $realProvider }

$unsigned = Join-Path $fixture 'unsigned.exe'
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $RunnerPath).Path -Destination $unsigned
$actual = Get-WindowsSigningEvidence -Path $unsigned -AllowedRoot $fixture
if (-not $actual.CacheOnly -or $actual.TrustStatus -eq 0) { throw 'Real unsigned Runner unexpectedly passed cached Windows trust.' }
Assert-Rejected { Assert-WindowsSigning -Path $unsigned -AllowedRoot $fixture -AllowedCertificateSha256 @($approved) -ExpectedProductVersion '0.2.1' } 'Windows Authenticode trust verification failed*'
Write-Output 'PASS: actual unsigned Runner PE is rejected by offline Windows trust without executing it.'

if ($SetupPath) {
    $setup = Join-Path $fixture 'unsigned-inno-setup.exe'
    Copy-Item -LiteralPath (Resolve-Path -LiteralPath $SetupPath).Path -Destination $setup
    $setupEvidence = Get-WindowsSigningEvidence -Path $setup -AllowedRoot $fixture
    $runnerCargo = Get-Content -LiteralPath (Join-Path $repoRoot 'crates/runner/Cargo.toml') -Raw
    $coordinatedVersion = [regex]::Match($runnerCargo, '(?m)^version\s*=\s*"(?<version>[0-9]+\.[0-9]+\.[0-9]+)"').Groups['version'].Value
    if (-not $coordinatedVersion -or $setupEvidence.ProductName -cne 'SteamWrapper' -or $setupEvidence.ProductVersion -cne $coordinatedVersion) { throw 'Actual Inno resource extraction differs from the strict coordinated signing policy.' }
    Assert-Rejected { Assert-WindowsSigning -Path $setup -AllowedRoot $fixture -AllowedCertificateSha256 @($approved) -ExpectedProductVersion $coordinatedVersion } 'Windows Authenticode trust verification failed*'
    Write-Output 'PASS: actual Inno Setup PE metadata normalizes through the production extractor; unsigned Setup remains rejected without executing it.'
}

$tampered = Join-Path $fixture 'tampered.exe'
Copy-Item -LiteralPath (Join-Path $PSHOME 'pwsh.exe') -Destination $tampered
$signer = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($tampered)
if ([string]::IsNullOrWhiteSpace($signer.Subject)) { throw 'The real tamper regression needs an embedded signed PowerShell executable.' }
$certificateHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($signer.GetRawCertData())).ToLowerInvariant()
$signer.Dispose()
$signedEvidence = Get-WindowsSigningEvidence -Path $tampered -AllowedRoot $fixture
if ($signedEvidence.TrustStatus -eq 0) {
    if (-not $signedEvidence.TimestampTrusted -or -not $signedEvidence.TimestampRfc3161 -or
        $signedEvidence.CertificateSha256 -cne $certificateHash -or $signedEvidence.SignerName -cne 'Microsoft Corporation' -or
        $signedEvidence.DigestAlgorithmOid -cne '2.16.840.1.101.3.4.2.1') { throw 'Trusted real PE evidence lost its signer, SHA-256 or RFC3161 countersignature.' }
    Assert-Rejected { Assert-WindowsSigning -Path $tampered -AllowedRoot $fixture -AllowedCertificateSha256 @($certificateHash) -ExpectedProductVersion '0.2.1' } 'Signing certificate does not match*'
    Write-Output 'PASS: real trusted RFC3161-signed PE evidence is decoded correctly; a trusted unrelated publisher is rejected.'
} else {
    Write-Output ('NOT RUN: positive Microsoft sample validation requires cached Windows chain/revocation evidence; status 0x{0:x8}. Negative tamper validation still runs.' -f $signedEvidence.TrustStatus)
}
$bytes = [IO.File]::ReadAllBytes($tampered)
$bytes[0x40] = $bytes[0x40] -bxor 1
[IO.File]::WriteAllBytes($tampered, $bytes)
$actual = Get-WindowsSigningEvidence -Path $tampered -AllowedRoot $fixture
if ($actual.TrustStatus -ne [uint32]2148098064 -or -not $actual.CacheOnly) { throw ('Real signed PE tampering must fail with TRUST_E_BAD_DIGEST; got 0x{0:x8}.' -f $actual.TrustStatus) }
Assert-Rejected { Assert-WindowsSigning -Path $tampered -AllowedRoot $fixture -AllowedCertificateSha256 @($approved) -ExpectedProductVersion '0.2.1' } 'Windows Authenticode trust verification failed*'
Write-Output 'PASS: actual embedded-signed PE with changed content is rejected as TRUST_E_BAD_DIGEST; system/user originals are untouched.'
