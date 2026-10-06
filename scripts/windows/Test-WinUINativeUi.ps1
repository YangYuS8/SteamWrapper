[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$RepoRoot = (Join-Path $PSScriptRoot '../..'),
    [Parameter(Position = 1)][string]$PublishDirectory,
    [switch]$Inspect,
    [ValidateSet('add-local', 'manual-appid', 'dirty-add', 'keyboard', 'updates', 'runner-update', 'profile-actions', 'steam-names', 'existing-editor', 'saved-editor')][string[]]$Cases = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Native WinUI acceptance requires Windows.' }
if ($Inspect -and $Cases.Count) { throw 'Inspection and focused native cases are separate modes.' }
if (-not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
    throw 'Native WinUI acceptance requires an unlocked interactive Windows desktop. Service CI only compiles the developer harness.'
}

$repository = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($PublishDirectory)) { $PublishDirectory = Join-Path $repository 'target/winui/publish' }
$publication = [IO.Path]::GetFullPath($PublishDirectory)
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
$null = Assert-WinUIReleasePath $repository $repository
if (-not (Test-Path -LiteralPath $publication -PathType Container)) {
    throw 'Publish a complete Manager first with scripts/windows/Invoke-WinUI.ps1 -Action Publish. This native acceptance command never publishes or installs software.'
}
if ([IO.Directory]::GetParent($publication).Name -ieq 'versions') { throw 'Native UI acceptance requires a portable publication, not an installed version directory.' }
# Read-only package validation: refuse missing files, runtime/user data, reparse
# points and oversized trees before the harness can create a fixture or window.
$files = @(Get-WinUIReleaseFiles -PublishDirectory $publication -RepositoryRoot $repository)
$required = @((Get-WinUIReleaseRequiredFiles)) + @('SteamWrapper.Deployment.dll', 'Deployment/SteamWrapper.exe')
foreach ($relative in $required) {
    $record = @($files | Where-Object { $_.Path -ieq $relative })
    if ($record.Count -ne 1 -or $record[0].Bytes -eq 0) { throw "Existing publication is missing a non-empty required file: $relative" }
}
$runner = @($files | Where-Object { $_.Path -ieq 'Runner/SteamWrapperRunner.exe' })[0]
$manifest = Read-WinUIReleaseText (Join-Path $publication 'Runner/runner-manifest.json') $repository | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.contractVersion -ne 2 -or $manifest.sha256 -cne $runner.Sha256) {
    throw 'Existing publication Runner manifest does not match its executable bytes or contract.'
}

$project = Join-Path $repository 'apps/manager-winui/SteamWrapper.NativeUi.Tests/SteamWrapper.NativeUi.Tests.csproj'
function Invoke-NativeUiCommand([string[]]$Arguments) {
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) { throw "dotnet failed ($LASTEXITCODE). Native UI fixture artifacts and any open fixture windows are retained; close windows normally." }
}

Push-Location -LiteralPath $repository
try {
    Invoke-NativeUiCommand @('restore', $project, '--locked-mode')
    Invoke-NativeUiCommand @('build', $project, '--no-restore', '--configuration', 'Release')
    $arguments = @('run', '--project', $project, '--no-build', '--no-restore', '--configuration', 'Release', '--', $repository, $publication)
    if ($Inspect) { $arguments += '--inspect' }
    foreach ($case in $Cases) { $arguments += @('--case', $case) }
    Invoke-NativeUiCommand $arguments
} finally { Pop-Location }
