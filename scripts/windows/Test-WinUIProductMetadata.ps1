[CmdletBinding()]
param(
    [string]$PublishDirectory = (Join-Path $PSScriptRoot '../../target/winui/publish'),
    [string]$ExpectedVersion
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Actual PE product metadata inspection requires Windows.' }
if (-not $ExpectedVersion) {
    $project = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj') -Raw)
    $ExpectedVersion = @($project.Project.PropertyGroup.Version | Where-Object { $_ })[0]
}
if ($ExpectedVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Expected product version must be a three-part numeric version.' }
$root = (Resolve-Path -LiteralPath $PublishDirectory).Path
$files = @('SteamWrapper.Manager.exe', 'SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll',
    'SteamWrapper.Deployment.dll', 'zh-CN/SteamWrapper.Application.resources.dll', 'Deployment/SteamWrapper.exe', 'Runner/SteamWrapperRunner.exe')
foreach ($relative in $files) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing own PE product: $relative." }
    $metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    if ($metadata.ProductName -cne 'SteamWrapper' -or $metadata.ProductVersion -cne $ExpectedVersion) {
        throw "Own PE product/version mismatch: $relative."
    }
}
$hostBytes = [IO.File]::ReadAllBytes((Join-Path $root 'Deployment/SteamWrapper.exe'))
if ($hostBytes.Length -lt 512) { throw 'The deployment Host is not a complete PE.' }
$peOffset = [BitConverter]::ToInt32($hostBytes, 60)
if ($peOffset -lt 64 -or $peOffset + 96 -gt $hostBytes.Length -or
    [BitConverter]::ToUInt32($hostBytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($hostBytes, $peOffset + 4) -ne 0x8664 -or
    [BitConverter]::ToUInt16($hostBytes, $peOffset + 24 + 68) -ne 2) {
    throw 'The actual deployment Host must be x64 with the Windows GUI subsystem.'
}
Write-Output "PASS: all $($files.Count) own published PE products are SteamWrapper $ExpectedVersion; NativeAOT Host is x64/GUI. No executable was run."
