[CmdletBinding()]
param(
    [string]$PublishDirectory,
    [string]$BaselineDirectory,
    [string]$Tag,
    [string]$BaselineTag,
    [string]$Compiler
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Installer option acceptance requires Windows.' }
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $repoRoot 'target/winui/publish' }
$publish = Assert-WinUIInstallerPath $PublishDirectory
if (-not $Tag) { $Tag = 'v' + (Get-Content -LiteralPath (Join-Path $publish 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version + '-options.1' }
$null = Assert-WinUIInstallerTag $Tag
if ($BaselineDirectory) {
    $baseline = Assert-WinUIInstallerPath $BaselineDirectory
    if (-not $BaselineTag) { $BaselineTag = 'v' + (Get-Content -LiteralPath (Join-Path $baseline 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version + '-options.1' }
    if ([Version](Assert-WinUIInstallerTag $BaselineTag) -ge [Version](Assert-WinUIInstallerTag $Tag)) { throw 'The baseline must have an older numeric product version.' }
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIProductMetadata.ps1') -PublishDirectory $baseline -ExpectedVersion (Assert-WinUIInstallerTag $BaselineTag)
    $null = & (Join-Path $PSScriptRoot 'Test-WinUIProductMetadata.ps1') -PublishDirectory $publish -ExpectedVersion (Assert-WinUIInstallerTag $Tag)
}
$root = Assert-WinUIInstallerPath (Join-Path $repoRoot ('target/winui/installer-options-' + [Guid]::NewGuid().ToString('N'))) -Output
$program = Join-Path $root 'program'
$data = Join-Path $root 'data'
[IO.Directory]::CreateDirectory($data) | Out-Null
$sentinel = Join-Path $data 'preserve.txt'
[IO.File]::WriteAllText($sentinel, 'Installer options must not change player data.')
$beforeHash = (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
$startShortcut = Join-Path $root 'shell-fixture/StartMenu/SteamWrapper.lnk'
$desktopShortcut = Join-Path $root 'shell-fixture/Desktop/SteamWrapper.lnk'
$events = [Collections.Generic.List[object]]::new()
$oldTest = $env:STEAMWRAPPER_DEPLOYMENT_TEST
$oldLocal = $env:LOCALAPPDATA
$oldSandbox = $env:STEAMWRAPPER_E2E_ROOT
$env:STEAMWRAPPER_DEPLOYMENT_TEST = '1'
$env:LOCALAPPDATA = $data
$env:STEAMWRAPPER_E2E_ROOT = $root
$passed = $false

function Invoke-OptionsProcess([string]$Executable, [string]$Name, [string[]]$Options = @()) {
    $log = Join-Path $root ($Name + '.log')
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/LOG="' + $log + '"')) + $Options
    $process = Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit(120000)) { throw "Installer option case $Name timed out; no process was killed." }
        $events.Add([pscustomobject]@{ name = $Name; exitCode = $process.ExitCode; log = $log })
        if ($process.ExitCode -ne 0) { throw "Installer option case $Name failed ($($process.ExitCode)); see $log." }
        # The lease receipt can precede process teardown. Let only this fixture's
        # maintenance process finish before the next install/uninstall case.
        foreach ($helper in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Deployment')) {
            try {
                if (-not $helper.HasExited -and [string]::Equals($helper.MainModule.FileName,
                    (Join-Path $program 'maintenance/SteamWrapper.Deployment.exe'), [StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $helper.WaitForExit(15000)) { throw 'The isolated maintenance helper did not exit normally; it was not killed.' }
                }
            } catch [ComponentModel.Win32Exception] { } catch [InvalidOperationException] { }
            finally { $helper.Dispose() }
        }
        Write-Host "Passed installer option process: $Name"
    } finally { $process.Dispose() }
}
function Assert-OptionsShortcuts([bool]$StartMenu, [bool]$Desktop) {
    if ((Test-Path -LiteralPath $startShortcut) -ne $StartMenu) { throw "Start menu shortcut differed from the selected task: expected $StartMenu." }
    if ((Test-Path -LiteralPath $desktopShortcut) -ne $Desktop) { throw "Desktop shortcut differed from the selected task: expected $Desktop." }
}
function Remove-OptionsInstallation([string]$Name) {
    $uninstaller = Join-Path $program 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        Invoke-OptionsProcess $uninstaller $Name
        Assert-OptionsShortcuts $false $false
        # Inno's temporary cleanup process removes the original executable after
        # the uninstall process exits. Do not launch that retiring image again.
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ((Test-Path -LiteralPath $uninstaller) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 150 }
        if (Test-Path -LiteralPath $uninstaller) { throw 'The successful isolated uninstaller did not finish removing itself.' }
    }
}
function Assert-RecordedTasks([string]$Path, [string]$Expected) {
    $line = @(Get-Content -LiteralPath $Path | Where-Object { $_ -like 'Tasks=*' })
    if ($line.Count -ne 1 -or $line[0] -cne "Tasks=$Expected") { throw 'Setup did not retain the previously selected shortcut tasks.' }
}

try {
    $build = @{ Tag = $Tag; PublishDirectory = $publish; IsolatedRoot = $program; OutputDirectory = (Join-Path $root 'setup') }
    if ($Compiler) { $build.Compiler = $Compiler }
    $setup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @build

    # Start the older product in a fresh root: an intentionally retained newer
    # removal journal must never be erased to make an old Host accept a downgrade.
    if ($BaselineDirectory) {
        $baselineBuild = $build.Clone()
        $baselineBuild.Tag = $BaselineTag
        $baselineBuild.PublishDirectory = $baseline
        $baselineBuild.OutputDirectory = Join-Path $root 'baseline-setup'
        $baselineSetup = & (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') @baselineBuild
        Invoke-OptionsProcess $baselineSetup 'baseline-desktop-only' @('/TASKS=desktopicon')
        Assert-OptionsShortcuts $false $true
        $saved = Join-Path $root 'upgrade.inf'
        Invoke-OptionsProcess $setup 'upgrade-retains-tasks' @(('/SAVEINF="' + $saved + '"'))
        Assert-RecordedTasks $saved 'desktopicon'
        Assert-OptionsShortcuts $false $true
        $state = Get-Content -LiteralPath (Join-Path $program 'installation.json') -Raw | ConvertFrom-Json
        if ($state.current.tag -cne $Tag -or $state.previous.tag -cne $BaselineTag) { throw 'The option-retention check did not upgrade the real baseline.' }
        Remove-OptionsInstallation 'remove-upgraded'
    }

    # The old installer created a Start-menu link even when /TASKS selected only desktopicon.
    Invoke-OptionsProcess $setup 'desktop-only' @('/LANG=english', '/TASKS=desktopicon')
    Assert-OptionsShortcuts $false $true
    $saved = Join-Path $root 'repair.inf'
    Invoke-OptionsProcess $setup 'remember-on-repair' @(('/SAVEINF="' + $saved + '"'))
    Assert-RecordedTasks $saved 'desktopicon'
    Assert-OptionsShortcuts $false $true
    Remove-OptionsInstallation 'remove-desktop-only'

    Invoke-OptionsProcess $setup 'defaults' @('/LANG=chinesesimplified')
    Assert-OptionsShortcuts $true $false
    Remove-OptionsInstallation 'remove-defaults'

    Invoke-OptionsProcess $setup 'both-shortcuts' @('/TASKS=startmenuicon,desktopicon')
    Assert-OptionsShortcuts $true $true
    Remove-OptionsInstallation 'remove-both'

    Invoke-OptionsProcess $setup 'no-icons-overrides-start-menu' @('/NOICONS', '/TASKS=startmenuicon,desktopicon')
    Assert-OptionsShortcuts $false $true
    Remove-OptionsInstallation 'remove-no-icons'

    Invoke-OptionsProcess $setup 'no-shortcuts' @('/TASKS=""')
    Assert-OptionsShortcuts $false $false
    Remove-OptionsInstallation 'remove-no-shortcuts'

    if ((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Installer options changed the data sentinel.' }
    $passed = $true
} finally {
    try { Remove-OptionsInstallation 'cleanup' }
    finally {
        $env:STEAMWRAPPER_DEPLOYMENT_TEST = $oldTest
        $env:LOCALAPPDATA = $oldLocal
        $env:STEAMWRAPPER_E2E_ROOT = $oldSandbox
        $evidence = [ordered]@{ passed = $passed; isolatedRoot = $root; tag = $Tag; baselineTag = $BaselineTag; genuineUpgrade = [bool]$BaselineDirectory; cleanVm = $false; cases = $events.ToArray() }
        [IO.File]::WriteAllText((Join-Path $root 'evidence.json'), ($evidence | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    }
}
Write-Output "Installer shortcut options passed: $root"
