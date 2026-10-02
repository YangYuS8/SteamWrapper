[CmdletBinding()]
param([Parameter(Mandatory)][string]$SetupPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Installer PE resource inspection requires Windows.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not ('SteamWrapper.BuildTools.InstallerResources' -as [type])) { Add-Type -Path (Join-Path $repoRoot 'packaging/windows/InstallerResources.cs') }
$setup = (Resolve-Path -LiteralPath $SetupPath).Path
if ((Get-Item -LiteralPath $setup).Length -gt 512L * 1024 * 1024) { throw 'Installer exceeds its 512 MiB package limit.' }
$bytes = [IO.File]::ReadAllBytes($setup)
if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw 'Installer is not a Windows PE.' }
$pe = [BitConverter]::ToInt32($bytes, 60)
if ($pe -lt 64 -or $pe + 6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) { throw 'Installer must be a native x64 PE.' }
$embedded = [SteamWrapper.BuildTools.InstallerResources]::IconHashes($setup)
$ico = [IO.File]::ReadAllBytes((Join-Path $repoRoot 'assets/brand/steamwrapper.ico'))
$count = [BitConverter]::ToUInt16($ico, 4)
for ($index = 0; $index -lt $count; $index++) {
    $entry = 6 + 16 * $index
    $length = [BitConverter]::ToInt32($ico, $entry + 8)
    $offset = [BitConverter]::ToInt32($ico, $entry + 12)
    if ($length -le 0 -or $offset -lt 6 + 16 * $count -or $offset + $length -gt $ico.Length) { throw 'Canonical icon is malformed.' }
    $frame = [byte[]]::new($length)
    [Array]::Copy($ico, $offset, $frame, 0, $length)
    $hash = [Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($frame))
    if ($hash -notin $embedded) { throw 'Installer is missing a canonical icon frame or contains altered branding.' }
}
$version = (Get-Item -LiteralPath $setup).VersionInfo
if ($version.ProductName.Trim() -ne 'SteamWrapper') { throw 'Installer Windows product metadata is missing.' }
Write-Host "Inspected actual x64 installer resources: $count canonical icon frames, product SteamWrapper."
return [pscustomobject]@{ machine = 'x64'; canonicalIconFrames = $count; productName = $version.ProductName.Trim(); productVersion = $version.ProductVersion.Trim(); bytes = $bytes.Length; sha256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() }
