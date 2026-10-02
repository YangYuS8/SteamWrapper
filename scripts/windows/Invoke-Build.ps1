[CmdletBinding()]
param([ValidateSet('Doctor', 'RustTest', 'Verify')][string]$Action = 'Doctor')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This task requires Windows.' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Build Tools missing. Run pwsh -NoProfile -File scripts/windows/Install-BuildTools.ps1 (or mise run windows:setup).' }
$components = (Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$installation = & $vswhere -latest -products '*' -requires $components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Required MSVC/Windows SDK components missing. Run pwsh -NoProfile -File scripts/windows/Install-BuildTools.ps1 (or mise run windows:setup).' }
& (Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program $($Arguments -join ' ') failed ($LASTEXITCODE)." }
}

if ($Action -eq 'Doctor') {
    Invoke-Checked dotnet @('--version')
    Invoke-Checked rustc @('--version')
    Get-Command cl.exe, link.exe | Select-Object Name, Source
    Write-Output "Windows SDK: $env:WindowsSDKVersion"
    Write-Output "Build Tools: $installation"
    return
}

if ($Action -eq 'RustTest') {
    Invoke-Checked cargo @('test', '--locked', '--workspace')
    return
}

Invoke-Checked cargo @('fmt', '--all', '--', '--check')
Invoke-Checked cargo @('check', '--locked', '--workspace')
Invoke-Checked cargo @('test', '--locked', '--workspace')
Invoke-Checked pwsh @('-NoProfile', '-File', 'scripts/windows/Invoke-WinUI.ps1', '-Action', 'Test')
Invoke-Checked pwsh @('-NoProfile', '-File', 'scripts/windows/Test-WinUIContracts.ps1')
Invoke-Checked pwsh @('-NoProfile', '-File', 'scripts/windows/Invoke-WinUI.ps1', '-Action', 'Publish')
