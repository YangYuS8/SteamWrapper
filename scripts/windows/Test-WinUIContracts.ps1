[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'The Runner-consumption contract requires Windows.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Run mise run windows:setup first.' }
$components = (Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$installation = & $vswhere -latest -products '*' -requires $components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Required MSVC/Windows SDK components are missing.' }
& (Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program $($Arguments -join ' ') failed ($LASTEXITCODE)." }
}

$testRoot = Join-Path $repoRoot ('target/winui-contracts/' + [Guid]::NewGuid().ToString('N'))
$fixturePublish = Join-Path $testRoot 'fixture-publish'
$contractOutput = Join-Path $testRoot 'results'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
Invoke-Checked cargo @('test', '--locked', '-p', 'steamwrapper-core', '--test', 'winui_contract')
Invoke-Checked cargo @('build', '--locked', '--release', '-p', 'steamwrapper-runner')
Invoke-Checked dotnet @('restore', 'tests/fixtures/SteamWrapper.ProcessFixture/SteamWrapper.ProcessFixture.csproj', '--locked-mode')
Invoke-Checked dotnet @('restore', 'tests/contracts/SteamWrapper.ContractDriver/SteamWrapper.ContractDriver.csproj', '--locked-mode')
Invoke-Checked dotnet @('publish', 'tests/fixtures/SteamWrapper.ProcessFixture/SteamWrapper.ProcessFixture.csproj', '--no-restore', '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $fixturePublish)
Invoke-Checked dotnet @('run', '--project', 'tests/contracts/SteamWrapper.ContractDriver/SteamWrapper.ContractDriver.csproj', '--no-restore', '-c', 'Release', '--', (Join-Path $repoRoot 'tests/contracts/legacy-v2.toml'), $contractOutput, (Join-Path $repoRoot 'target/release/steamwrapper-runner.exe'), $fixturePublish)
$previousContractRoot = $env:STEAMWRAPPER_CONTRACT_ROOT
try {
    $env:STEAMWRAPPER_CONTRACT_ROOT = $contractOutput
    Invoke-Checked cargo @('test', '--locked', '-p', 'steamwrapper-core', '--test', 'winui_contract', '--', '--ignored')
} finally {
    $env:STEAMWRAPPER_CONTRACT_ROOT = $previousContractRoot
}
Write-Output "WinUI C# / Rust contracts passed. Isolated evidence: $contractOutput"
