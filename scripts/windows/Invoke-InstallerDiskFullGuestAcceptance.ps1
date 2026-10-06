# Inbox PowerShell 5.1. Guest-only actual NativeAOT copy on a newly created,
# fixed 512 MiB virtual volume. This does not run an Inno UI or install runtimes.
[CmdletBinding()]
param([switch]$HelpersOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'InstallerBoundaryAcceptance.ps1')
if ($HelpersOnly) { return }
$inputDirectory='C:\AcceptanceInput\installer-boundary'
$descriptorPath=Join-Path $inputDirectory 'manifest.json'
Assert-InstallerBoundary (Test-Path -LiteralPath $descriptorPath -PathType Leaf) 'Missing sealed installer-boundary guest input.'
Assert-InstallerBoundary ((Get-Item -LiteralPath $descriptorPath).Length -le 1MB) 'The guest descriptor exceeds its bound.'
$descriptor=Get-Content -LiteralPath $descriptorPath -Raw | ConvertFrom-Json
$system=Get-CimInstance Win32_ComputerSystem; $os=Get-CimInstance Win32_OperatingSystem
$context=[pscustomobject]@{computerName=[Environment]::MachineName;userName=[Environment]::UserName;profile=[Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile);manufacturer=$system.Manufacturer;model=$system.Model;build=[int]$os.BuildNumber;productType=[int]$os.ProductType;x64=[Environment]::Is64BitOperatingSystem;sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;administrator=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
Assert-InstallerBoundaryGuestContext $context $descriptor
Assert-InstallerBoundary ($PSScriptRoot -ieq $inputDirectory) 'Run only the sealed guest-local script from the dedicated read-only input mapping.'
foreach ($name in @('STEAMWRAPPER_DEPLOYMENT_TEST','STEAMWRAPPER_E2E_ROOT','STEAM_DIR')) { Assert-InstallerBoundary (-not [Environment]::GetEnvironmentVariable($name,'Process')) 'The fresh guest contains unexpected test overrides.' }
$run=[string]$descriptor.runId
$root='C:\Users\Public\SteamWrapperInstallerBoundary-' + $run
$output='C:\AcceptanceOutput\installer-boundary-' + $run
Assert-InstallerBoundary (-not (Test-Path -LiteralPath $root)) 'The guest-local run already exists and is preserved.'
Assert-InstallerBoundary (-not (Test-Path -LiteralPath $output)) 'Existing guest evidence is preserved.'
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $total=0L
Assert-InstallerBoundary ($descriptor.assets.Count -gt 0 -and $descriptor.assets.Count -le 4096) 'Expected a bounded sealed pair of complete payloads.'
foreach ($asset in $descriptor.assets) {
    Assert-InstallerBoundaryAssetPath $asset.path
    Assert-InstallerBoundary ($names.Add($asset.path) -and $asset.sha256 -cmatch '^[a-f0-9]{64}$' -and $asset.bytes -gt 0 -and $asset.bytes -le 512MB) 'Invalid or duplicate sealed payload asset.'
    $total += [long]$asset.bytes
    Assert-InstallerBoundary ($total -le 1GB) 'The complete fixture input exceeds its bounded size.'
    $path=Join-Path $inputDirectory $asset.path
    Assert-InstallerBoundary ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -eq $asset.bytes -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $asset.sha256) 'A guest input differs from its sealed payload identity.'
}
foreach ($kind in @('baseline','target')) {
    $tag=[string]$descriptor.$kind.tag
    Assert-InstallerBoundary ($tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') 'Invalid payload version identity.'
    $manifest=Get-Content -LiteralPath (Join-Path $inputDirectory ($kind + '/deployment-manifest.json')) -Raw | ConvertFrom-Json
    Assert-InstallerBoundary ($manifest.tag -ceq $tag -and $manifest.version -ceq $tag.TrimStart('v').Split('-')[0]) 'Payload metadata differs from the sealed release identity.'
    foreach ($relative in @('SteamWrapper.Manager.exe','Deployment/SteamWrapper.exe','Runner/SteamWrapperRunner.exe')) {
        Assert-InstallerBoundary ($names.Contains($kind + '/' + $relative)) 'A mandatory genuine PE was omitted from the sealed input.'
        $info=[Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $inputDirectory ($kind + '/' + $relative)))
        Assert-InstallerBoundary ($info.FileVersion -match ('^' + [regex]::Escape($manifest.version) + '(?:\.0)?$')) 'A genuine payload PE version differs from its release identity; metadata-only numeric fixtures are refused.'
    }
    foreach ($file in $manifest.files) {
        Assert-InstallerBoundary ($names.Contains($kind + '/' + $file.path)) 'The sealed input omits a declared complete payload file.'
        $record=@($descriptor.assets | Where-Object path -CEQ ($kind + '/' + $file.path))
        Assert-InstallerBoundary ($record.Count -eq 1 -and $record[0].bytes -eq $file.bytes -and $record[0].sha256 -ceq $file.sha256) 'Payload manifest and sealed input differ.'
    }
}
Assert-InstallerBoundary (([Version]($descriptor.target.tag.TrimStart('v').Split('-')[0])) -gt ([Version]($descriptor.baseline.tag.TrimStart('v').Split('-')[0]))) 'Use a genuine newer numeric target payload.'
$vhd=Join-Path $root 'failure.vhd'
$letter=@('R','S','T','U','V','W','X','Y','Z') | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) } | Select-Object -First 1
Assert-InstallerBoundary ($null -ne $letter) 'No unused bounded virtual drive letter is available.'
$diskCommands=New-InstallerBoundaryDiskPartCommands $vhd $letter 512 $run
[IO.Directory]::CreateDirectory($root) | Out-Null; [IO.Directory]::CreateDirectory($output) | Out-Null
$report=New-InstallerBoundaryDiskFullReport $context $descriptor
$attached=$false; $processesExited=$true; $filler=$null; $saved=@{}
function Write-DiskBoundaryEvidence { [IO.File]::WriteAllText((Join-Path $output 'evidence.json'),($report | ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false)) }
function Invoke-DiskBoundaryHost([string]$Operation,[string]$Payload,[string]$Name) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$nativeHost; $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardError=$true; $start.RedirectStandardOutput=$true
    $start.Arguments=$Operation + ' --test-root --language en --root "' + $program + '"'
    if ($Payload) { $start.Arguments += ' --payload "' + $Payload + '"' }
    $process=[Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(120000)) { $script:processesExited=$false; throw 'The owned NativeAOT process timed out; it was not killed and the virtual disk remains attached.' }
        [IO.File]::WriteAllText((Join-Path $output ($Name + '.stderr.txt')),$process.StandardError.ReadToEnd(),[Text.UTF8Encoding]::new($false))
        return $process.ExitCode
    } finally { $process.Dispose() }
}
try {
    $createScript=Join-Path $root 'create-volume.txt'; [IO.File]::WriteAllText($createScript,$diskCommands,[Text.UTF8Encoding]::new($false))
    & (Join-Path $env:windir 'System32/diskpart.exe') /s $createScript *> (Join-Path $output 'diskpart-create.log')
    $createExitCode=$LASTEXITCODE
    $report.diskpartCreateExitCode=$createExitCode
    Assert-InstallerBoundary ($createExitCode -eq 0 -and (Test-Path -LiteralPath $vhd -PathType Leaf)) ('The bounded guest VHD was not created (diskpart exit code ' + $createExitCode + '); see diskpart-create.log. No physical disk was selected.')
    $image=Get-DiskImage -ImagePath $vhd -ErrorAction Stop
    Assert-InstallerBoundary ($null -ne $image) 'Get-DiskImage did not return the newly created guest VHD.'
    $attached=[bool]$image.Attached
    Assert-InstallerBoundary ($createExitCode -eq 0 -and (Test-Path -LiteralPath ($letter + ':\'))) 'The bounded guest VHD could not be created; no physical disk was selected.'
    # A newly attached VHD may not yet be present in Storage's cached CIM objects.
    # Refresh only this disposable guest, then retain the actual image-to-disk binding.
    Update-HostStorageCache -ErrorAction Stop | Out-Null
    $report.storageEnumerationRefresh=$true
    $binding=Wait-InstallerBoundaryVirtualDisk $vhd $letter {param($path) Get-DiskImage -ImagePath $path -ErrorAction Stop} {
        param($inputImage) $inputImage | Get-Disk -ErrorAction Stop
    } {param($driveLetter) Get-Partition -DriveLetter $driveLetter -ErrorAction Stop}
    $report.storageBinding=[ordered]@{attempts=$binding.attempts;diskNumber=$binding.disk.Number;partitionDiskNumber=$binding.partition.DiskNumber;driveLetter=[string]$binding.partition.DriveLetter;capacityBytes=$binding.disk.Size}
    $attached=$true; $report.newVirtualDiskVerified=$true
    $volumeRoot=$letter + ':\SteamWrapperInstallerBoundary-' + $run
    $program=Join-Path $volumeRoot 'program'; $local=Join-Path $volumeRoot 'data'; $data=Join-Path $local 'SteamWrapper'
    [IO.Directory]::CreateDirectory($data) | Out-Null
    $sentinel=Join-Path $data 'profiles.toml'; [IO.File]::WriteAllText($sentinel,'Disposable configuration bytes preserved through a real disk-full copy.')
    $dataHash=(Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
    foreach ($name in @('LOCALAPPDATA','STEAMWRAPPER_DEPLOYMENT_TEST','STEAMWRAPPER_E2E_ROOT','STEAM_DIR')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    $env:LOCALAPPDATA=$local; $env:STEAMWRAPPER_DEPLOYMENT_TEST='1'; $env:STEAMWRAPPER_E2E_ROOT=$volumeRoot; $env:STEAM_DIR=Join-Path $volumeRoot 'steam-fixture'
    $nativeHost=Join-Path $inputDirectory 'target/Deployment/SteamWrapper.exe'; $report.hostDigestVerified=$true
    Assert-InstallerBoundary ((Invoke-DiskBoundaryHost '--install' (Join-Path $inputDirectory 'baseline') 'baseline-install') -eq 0) 'The genuine baseline did not install on the new virtual volume.'
    $statePath=Join-Path $program 'installation.json'; $stateBefore=(Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    $launcherBefore=(Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash
    Assert-InstallerBoundary (-not (Test-Path -LiteralPath (Join-Path $program 'installation-journal.json'))) 'Baseline left a journal before the copy fault.'
    Add-Type -TypeDefinition (Get-InstallerBoundaryDiskFillerSource)
    $filler=New-Object SteamWrapperBoundaryDiskFiller($program); $filler.Start()
    $exit=Invoke-DiskBoundaryHost '--install' (Join-Path $inputDirectory 'target') 'exhausted-target-install'
    $filler.Stop()
    $report.hostExitCode=$exit; $report.journalWritten=$filler.JournalSeen; $report.stagingCopyObserved=$filler.CopySeen
    $report.freeBytesAtFailure=$filler.FreeBytes; $report.copyWitness=[ordered]@{path=$filler.WitnessPath;bytes=$filler.WitnessBytes;fillerFailure=$filler.Failure}
    Assert-InstallerBoundary ($filler.Exhausted -and $filler.JournalSeen -and $filler.CopySeen -and $exit -eq 11) 'The actual copy did not fail on an exhausted volume after admission; no disk-full pass is claimed.'
    $stages=@(Get-ChildItem -LiteralPath $program -Directory -Filter '.staging-*')
    Assert-InstallerBoundary ($stages.Count -eq 1) 'The failed copy did not retain exactly its incomplete owned stage.'
    $incoming=Get-Content -LiteralPath (Join-Path $inputDirectory 'target/deployment-manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $incoming.files) {
        $path=Join-Path $stages[0].FullName $file.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne $file.bytes) { $report.stagingIncomplete=$true; break }
    }
    Assert-InstallerBoundary $report.stagingIncomplete 'The target payload was already completely copied; do not claim a mid-copy failure.'
    $report.currentInstallationUnchanged=((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -ceq $stateBefore -and (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash -ceq $launcherBefore)
    $ownedFiller=Join-Path $volumeRoot 'own-space-filler.bin'
    Assert-InstallerBoundary (Test-Path -LiteralPath $ownedFiller -PathType Leaf) 'The exact own space filler is unavailable.'
    [IO.File]::Delete($ownedFiller)
    $report.repairSucceeded=((Invoke-DiskBoundaryHost '--repair' '' 'repair-after-freeing-own-filler') -eq 0)
    $report.dataUnchanged=((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ceq $dataHash)
    Assert-InstallerBoundaryDiskFullResult ([pscustomobject]$report)
    Assert-InstallerBoundary ((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -ceq $stateBefore -and (Get-FileHash -LiteralPath (Join-Path $program 'SteamWrapper.exe') -Algorithm SHA256).Hash -ceq $launcherBefore) 'Repair did not retain the exact prior installation and launcher.'
    $report.result='passed'; $report.productRecoveryPassed=$true
} catch {
    $report.result='failed'; $report.failure=[ordered]@{type=$_.Exception.GetType().FullName;message=$_.Exception.Message}
    throw
} finally {
    try {
        if ($null -ne $filler) { $filler.Stop() }
    } catch {
        $processesExited=$false; $report.result='failed'; $report.fillerStopFailure=$_.Exception.Message
    } finally {
        foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key,$item.Value,'Process') }
        if ($attached -and $processesExited) {
            try {
                $detachScript=Join-Path $root 'detach-own-volume.txt'
                [IO.File]::WriteAllText($detachScript,('select vdisk file="' + $vhd + '"' + "`r`n" + 'detach vdisk'),[Text.UTF8Encoding]::new($false))
                & (Join-Path $env:windir 'System32/diskpart.exe') /s $detachScript *> (Join-Path $output 'diskpart-detach.log')
                $report.cleanup=[ordered]@{status='failed';detachExitCode=$LASTEXITCODE;detached=(-not (Get-DiskImage -ImagePath $vhd).Attached)}
                Assert-InstallerBoundary ($report.cleanup.detachExitCode -eq 0 -and $report.cleanup.detached) 'Normal detachment of the own virtual disk failed; the guest disk is preserved and no force-detach was attempted.'
                $report.cleanup.status='passed'
            } catch {
                $report.result='failed'; $report.cleanup.failure=$_.Exception.Message
            }
        } elseif ($attached) {
            $report.cleanup=[ordered]@{status='retained-for-live-owned-process';detached=$false}
        } else { $report.cleanup=[ordered]@{status='not-attached';detached=$false} }
        Write-DiskBoundaryEvidence
    }
}
Assert-InstallerBoundaryDiskFullCompletion ([pscustomobject]$report)
Write-Output "Actual NativeAOT mid-copy disk-full acceptance passed: $output"
