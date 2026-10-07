[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$helper = Join-Path $PSScriptRoot 'InstallerBoundaryAcceptance.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Missing bounded installer boundary acceptance helpers.' }
. $helper
$script:cases = 0
function Assert-BoundaryTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:cases++
}
function Assert-BoundaryTestReject([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { $null = & $Operation } catch { $rejected = $true }
    Assert-BoundaryTest $rejected $Message
}
$run = '0123456789abcdef0123456789abcdef'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Get-InstallerBoundaryRoot $repo $run
Assert-BoundaryTest ($root -ceq (Join-Path $repo ('target/winui/installer-options-ui-' + $run))) 'The fixture root escaped its dedicated output prefix.'
Assert-InstallerBoundaryRoot $root $repo
$script:cases++
foreach ($invalid in @('', 'other', ('A' * 32), ('../' + $run))) {
    Assert-BoundaryTestReject { Get-InstallerBoundaryRoot $repo $invalid } 'An invalid fixture identity was accepted.'
}
foreach ($invalid in @($repo, (Join-Path $repo 'target/winui/publish'), ($root + '/child'), ($root + '-other'))) {
    Assert-BoundaryTestReject { Assert-InstallerBoundaryRoot $invalid $repo } 'An unrelated or nested path was accepted as the whole fixture.'
}
$key = Get-InstallerBoundaryRegistryKey $root $repo
Assert-BoundaryTest ($key -cmatch '^Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SteamWrapper-Installer-Test-[a-f0-9]{16}_is1$') 'The registry identity is not an isolated Inno identity.'
Assert-BoundaryTest ($key -ceq (Get-InstallerBoundaryRegistryKey $root.ToUpperInvariant() $repo)) 'The registry identity changed with Windows path casing.'
$contractRepo='C:\SteamWrapperBoundaryContract'
$contractRoot=Get-InstallerBoundaryRoot $contractRepo $run
Assert-BoundaryTest ((Get-InstallerBoundaryRegistryKey $contractRoot $contractRepo) -ceq 'Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamWrapper-Installer-Test-1a6dcc9b03c0d92c_is1') 'Isolated identity must hash the canonical program directory, including the program suffix.'
$selections = @('restore','profiles','backups','runner','settings','cache','logs','sensitive','all')
$plans = @(Get-InstallerBoundaryCleanupCases)
Assert-BoundaryTest (($plans.name -join ',') -ceq ($selections -join ',')) 'The minimal seven independent and two interacting cases changed.'
foreach ($name in $selections) {
    $plan = Get-InstallerBoundaryCleanupCase $name
    Assert-BoundaryTest ($plan.action -ceq ('cleanup-' + $name)) 'A cleanup action did not identify exactly its selected controls.'
    $before = [ordered]@{}
    foreach ($path in (Get-InstallerBoundaryOwnedDataFiles)) { $before[$path] = 'a' * 64 }
    foreach ($path in @('updates/trust-state.json','backups/retained.vdf',('backups/steam-launch-options/' + $run + '/123456-localconfig.vdf'),'cache/covers/player-art.cover','logs/player-notes.txt','games/save.dat')) { $before[$path] = 'b' * 64 }
    $after = [ordered]@{}
    foreach ($path in $before.Keys) { if ($path -cnotin $plan.removedData) { $after[$path] = $before[$path] } }
    Assert-InstallerBoundaryDataResult $plan $before $after
    $script:cases++
    $wrong = [ordered]@{}
    foreach ($path in $after.Keys) { $wrong[$path] = $after[$path] }
    $wrong.Remove('updates/trust-state.json')
    Assert-BoundaryTestReject { Assert-InstallerBoundaryDataResult $plan $before $wrong } 'Cleanup accepted deletion of retained update trust.'
    if ($plan.removedData.Count) {
        $wrong = [ordered]@{}
        foreach ($path in $after.Keys) { $wrong[$path] = $after[$path] }
        $wrong[$plan.removedData[0]] = 'a' * 64
        Assert-BoundaryTestReject { Assert-InstallerBoundaryDataResult $plan $before $wrong } 'A selected cleanup silently retained an expected ordinary fixture file.'
    }
}
Assert-BoundaryTestReject { Get-InstallerBoundaryCleanupCase 'profiles,cache' } 'An unreviewed arbitrary cleanup combination was accepted.'
$descriptor = [pscustomobject]@{schemaVersion=1;runId=$run;hostComputerName='HOST';sandboxOnly=$true;networkingDisabled=$true}
$guest = [pscustomobject]@{computerName='SANDBOX';userName='WDAGUtilityAccount';profile='C:\Users\WDAGUtilityAccount';manufacturer='Microsoft Corporation';model='Virtual Machine';build=26100;productType=1;x64=$true;sessionId=1;administrator=$true}
Assert-InstallerBoundaryGuestContext $guest $descriptor
$script:cases++
$reportDescriptor=$descriptor | ConvertTo-Json | ConvertFrom-Json
$reportDescriptor | Add-Member -NotePropertyName baseline -NotePropertyValue ([pscustomobject]@{tag='v0.2.5-preview.1'})
$reportDescriptor | Add-Member -NotePropertyName target -NotePropertyValue ([pscustomobject]@{tag='v0.2.6-preview.1'})
$initialReport=New-InstallerBoundaryDiskFullReport $guest $reportDescriptor
Assert-BoundaryTest ($initialReport.actualInno -is [bool] -and -not $initialReport.actualInno -and $initialReport.result -ceq 'running' -and
    -not $initialReport.productRecoveryPassed -and $initialReport.manifestsRebuilt -and $initialReport.localPayloadFixture) 'The real guest report cannot initialize or incorrectly claims public Inno acceptance.'
foreach ($mutation in @(
    @{name='computerName';value='HOST'},@{name='userName';value='admin'},@{name='profile';value='C:\Users\admin'},
    @{name='manufacturer';value='Other'},@{name='model';value='Host'},@{name='build';value=26000},
    @{name='productType';value=3},@{name='x64';value=$false},@{name='sessionId';value=0},@{name='administrator';value=$false}
)) {
    $copy = $guest | ConvertTo-Json | ConvertFrom-Json
    $copy.($mutation.name) = $mutation.value
    Assert-BoundaryTestReject { Assert-InstallerBoundaryGuestContext $copy $descriptor } ('Unsafe guest context accepted: ' + $mutation.name)
}
$vhd = 'C:\Users\Public\SteamWrapperInstallerBoundary-' + $run + '\failure.vhd'
$commands = New-InstallerBoundaryDiskPartCommands $vhd 'R' 512 $run
$commandLines = @($commands -split "`r`n")
$expectedLines = @(
    ('create vdisk file="' + $vhd + '" maximum=512 type=fixed'),
    ('select vdisk file="' + $vhd + '"'),
    'attach vdisk',
    'create partition primary',
    ('format fs=ntfs quick label="SwBd-' + $run.Substring(0,12) + '"'),
    'assign letter=R'
)
Assert-BoundaryTest ($commandLines.Count -eq 6) 'Diskpart requires six separate commands; array concatenation must not fold commands into the create line.'
for ($index = 0; $index -lt $expectedLines.Count; $index++) {
    Assert-BoundaryTest ($commandLines[$index] -ceq $expectedLines[$index]) ('Unexpected exact diskpart command at line ' + ($index + 1) + '.')
}
Assert-BoundaryTest ($commands -match 'maximum=512 type=fixed' -and $commands -match 'select vdisk file=' -and $commands -notmatch 'select disk|clean|delete|expand') 'Virtual volume creation was unbounded or could target an existing physical disk.'
foreach ($invalid in @('C:\failure.vhd','C:\AcceptanceInput\failure.vhd', ($vhd + '"'), ($vhd.Replace($run, 'other')))) {
    Assert-BoundaryTestReject { New-InstallerBoundaryDiskPartCommands $invalid 'R' 512 $run } 'A non-owned guest VHD path was accepted.'
}
foreach ($letter in @('C','D','R:','"R','r')) { Assert-BoundaryTestReject { New-InstallerBoundaryDiskPartCommands $vhd $letter 512 $run } 'A unsafe volume assignment was accepted.' }
foreach ($size in @(0,128,513,1024)) { Assert-BoundaryTestReject { New-InstallerBoundaryDiskPartCommands $vhd 'R' $size $run } 'An unbounded virtual volume size was accepted.' }
$expectedImage=[pscustomobject]@{Attached=$true}
$expectedDisk=[pscustomobject]@{Number=1;Size=512MB}
$expectedPartition=[pscustomobject]@{DiskNumber=1;DriveLetter='R'}
$storageObservation=[pscustomobject]@{reads=0;diskReads=0}
$binding=Wait-InstallerBoundaryVirtualDisk $vhd 'R' {
    param($imagePath)
    Assert-InstallerBoundary ($imagePath -ceq $vhd) 'The probe queried another image.'
    $storageObservation.reads++
    if($storageObservation.reads -lt 3){throw 'The newly attached disk is not yet visible to Storage CIM.'}
    return $expectedImage
} {
    param($inputImage)
    Assert-InstallerBoundary ([object]::ReferenceEquals($inputImage,$expectedImage)) 'The disk query lost the actual image binding.'
    $storageObservation.diskReads++;return $expectedDisk
} {param($driveLetter) Assert-InstallerBoundary ($driveLetter -ceq 'R') 'The probe queried another drive.';return $expectedPartition} 1000 1
Assert-BoundaryTest ($storageObservation.reads -eq 3 -and $storageObservation.diskReads -eq 1 -and $binding.attempts -eq 3 -and
    [object]::ReferenceEquals($binding.disk,$expectedDisk)) 'Transient Storage enumeration failures did not retain the actual image-to-disk binding.'
Assert-BoundaryTestReject {Wait-InstallerBoundaryVirtualDisk $vhd 'R' {$null} {$expectedDisk} {$expectedPartition} 20 1} 'Missing Storage objects were accepted or kept waiting without a bound.'
$foreignPartition=[pscustomobject]@{DiskNumber=2;DriveLetter='R'}
Assert-BoundaryTestReject {Wait-InstallerBoundaryVirtualDisk $vhd 'R' {$expectedImage} {$expectedDisk} {$foreignPartition} 1000 1} 'A partition on another disk was accepted.'
$oversizedDisk=[pscustomobject]@{Number=1;Size=1GB}
Assert-BoundaryTestReject {Wait-InstallerBoundaryVirtualDisk $vhd 'R' {$expectedImage} {$oversizedDisk} {$expectedPartition} 1000 1} 'An oversized disk was accepted.'
Assert-BoundaryTestReject {Wait-InstallerBoundaryVirtualDisk $vhd 'R' {([pscustomobject]@{Attached=$false})} {$expectedDisk} {$expectedPartition} 1000 1} 'A detached image was accepted.'
Assert-BoundaryTestReject {Wait-InstallerBoundaryVirtualDisk $vhd 'R' {$expectedImage} {$expectedDisk} {$expectedPartition} 0 1} 'The Storage wait accepted an invalid timeout.'
$legacyFrame=[pscustomobject]@{image=[pscustomobject]@{ImagePath=$vhd;DevicePath='\\.\PHYSICALDRIVE1';Number=1;Attached=$true;Size=512MB};pathNodes=@()}
$nodePath=$vhd
while($nodePath){$legacyFrame.pathNodes+=[pscustomobject]@{FullName=$nodePath;IsContainer=($nodePath -cne $vhd);Attributes=0};$nodePath=[IO.Path]::GetDirectoryName($nodePath)}
$legacyDrive=[pscustomobject]@{DeviceID='\\.\PHYSICALDRIVE1';Index=1;Size=510MB}
$legacyPartition=[pscustomobject]@{DeviceID='Disk #1, Partition #0';DiskIndex=1;Index=0;StartingOffset=1MB;Size=511MB}
$legacyLogical=[pscustomobject]@{DeviceID='R:';DriveType=3;FileSystem='NTFS';Size=(511MB-4096);FreeSpace=500MB}
$legacyGuid='\\?\Volume{11111111-2222-3333-4444-555555555555}\'
$legacyVolume=[pscustomobject]@{DeviceID=$legacyGuid;DriveLetter='R:';FileSystem='NTFS';Capacity=$legacyLogical.Size}
$legacyCallbacks=@{ReadImage={param($path) Assert-InstallerBoundary ($path -ceq $vhd) 'Another image was read.';return $legacyFrame};
    ReadDrives={param($image) Assert-InstallerBoundary ([object]::ReferenceEquals($image,$legacyFrame.image)) 'The drive query lost the actual image.';return $legacyDrive};
    ReadPartitions={param($drive) Assert-InstallerBoundary ([object]::ReferenceEquals($drive,$legacyDrive)) 'The first actual association lost its drive.';return $legacyPartition};
    ReadLogicalDisks={param($partition) Assert-InstallerBoundary ([object]::ReferenceEquals($partition,$legacyPartition)) 'The second actual association lost its partition.';return $legacyLogical};
    ReadVolumes={param($logical) Assert-InstallerBoundary ([object]::ReferenceEquals($logical,$legacyLogical)) 'The volume query lost its actual logical disk.';return $legacyVolume};
    ReadDeviceLength={param($image) Assert-InstallerBoundary ($image.DevicePath -ceq $legacyDrive.DeviceID) 'The exact length probe was not bound.';return 512MB};
    ReadVolumeGuid={param($letter) Assert-InstallerBoundary ($letter -ceq 'R') 'Another mount point was queried.';return $legacyGuid};TimeoutMilliseconds=1000;PollMilliseconds=1}
$legacyBinding=Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @legacyCallbacks
Assert-BoundaryTest ($legacyBinding.provider -ceq 'Win32' -and $legacyBinding.deviceLength -eq 512MB -and
    [object]::ReferenceEquals($legacyBinding.disk,$legacyDrive) -and $legacyBinding.volume.DeviceID -ceq $legacyGuid) 'The actual callback chain did not establish the complete legacy VHD binding.'
foreach($change in @('wrongImagePath','detached','systemDisk','wrongDevicePath','wrongImageSize','reparseFile','reparseParent','missingParent',
    'wrongDriveIndex','wrongDriveDevice','wrongGeometrySize','wrongPartitionDisk','wrongPartitionIdentity','wrongPartitionBounds',
    'wrongLogicalDrive','wrongDriveType','wrongFileSystem','wrongLogicalSize','wrongVolumeDrive','wrongVolumeCapacity','wrongVolumeGuid','malformedVolumeGuid')) {
    $savedFrame=$legacyFrame;$savedDrive=$legacyDrive;$savedPartition=$legacyPartition;$savedLogical=$legacyLogical;$savedVolume=$legacyVolume
    $legacyFrame=$savedFrame|ConvertTo-Json -Depth 5|ConvertFrom-Json;$legacyDrive=$savedDrive|ConvertTo-Json|ConvertFrom-Json
    $legacyPartition=$savedPartition|ConvertTo-Json|ConvertFrom-Json;$legacyLogical=$savedLogical|ConvertTo-Json|ConvertFrom-Json;$legacyVolume=$savedVolume|ConvertTo-Json|ConvertFrom-Json
    try {
        switch($change){
            'wrongImagePath' {$legacyFrame.image.ImagePath='C:\failure.vhd'}
            'detached' {$legacyFrame.image.Attached=$false}
            'systemDisk' {$legacyFrame.image.DevicePath='\\.\PHYSICALDRIVE0';$legacyFrame.image.Number=0}
            'wrongDevicePath' {$legacyFrame.image.DevicePath='\\.\PHYSICALDRIVE2'}
            'wrongImageSize' {$legacyFrame.image.Size=1GB}
            'reparseFile' {$legacyFrame.pathNodes[0].Attributes=[int][IO.FileAttributes]::ReparsePoint}
            'reparseParent' {$legacyFrame.pathNodes[1].Attributes=[int][IO.FileAttributes]::ReparsePoint}
            'missingParent' {$legacyFrame.pathNodes=$legacyFrame.pathNodes[0]}
            'wrongDriveIndex' {$legacyDrive.Index=2}
            'wrongDriveDevice' {$legacyDrive.DeviceID='\\.\PHYSICALDRIVE2'}
            'wrongGeometrySize' {$legacyDrive.Size=1GB}
            'wrongPartitionDisk' {$legacyPartition.DiskIndex=2}
            'wrongPartitionIdentity' {$legacyPartition.DeviceID='Disk #2, Partition #0'}
            'wrongPartitionBounds' {$legacyPartition.StartingOffset=2MB;$legacyPartition.Size=512MB}
            'wrongLogicalDrive' {$legacyLogical.DeviceID='C:'}
            'wrongDriveType' {$legacyLogical.DriveType=2}
            'wrongFileSystem' {$legacyLogical.FileSystem='FAT32'}
            'wrongLogicalSize' {$legacyLogical.Size=1GB}
            'wrongVolumeDrive' {$legacyVolume.DriveLetter='C:'}
            'wrongVolumeCapacity' {$legacyVolume.Capacity++}
            'wrongVolumeGuid' {$legacyVolume.DeviceID='\\?\Volume{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}\'}
            'malformedVolumeGuid' {$legacyVolume.DeviceID='R:\'}
        }
        Assert-BoundaryTestReject {Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @legacyCallbacks} ('Unsafe legacy binding accepted: '+$change)
    } finally {$legacyFrame=$savedFrame;$legacyDrive=$savedDrive;$legacyPartition=$savedPartition;$legacyLogical=$savedLogical;$legacyVolume=$savedVolume}
}
foreach($reader in @('ReadImage','ReadDrives','ReadPartitions','ReadLogicalDisks','ReadVolumes')) {
    $wrongCallbacks=$legacyCallbacks.Clone();$originalReader=$legacyCallbacks[$reader]
    $wrongCallbacks[$reader]={param($inputValue) $items=@(& $originalReader $inputValue);return @($items+$items)}.GetNewClosure()
    Assert-BoundaryTestReject {Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @wrongCallbacks} ('Ambiguous legacy binding accepted at '+$reader)
}
$wrongCallbacks=$legacyCallbacks.Clone();$wrongCallbacks.ReadDeviceLength={513MB}
Assert-BoundaryTestReject {Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @wrongCallbacks} 'Wrong actual device length was accepted.'
$wrongCallbacks=$legacyCallbacks.Clone();$wrongCallbacks.ReadImage={$null};$wrongCallbacks.TimeoutMilliseconds=20
Assert-BoundaryTestReject {Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @wrongCallbacks} 'Absent actual image exceeded the bounded wait or was accepted.'
$legacyRace=[pscustomobject]@{reads=0}
$raceCallbacks=$legacyCallbacks.Clone();$raceCallbacks.ReadDrives={param($image) $legacyRace.reads++;if($legacyRace.reads -lt 3){throw 'Win32 enumeration is not ready.'};return $legacyDrive}
$legacyBinding=Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @raceCallbacks
Assert-BoundaryTest ($legacyRace.reads -eq 3 -and $legacyBinding.attempts -eq 3) 'The complete actual legacy chain did not retry transient provider failures.'
$wrongCallbacks=$legacyCallbacks.Clone();$wrongCallbacks.ReadVolumeGuid={'\\?\Volume{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}\'}
Assert-BoundaryTestReject {Wait-InstallerBoundaryLegacyVirtualDisk $vhd 'R' @wrongCallbacks} 'Another actual mount-point GUID was accepted.'
Add-Type -TypeDefinition (Get-InstallerBoundaryDiskReaderSource)
Assert-BoundaryTestReject {[SteamWrapperBoundaryDiskReader]::ReadLength($vhd,'\\.\PHYSICALDRIVE1',1)} 'The actual read-only device API could run outside the guest.'
Assert-BoundaryTestReject {[SteamWrapperBoundaryDiskReader]::ReadVolumeGuid('R')} 'The actual mount-point API could run outside the guest.'
$facts = [pscustomobject]@{hostDigestVerified=$true;newVirtualDiskVerified=$true;journalWritten=$true;stagingCopyObserved=$true;stagingIncomplete=$true;hostExitCode=11;freeBytesAtFailure=0;currentInstallationUnchanged=$true;repairSucceeded=$true;dataUnchanged=$true}
Assert-InstallerBoundaryDiskFullResult $facts
$script:cases++
foreach ($name in @('hostDigestVerified','newVirtualDiskVerified','journalWritten','stagingCopyObserved','stagingIncomplete','currentInstallationUnchanged','repairSucceeded','dataUnchanged')) {
    $copy = $facts | ConvertTo-Json | ConvertFrom-Json
    $copy.$name = $false
    Assert-BoundaryTestReject { Assert-InstallerBoundaryDiskFullResult $copy } ('Disk-full acceptance fabricated or omitted ' + $name + '.')
}
foreach ($mutation in @(@{name='hostExitCode';value=0},@{name='freeBytesAtFailure';value=65536})) {
    $copy = $facts | ConvertTo-Json | ConvertFrom-Json
    $copy.($mutation.name) = $mutation.value
    Assert-BoundaryTestReject { Assert-InstallerBoundaryDiskFullResult $copy } 'Preflight rejection or a healthy-volume copy was accepted as a mid-copy disk-full result.'
}
$complete=$facts | ConvertTo-Json | ConvertFrom-Json
$complete | Add-Member -NotePropertyName result -NotePropertyValue 'passed'
$complete | Add-Member -NotePropertyName productRecoveryPassed -NotePropertyValue $true
$complete | Add-Member -NotePropertyName cleanup -NotePropertyValue ([pscustomobject]@{status='passed';detached=$true})
Assert-InstallerBoundaryDiskFullCompletion $complete
$script:cases++
foreach ($field in @('result','productRecoveryPassed','cleanup')) {
    $copy=$complete | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    if ($field -ceq 'result') {$copy.result='failed'} elseif ($field -ceq 'cleanup') {$copy.cleanup.detached=$false} else {$copy.productRecoveryPassed=$false}
    Assert-BoundaryTestReject {Assert-InstallerBoundaryDiskFullCompletion $copy} 'Successful product recovery hid failed test-volume cleanup.'
}
foreach ($path in @('baseline/SteamWrapper.Manager.exe','target/zh-CN/SteamWrapper.Application.resources.dll','target/deployment-manifest.json')) {
    Assert-InstallerBoundaryAssetPath $path
    $script:cases++
}
foreach ($path in @('target/../profiles.toml','target//file.exe','C:/target/file.exe','target/file.exe:stream','target/.env','target/logs/private.txt','target/NUL.exe','target/file.')) {
    Assert-BoundaryTestReject { Assert-InstallerBoundaryAssetPath $path } 'An unsafe or private sealed payload path was accepted.'
}
Add-Type -TypeDefinition (Get-InstallerBoundaryDiskFillerSource)
$filler=[SteamWrapperBoundaryDiskFiller]::new('R:\SteamWrapperInstallerBoundary-' + $run + '\program')
Assert-BoundaryTestReject { $filler.Start() } 'The real disk filler could start on the host.'
foreach ($path in @('C:\program','R:\SteamWrapperInstallerBoundary-other\program',('R:\SteamWrapperInstallerBoundary-' + $run + '\program\child'))) {
    Assert-BoundaryTestReject { [SteamWrapperBoundaryDiskFiller]::new($path) } 'The actual filler accepted an unbounded program path.'
}
Add-Type -TypeDefinition (Get-InstallerBoundaryRegistryFaultSource)
$fault=[SteamWrapperBoundaryRegistryFault]::new((Join-Path $root 'program'),$key,[byte[]]::new(32))
Assert-BoundaryTest ($null -ne $fault -and -not $fault.StateSeen -and -not $fault.Applied) 'Constructing the registry watcher changed a registry key or started a process.'
foreach ($invalidKey in @('Software\SteamWrapper',($key + '\child'),($key.Replace('SteamWrapper-Installer-Test-','SteamWrapper-')))) {
    Assert-BoundaryTestReject { [SteamWrapperBoundaryRegistryFault]::new((Join-Path $root 'program'),$invalidKey,[byte[]]::new(32)) } 'The actual late-phase fault could target an unrelated key.'
}
Assert-BoundaryTestReject { [SteamWrapperBoundaryRegistryFault]::new((Join-Path $repo 'target/winui/publish'),$key,[byte[]]::new(32)) } 'The actual late-phase fault accepted a non-fixture program root.'
Write-Output "Installer boundary helper tests passed: $script:cases cases. No UI, registry, disk or guest changes were made."
