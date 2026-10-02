[CmdletBinding()]
param([string]$RunnerPath = (Join-Path $PSScriptRoot '../../target/release/steamwrapper-runner.exe'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Windows PE metadata must be tested on Windows.' }
$runner = (Resolve-Path -LiteralPath $RunnerPath).Path
$cargo = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../crates/runner/Cargo.toml'))
$versions = [regex]::Matches($cargo, '(?m)^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$')
if ($versions.Count -ne 1) { throw 'Expected one coordinated Runner version.' }
$expected = $versions[0].Groups[1].Value
$metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($runner)
if ($metadata.ProductName -cne 'SteamWrapper') { throw 'Runner must have ProductName=SteamWrapper before release signing.' }
if ($metadata.ProductVersion -cne $expected -or $metadata.FileVersion -cne $expected) { throw 'Runner PE product/file versions must match its coordinated Cargo version.' }
if ($metadata.OriginalFilename -cne 'SteamWrapperRunner.exe' -or $metadata.InternalName -cne 'SteamWrapperRunner') { throw 'Runner PE identity metadata does not match its distributed filename.' }
Write-Output "PASS: real Runner PE metadata is SteamWrapper $expected; the executable was inspected without running it."
