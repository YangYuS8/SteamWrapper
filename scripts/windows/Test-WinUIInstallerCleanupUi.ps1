[CmdletBinding()]
param([string]$PublishDirectory, [string]$Tag, [string]$FixtureRoot,
    [ValidateSet('english','chinesesimplified')][string]$Language='english',
    [ValidateSet('restore','profiles','backups','runner','settings','cache','logs','sensitive','all')][string[]]$Cases=@('restore','profiles','backups','runner','settings','cache','logs','sensitive','all'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'Actual installer checkbox acceptance requires an agreed interactive Windows test desktop.' }
. (Join-Path $PSScriptRoot 'InstallerBoundaryAcceptance.ps1')
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $PublishDirectory) { $PublishDirectory=Join-Path $repo 'target/winui/publish' }
$publish=Assert-WinUIInstallerPath $PublishDirectory
if (-not $Tag) { $Tag='v' + (Get-Content -LiteralPath (Join-Path $publish 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json).version + '-preview.1' }
$null=Assert-WinUIInstallerTag $Tag
if (-not $FixtureRoot) { $FixtureRoot=Get-InstallerBoundaryRoot $repo ([Guid]::NewGuid().ToString('N')) }
Assert-InstallerBoundaryRoot $FixtureRoot $repo
$root=[IO.Path]::GetFullPath($FixtureRoot)
if ((Test-Path -LiteralPath $root) -and @(Get-ChildItem -LiteralPath $root -Force | Select-Object -First 1).Count) { throw 'Choose a fresh fixture; existing evidence and files are preserved.' }
if (@($Cases | Select-Object -Unique).Count -ne $Cases.Count) { throw 'Cleanup acceptance cases must be unique.' }
$plans=@($Cases | ForEach-Object { Get-InstallerBoundaryCleanupCase $_ })
[IO.Directory]::CreateDirectory($root) | Out-Null
$program=Join-Path $root 'program'; $data=Join-Path $root 'data/SteamWrapper'; $steam=Join-Path $root 'steam-fixture'
$setup=& (Join-Path $PSScriptRoot 'New-WinUIInstaller.ps1') -Tag $Tag -PublishDirectory $publish -IsolatedRoot $program -OutputDirectory (Join-Path $root 'setup')
$build=Get-Content -LiteralPath (Join-Path $root 'setup/installer-build.json') -Raw | ConvertFrom-Json
Assert-InstallerBoundary ($build.isolated -is [bool] -and $build.isolated) 'Cleanup acceptance never executes a production installer.'
$project=Join-Path $repo 'apps/manager-winui/SteamWrapper.NativeUi.Tests/SteamWrapper.NativeUi.Tests.csproj'
& dotnet restore $project --locked-mode
if ($LASTEXITCODE) { throw 'Native installer harness locked restore failed.' }
& dotnet build $project --no-restore -c Release --nologo
if ($LASTEXITCODE) { throw 'Native installer harness build failed.' }
$harness=Join-Path (Split-Path $project) 'bin/Release/net10.0-windows10.0.26100.0/SteamWrapper.NativeUi.Tests.dll'
$saved=@{}; $records=[Collections.Generic.List[object]]::new(); $passed=$false
$legacySteamBackup='backups/steam-launch-options/' + [Guid]::NewGuid().ToString('N') + '/123456-localconfig.vdf'
$processTemp=Join-Path $root 'process-temp'
[IO.Directory]::CreateDirectory($processTemp) | Out-Null
Assert-InstallerBoundary (-not ((Get-Item -LiteralPath $processTemp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Isolated process temporary files must not follow links.'
foreach ($name in @('LOCALAPPDATA','STEAMWRAPPER_DEPLOYMENT_TEST','STEAMWRAPPER_E2E_ROOT','STEAM_DIR','TEMP','TMP')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$env:LOCALAPPDATA=Join-Path $root 'data'; $env:STEAMWRAPPER_DEPLOYMENT_TEST='1'; $env:STEAMWRAPPER_E2E_ROOT=$root; $env:STEAM_DIR=$steam
$env:TEMP=$processTemp; $env:TMP=$processTemp
function Write-CleanupFixture([string]$Relative, [string]$Text) {
    $path=Join-Path $data $Relative
    [IO.Directory]::CreateDirectory((Split-Path $path)) | Out-Null
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
}
function Read-CleanupFixtureHashes {
    $result=[ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $data -Recurse -File -Force) {
        Assert-InstallerBoundary (-not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Disposable data must not contain links.'
        $result[[IO.Path]::GetRelativePath($data,$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return ,$result
}
function Invoke-CleanupSilent([string]$Executable,[string]$Name) {
    $start=[Diagnostics.ProcessStartInfo]::new($Executable); $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    foreach ($arg in @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LANG=' + $Language),('/LOG=' + (Join-Path $root ($Name + '.log'))))) { $start.ArgumentList.Add($arg) }
    $process=[Diagnostics.Process]::Start($start)
    try { Assert-InstallerBoundary ($process.WaitForExit(120000) -and $process.ExitCode -eq 0) ('Isolated setup failed: ' + $Name + '. No process was killed.') }
    finally { $process.Dispose() }
}
try {
    foreach ($plan in $plans) {
        $beforeSteam=[ordered]@{}; $expectedSteam=[ordered]@{}
        foreach ($relative in Get-InstallerBoundaryOwnedDataFiles) { Write-CleanupFixture $relative ('Disposable fixture: ' + $relative) }
        [IO.Directory]::CreateDirectory((Join-Path $data 'bin')) | Out-Null
        Copy-Item -LiteralPath (Join-Path $publish 'Runner/SteamWrapperRunner.exe') -Destination (Join-Path $data 'bin/SteamWrapperRunner.exe') -Force
        Copy-Item -LiteralPath (Join-Path $publish 'Runner/runner-manifest.json') -Destination (Join-Path $data 'bin/runner-manifest.json') -Force
        foreach ($relative in @('updates/trust-state.json','backups/retained.vdf','cache/covers/player-art.cover','logs/player-notes.txt','games/save.dat')) {
            Write-CleanupFixture $relative ('Must retain fixture: ' + $relative)
        }
        [IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps')) | Out-Null
        foreach ($account in @('123456','654321')) {
            $path=Join-Path $steam ('userdata/' + $account + '/config/localconfig.vdf')
            [IO.Directory]::CreateDirectory((Split-Path $path)) | Out-Null
            $command=if ($plan.recognizedLaunchOptions) { '"' + (Join-Path $data 'bin/SteamWrapperRunner.exe') + '" --appid "123" -- %command%' } else { '-windowed' }
            $escaped=$command.Replace('\','\\').Replace('"','\"')
            $text='// retain account ' + $account + "`r`n" + '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "123" { "LaunchOptions" "' + $escaped + '" } "456" { "LaunchOptions" "-player-custom" } } } } } }'
            [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
            $beforeSteam[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $expectedSteam[$path]=if ($plan.restoreSteam) { $text.Replace('"LaunchOptions" "' + $escaped + '"','"LaunchOptions" ""') } else { $text }
        }
        # Unknown backups belong outside the protected operation inventory. A
        # historical numeric-account snapshot remains a recognized retained backup.
        if (-not (Test-Path -LiteralPath (Join-Path $data $legacySteamBackup))) {
            $historicalAccount=Join-Path $steam 'userdata/123456/config/localconfig.vdf'
            Write-CleanupFixture $legacySteamBackup ([IO.File]::ReadAllText($historicalAccount,[Text.Encoding]::UTF8))
        }
        $before=Read-CleanupFixtureHashes
        Invoke-CleanupSilent $setup ('install-' + $plan.name)
        $uninstaller=Join-Path $program 'unins000.exe'
        Assert-InstallerBoundary (Test-Path -LiteralPath $uninstaller -PathType Leaf) 'The isolated setup did not produce an uninstaller.'
        & dotnet $harness --installer-options-ui $root $uninstaller $Language $plan.action
        Assert-InstallerBoundary ($LASTEXITCODE -eq 0) ('Native cleanup selection failed: ' + $plan.name + '. Its window was not killed.')
        $uninstallLog=Join-Path $root ($plan.action + '-' + $Language + '.log')
        $temporaryImages=[regex]::Matches([IO.File]::ReadAllText($uninstallLog),'(?m)Current Uninstall EXE: (?<path>[^\r\n]+)')
        Assert-InstallerBoundary ($temporaryImages.Count -gt 0) 'The actual uninstaller did not report its second-phase image location.'
        foreach ($image in $temporaryImages) {
            $actual=[IO.Path]::GetFullPath($image.Groups['path'].Value.Trim())
            Assert-InstallerBoundary ($actual.StartsWith($processTemp + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'The actual second-phase uninstaller escaped its owned temporary root.'
        }
        $after=Read-CleanupFixtureHashes
        Assert-InstallerBoundaryDataResult $plan $before $after
        foreach ($path in $expectedSteam.Keys) {
            Assert-InstallerBoundary ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq $expectedSteam[$path]) 'Cleanup did not preserve every unrelated Steam byte or restore the exact selected command.'
        }
        if ($plan.restoreSteam) {
            $newBackups=@($after.Keys | Where-Object { $_ -like 'backups/steam-launch-options/*' -and -not $before.Contains($_) })
            Assert-InstallerBoundary ($newBackups.Count -eq 4) 'Same-volume restoration did not create the original and replaced-byte backups for both accounts.'
            foreach ($path in $beforeSteam.Keys) {
                $account=Split-Path (Split-Path (Split-Path $path) -Parent) -Leaf
                foreach ($suffix in @('-localconfig.vdf','-replaced.vdf')) {
                    $backup=@($newBackups | Where-Object { $_ -like ('*/' + $account + $suffix) })
                    Assert-InstallerBoundary ($backup.Count -eq 1 -and $after[$backup[0]] -ceq $beforeSteam[$path]) 'A per-account restoration backup differs from the exact pre-uninstall account file.'
                }
            }
        }
        Assert-InstallerBoundary (-not (Test-Path -LiteralPath (Join-Path $program 'SteamWrapper.exe'))) 'Confirmed cleanup left Manager installed.'
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        while ((Test-Path -LiteralPath $uninstaller) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Assert-InstallerBoundary (-not (Test-Path -LiteralPath $uninstaller)) 'The uninstaller did not finish normally; it was not killed.'
        $records.Add([ordered]@{name=$plan.name;language=$Language;actualInnoCheckboxes=$true;selectedRemoval=$plan.removedData;restoreSteam=$plan.restoreSteam;twoAccountBackupsVerified=$plan.restoreSteam;protectedAndUnselectedHashesUnchanged=$true;historicalSteamBackupRetained=$true;temporaryProcessLocationVerified=$true;managerRemoved=$true})
    }
    $passed=$true
} finally {
    foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key,$item.Value,'Process') }
    [IO.File]::WriteAllText((Join-Path $root 'cleanup-evidence.json'),([ordered]@{schemaVersion=1;result=$(if($passed){'passed'}else{'failed'});fixtureRoot=$root;processTemporaryRoot=$processTemp;isolated=$true;cleanVm=$false;tag=$Tag;setupSha256=$build.installer.sha256;cases=$records.ToArray();noGamesLaunched=$true;noProcessesKilled=$true} | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
Write-Output "Actual Inno cleanup mapping passed: $root"
