[CmdletBinding()]
param([ValidateSet('Build', 'Test', 'Publish', 'Sandbox')][string]$Action = 'Build')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'WinUI requires Windows.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$project = Join-Path $repoRoot 'apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj'
$tests = Join-Path $repoRoot 'apps/manager-winui/SteamWrapper.Application.Tests/SteamWrapper.Application.Tests.csproj'
$publishRoot = Join-Path $repoRoot 'target/winui'
$output = Join-Path $publishRoot 'publish'

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE)." }
}

if ($Action -eq 'Test') {
    Invoke-Checked dotnet @('restore', $tests, '--locked-mode')
    Invoke-Checked dotnet @('test', $tests, '--no-restore', '--configuration', 'Release')
    return
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Run mise run windows:setup first.' }
$components = (Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$installation = & $vswhere -latest -products '*' -requires $components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Required MSVC/SDK components are missing.' }
& (Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

Invoke-Checked cargo @('build', '--locked', '--release', '-p', 'steamwrapper-runner')
$stage = Join-Path $repoRoot 'target/winui/runner'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$runnerPath = Join-Path $stage 'SteamWrapperRunner.exe'
Copy-Item -LiteralPath (Join-Path $repoRoot 'target/release/steamwrapper-runner.exe') -Destination $runnerPath -Force
$versionMatch = @(Select-String -LiteralPath (Join-Path $repoRoot 'crates/runner/Cargo.toml') -Pattern '^version = "([0-9]+\.[0-9]+\.[0-9]+)"$')
if ($versionMatch.Count -ne 1) { throw 'Runner package must have one three-part release version.' }
@{
    schemaVersion = 1
    version = $versionMatch[0].Matches[0].Groups[1].Value
    contractVersion = 2
    sha256 = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'runner-manifest.json') -Encoding utf8NoBOM

Invoke-Checked dotnet @('restore', $project, '--locked-mode', '-r', 'win-x64', '-p:Platform=x64')
if ($Action -eq 'Build') {
    Invoke-Checked dotnet @('build', $project, '--no-restore', '--configuration', 'Release', '-p:Platform=x64')
    return
}
. (Join-Path $PSScriptRoot 'Complete-WinUIPublish.ps1')
$candidate = Join-Path $publishRoot ('publish-staging-' + [Guid]::NewGuid().ToString('N'))
Assert-WinUIBuildPath $candidate
New-Item -ItemType Directory -Path $candidate | Out-Null
try {
    Invoke-Checked dotnet @('publish', $project, '--no-restore', '--configuration', 'Release', '--runtime', 'win-x64', '--self-contained', 'true', '-p:Platform=x64', '--output', $candidate)
} catch {
    Write-Warning "The previous release is unchanged. Failed publish output is retained at $candidate"
    throw
}
foreach ($running in @(Get-Process -Name 'SteamWrapper.Manager' -ErrorAction SilentlyContinue)) {
    if ($running.Path -and $running.Path.StartsWith($output + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Close the running WinUI preview before replacing its release directory. New output is retained at $candidate"
    }
}
$output = Complete-WinUIPublish -Root $publishRoot -Candidate $candidate -RequiredFiles @(
    'SteamWrapper.Manager.exe', 'SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll', 'SteamWrapper.Manager.pri',
    'coreclr.dll', 'Microsoft.UI.Xaml.dll', 'Microsoft.WindowsAppRuntime.dll', 'Microsoft.Windows.Storage.Pickers.Projection.dll',
    'Runner/SteamWrapperRunner.exe', 'Runner/runner-manifest.json'
)
Write-Output "WinUI preview: $output"
if ($Action -ne 'Sandbox') { return }

# A new fixture for every preview, including Steam discovery and all stable paths.
$fixture = Join-Path $repoRoot ('target/winui/sandbox/' + [Guid]::NewGuid().ToString('N'))
$steam = Join-Path $fixture 'Steam'
$localData = Join-Path $fixture 'LocalAppData'
$game = Join-Path $steam 'steamapps/common/示例游戏'
New-Item -ItemType Directory -Path $game, $localData -Force | Out-Null
@'
"AppState"
{
    "appid" "480"
    "name" "示例游戏（隔离预览）"
    "installdir" "示例游戏"
}
'@ | Set-Content -LiteralPath (Join-Path $steam 'steamapps/appmanifest_480.acf') -Encoding utf8NoBOM
$start = [System.Diagnostics.ProcessStartInfo]::new((Join-Path $output 'SteamWrapper.Manager.exe'))
$start.UseShellExecute = $false
$start.Environment['STEAM_DIR'] = $steam
$start.Environment['LOCALAPPDATA'] = $localData
$start.Environment['XDG_DATA_HOME'] = (Join-Path $fixture 'xdg')
$start.Environment['STEAMWRAPPER_E2E_ROOT'] = $fixture
$process = [System.Diagnostics.Process]::Start($start)
Write-Output "Sandbox PID $($process.Id); fixture: $fixture"
