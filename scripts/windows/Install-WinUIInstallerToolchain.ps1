[CmdletBinding()]
param([switch]$DownloadOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'The installer compiler requires Windows.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pin = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging/windows/inno-toolchain.json') -Raw | ConvertFrom-Json
$toolRoot = Join-Path $repoRoot "target/toolchain/inno-$($pin.version)-x64"
$downloadRoot = Join-Path $repoRoot 'target/toolchain/downloads'
foreach ($path in @($toolRoot, $downloadRoot)) {
    $ancestor = $path
    while ($ancestor -and $ancestor -ne $repoRoot) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Toolchain paths must not contain reparse points.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}
[IO.Directory]::CreateDirectory($downloadRoot) | Out-Null
$installer = Join-Path $downloadRoot $pin.fileName
if (-not (Test-Path -LiteralPath $installer)) { Invoke-WebRequest -Uri $pin.url -OutFile $installer }
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pin.sha256) { throw 'The Inno toolchain download does not match the pinned official SHA-256.' }
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne $pin.publisher) { throw 'The Inno toolchain download does not have the expected valid official publisher signature.' }
Write-Host "Verified Inno Setup $($pin.version) x64 official SHA-256 and publisher $($pin.publisher)."
if ($DownloadOnly) { return $installer }
$compiler = Join-Path $toolRoot 'ISCC.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $process = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER', '/NOICONS', ('/DIR="' + $toolRoot + '"')) -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Inno toolchain installation failed with exit code $($process.ExitCode)." }
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The installed Inno compiler is missing.' }
$compilerSignature = Get-AuthenticodeSignature -LiteralPath $compiler
if ($compilerSignature.Status -ne 'Valid' -or $compilerSignature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne $pin.publisher) { throw 'The installed Inno compiler does not have the expected official publisher signature.' }
$compilerVersion = (& $compiler --version).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerVersion -ne $pin.version) { throw 'The installed compiler engine does not match the pinned Inno version.' }
return $compiler
