[CmdletBinding()]
param([string]$RunnerPath = (Join-Path $PSScriptRoot '../../target/release/steamwrapper-runner.exe'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Actual Runner PE imports must be inspected on Windows.' }
$runner = (Resolve-Path -LiteralPath $RunnerPath).Path
$bytes = [IO.File]::ReadAllBytes($runner)
if ($bytes.Length -lt 512) { throw 'The Runner is not a complete PE executable.' }
$peOffset = [BitConverter]::ToInt32($bytes, 60)
if ($peOffset -lt 64 -or $peOffset + 96 -gt $bytes.Length -or
    [BitConverter]::ToUInt16($bytes, 0) -ne 0x5a4d -or
    [BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 24) -ne 0x20b -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68) -ne 2) {
    throw 'The actual distributed Runner must be x64 with the Windows GUI subsystem.'
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { throw 'Official MSVC Build Tools are required to inspect Runner imports.' }
$candidates = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe')
if ($LASTEXITCODE -ne 0 -or $candidates.Count -eq 0) { throw 'The official MSVC dumpbin.exe import inspector is missing.' }
$dumpbin = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Sort-Object { [Version]([Diagnostics.FileVersionInfo]::GetVersionInfo($_).FileVersion) } -Descending |
    Select-Object -First 1)
if ($dumpbin.Count -ne 1) { throw 'The official MSVC dumpbin.exe import inspector is missing.' }

# /IMPORTS reports both ordinary and delay-loaded imports. Inspect the actual
# executable, since a successful build or a configured flag does not prove its
# runtime dependencies. Windows 11 inbox DLLs, including UCRT API sets, are valid.
$inspection = (& $dumpbin[0] /imports $runner 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "MSVC failed to inspect Runner imports ($LASTEXITCODE)." }
$imports = @([regex]::Matches($inspection, '(?im)^\s+([a-z0-9_.-]+\.dll)\s*$') |
    ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique)
if ($imports.Count -eq 0) { throw 'MSVC returned no DLL imports for the actual Runner executable.' }
$redistributable = @($imports | Where-Object { $_ -match '^(?:(?:vcruntime|msvcp|msvcr|concrt|vcomp|vcamp)[0-9][a-z0-9_]*|ucrtbased)\.dll$' })
if ($redistributable.Count -ne 0) {
    throw "The independent Runner must not require a separately installed Visual C++ redistributable: $($redistributable -join ', '). Enable static CRT linkage for the Windows MSVC build."
}
$sha256 = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "PASS: actual x64/GUI Runner has no ordinary or delay-loaded Visual C++ redistributable imports. SHA256=$sha256; inspected imports: $($imports -join ', ')."
