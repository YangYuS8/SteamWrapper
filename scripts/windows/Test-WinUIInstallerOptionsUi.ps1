[CmdletBinding()]
param([string]$PublishDirectory, [string]$Tag, [string]$FixtureRoot,
    [ValidateSet('english', 'chinesesimplified')][string[]]$Languages = @('english', 'chinesesimplified'),
    [switch]$LayoutOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Native installer acceptance requires an interactive Windows desktop.' }
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $repo 'target/winui/publish' }
if (-not $Tag) { $Tag = 'v' + (Get-Content -LiteralPath (Join-Path $PublishDirectory 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version + '-preview.1' }
$null = Assert-WinUIInstallerTag $Tag
if (-not $FixtureRoot) { $FixtureRoot = Join-Path $repo ('target/winui/installer-options-ui-' + [Guid]::NewGuid().ToString('N')) }
$root = Assert-WinUIInstallerPath $FixtureRoot -Output
if (-not $root.StartsWith((Join-Path $repo 'target/winui/installer-options-ui-'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Expected a disposable installer-options-ui fixture under target/winui.' }
$program = Join-Path $root 'program'
$data = Join-Path $root 'data/SteamWrapper'
$setup = Join-Path $root "setup/SteamWrapper-$Tag-win-x64-setup.exe"
if (-not (Test-Path -LiteralPath $setup)) {
    $setup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') -Tag $Tag -PublishDirectory $PublishDirectory -IsolatedRoot $program -OutputDirectory (Join-Path $root 'setup')
}
$project = Join-Path $repo 'apps/manager-winui/SteamWrapper.NativeUi.Tests/SteamWrapper.NativeUi.Tests.csproj'
& dotnet restore $project --locked-mode
if ($LASTEXITCODE) { throw 'Native installer acceptance harness locked restore failed.' }
& dotnet build $project --no-restore -c Release --nologo
if ($LASTEXITCODE) { throw 'Native installer acceptance harness did not build.' }
$harness = Join-Path (Split-Path $project) 'bin/Release/net10.0-windows10.0.26100.0/SteamWrapper.NativeUi.Tests.dll'
$saved = @{}
foreach ($name in @('LOCALAPPDATA', 'STEAMWRAPPER_DEPLOYMENT_TEST', 'STEAMWRAPPER_E2E_ROOT', 'STEAM_DIR')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$env:LOCALAPPDATA = Join-Path $root 'data'
$env:STEAMWRAPPER_DEPLOYMENT_TEST = '1'
$env:STEAMWRAPPER_E2E_ROOT = $root
$env:STEAM_DIR = Join-Path $root 'steam-fixture'
$preserved = @('profiles.toml', 'ui-settings.json', 'logs/manager-startup.log', 'backups/preserve.toml', 'bin/SteamWrapperRunner.exe', 'cache/covers/custom.txt')
$removed = @('cache/covers/123.cover', ('cache/updates/setup-' + ('a' * 64) + '.exe'))
$hashes = @{}
$passed = $false
function Assert-FixtureData([bool]$ExpectCache) {
    foreach ($file in $preserved) {
        if ((Get-FileHash -LiteralPath (Join-Path $data $file) -Algorithm SHA256).Hash -cne $hashes[$file]) { throw "Unselected player data changed: $file" }
    }
    foreach ($file in $removed) {
        $path = Join-Path $data $file
        if ((Test-Path -LiteralPath $path) -ne $ExpectCache) { throw "Cache selection did not match actual file state: $file" }
        if ($ExpectCache -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $hashes[$file]) { throw "Cancelled uninstall changed cache: $file" }
    }
}
function Invoke-NativeCase([string]$Executable, [string]$Language, [string]$Action) {
    & dotnet $harness --installer-options-ui $root $Executable $Language $Action
    if ($LASTEXITCODE) { throw "Interactive installer case failed: $Language $Action. Windows and fixture remain for diagnosis." }
}
function Invoke-SilentFixture([string]$Executable, [string]$Language, [string]$Name) {
    $process = Start-Process -FilePath $Executable -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/LANG=$Language", ('/LOG="' + (Join-Path $root ($Name + '.log')) + '"')) -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit(120000) -or $process.ExitCode -ne 0) { throw "Fixture process failed: $Name; no process was killed." }
    } finally { $process.Dispose() }
}
try {
    foreach ($file in @($preserved) + @($removed)) {
        $path = Join-Path $data $file
        [IO.Directory]::CreateDirectory((Split-Path $path)) | Out-Null
        [IO.File]::WriteAllText($path, "Disposable UI acceptance fixture: $file")
        $hashes[$file] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    foreach ($language in $Languages) {
        if (-not $LayoutOnly) {
            Invoke-NativeCase $setup $language 'setup'
            Assert-FixtureData $true
            if (Test-Path -LiteralPath (Join-Path $program 'installation.json')) { throw 'Cancelled setup unexpectedly installed Manager.' }
        }
        Invoke-SilentFixture $setup $language ("install-$language")
        $manifest = Join-Path $program 'installation.json'
        $beforeManifest = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
        $uninstaller = Join-Path $program 'unins000.exe'
        Invoke-NativeCase $uninstaller $language 'cancel'
        Assert-FixtureData $true
        if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -cne $beforeManifest) { throw 'Cancelled uninstall changed the installation manifest.' }
        if ($LayoutOnly) {
            Invoke-SilentFixture $uninstaller $language ("uninstall-$language")
            Assert-FixtureData $true
        } else {
            Invoke-NativeCase $uninstaller $language 'cache'
            Assert-FixtureData $false
        }
        if (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe')) { throw 'Confirmed uninstall left Manager installed.' }
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ((Test-Path -LiteralPath $uninstaller) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 150 }
        if (Test-Path -LiteralPath $uninstaller) { throw 'Isolated uninstaller did not finish deleting itself.' }
        [IO.File]::WriteAllText((Join-Path $root ("data-$language.json")), ([ordered]@{
            passed=$true; language=$language; setupCancellationTested=(-not $LayoutOnly); uninstallCancellationPreservedData=$true;
            selectedCleanup=$(if ($LayoutOnly) { 'none' } else { 'cache' }); unselectedDataUnchanged=$true; managerRemoved=$true
        } | ConvertTo-Json))
        foreach ($file in $removed) { [IO.File]::WriteAllText((Join-Path $data $file), "Disposable UI acceptance fixture: $file") }
    }
    $passed = $true
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    [IO.File]::WriteAllText((Join-Path $root ('evidence-' + ($Languages -join '-') + '.json')), ([ordered]@{ passed=$passed; isolatedRoot=$root; tag=$Tag; languages=$Languages; cleanVm=$false; layoutOnly=[bool]$LayoutOnly; defaultCleanup='none'; selectedCleanup=$(if ($LayoutOnly) { 'none' } else { 'cache' }); unselectedDataHashes=$hashes; screenshots=@(Get-ChildItem -LiteralPath $root -Filter '*.png' | ForEach-Object Name) } | ConvertTo-Json -Depth 5))
}
Write-Output "Native installer options passed: $root"
