[CmdletBinding()]
param([ValidateSet('Doctor', 'RustTest', 'Verify')][string]$Action = 'Doctor')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This task requires Windows.' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Build Tools missing. Run mise run windows:setup.' }
$components = (Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$installation = & $vswhere -latest -products '*' -requires $components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Required MSVC/Windows SDK components missing. Run mise run windows:setup.' }
& (Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program $($Arguments -join ' ') failed ($LASTEXITCODE)." }
}

if ($Action -eq 'Doctor') {
    Invoke-Checked dotnet @('--version')
    Invoke-Checked rustc @('--version')
    Invoke-Checked node @('--version')
    Invoke-Checked pnpm @('--version')
    Invoke-Checked dx @('--version')
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
Invoke-Checked pnpm @('install', '--frozen-lockfile')
Invoke-Checked pnpm @('--filter', 'steamwrapper-manager-dioxus-e2e', 'exec', 'tsc', '--noEmit')

# Only stage build output into the already-ignored bundle resource directory.
Invoke-Checked cargo @('build', '--locked', '--release', '-p', 'steamwrapper-runner')
$resources = Join-Path $repoRoot 'apps/manager-dioxus/resources/runner'
New-Item -ItemType Directory -Path $resources -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'target/release/steamwrapper-runner.exe') -Destination (Join-Path $resources 'SteamWrapperRunner.exe') -Force
if (-not (Test-Path -LiteralPath (Join-Path $resources 'steamwrapper-runner'))) {
    New-Item -ItemType File -Path (Join-Path $resources 'steamwrapper-runner') | Out-Null
}
Push-Location (Join-Path $repoRoot 'apps/manager-dioxus')
try {
    Invoke-Checked dx @('check')
    Invoke-Checked dx @('build', '--release')
} finally { Pop-Location }
Invoke-Checked cargo @('build', '--locked', '-p', 'steamwrapper-manager-dioxus', '--features', 'e2e')
Invoke-Checked pnpm @('--filter', 'steamwrapper-manager-dioxus-e2e', 'run', 'e2e:native')
