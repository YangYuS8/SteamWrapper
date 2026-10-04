[CmdletBinding()]
param(
    [string]$Repository = 'YangYuS8/SteamWrapper',
    [string]$KeyId = ('project-' + [DateTime]::UtcNow.ToString('yyyyMMdd')),
    [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
    [string]$GhExecutable = 'gh'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $KeyId -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Invalid repository or update key ID.' }
$trust = Get-Content -LiteralPath $TrustPath -Raw | ConvertFrom-Json
if (@($trust.keys).Count -ne 0) { throw 'A trust key is already configured. Key rotation requires an explicit migration; initialization will not replace it.' }
if ($trust.githubRepository -cne $Repository) { throw 'The public trust repository does not match the secret destination.' }
$names = & $GhExecutable secret list --repo $Repository --json name --jq '.[].name'
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository secret names; signing initialization stopped.' }
if ($names -contains 'STEAMWRAPPER_UPDATE_PRIVATE_KEY') { throw 'The signing secret already exists; initialization will not replace it.' }
$key = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
$privateBytes = $null
$process = $null
try {
    $public = [Convert]::ToBase64String($key.ExportSubjectPublicKeyInfo())
    $privateBytes = $key.ExportPkcs8PrivateKey()
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Command $GhExecutable -ErrorAction Stop).Source
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('secret', 'set', 'STEAMWRAPPER_UPDATE_PRIVATE_KEY', '--repo', $Repository)) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    # The private key goes only to gh stdin. Never write it to a file, arguments or logs.
    $process.StandardInput.WriteLine([Convert]::ToBase64String($privateBytes))
    $process.StandardInput.Close()
    $null = $process.StandardOutput.ReadToEndAsync()
    $null = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw 'GitHub did not accept the signing secret; no public trust key was changed.' }
    $trust.keys = @([ordered]@{ keyId = $KeyId; subjectPublicKeyInfo = $public })
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($TrustPath), ($trust | ConvertTo-Json -Depth 6) + "`n", [Text.UTF8Encoding]::new($false))
    Write-Output "Configured repository update signing and public key '$KeyId'. Commit the public trust file before releasing."
} finally {
    if ($null -ne $privateBytes) { [Array]::Clear($privateBytes, 0, $privateBytes.Length) }
    if ($null -ne $process) { $process.Dispose() }
    $key.Dispose()
}
