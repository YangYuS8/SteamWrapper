# Import-only acceptance helpers. No UI, registry, process, disk or guest actions.
Set-StrictMode -Version Latest
function Assert-InstallerBoundary([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-InstallerBoundaryRoot([string]$RepositoryRoot, [string]$RunId) {
    Assert-InstallerBoundary ($RunId -cmatch '^[a-f0-9]{32}$') 'Expected a fresh bounded fixture identity.'
    return Join-Path ([IO.Path]::GetFullPath($RepositoryRoot)) ('target/winui/installer-options-ui-' + $RunId)
}
function Assert-InstallerBoundaryRoot([string]$Root, [string]$RepositoryRoot) {
    $root = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $prefix = Join-Path ([IO.Path]::GetFullPath($RepositoryRoot)) 'target/winui/installer-options-ui-'
    Assert-InstallerBoundary ($root.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and
        $root.Substring($prefix.Length) -imatch '^[a-f0-9]{32}$') 'Expected the whole dedicated installer fixture, not a parent, child or unrelated root.'
    for ($path = $root; $path; $path = [IO.Path]::GetDirectoryName($path)) {
        if (Test-Path -LiteralPath $path) {
            Assert-InstallerBoundary (-not ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Fixture ancestors cannot redirect outside their owned tree.'
        }
    }
}
function Get-InstallerBoundaryRegistryKey([string]$Root, [string]$RepositoryRoot) {
    Assert-InstallerBoundaryRoot $Root $RepositoryRoot
    $hash = [Security.Cryptography.SHA256]::Create()
    # New-WinUIInstaller derives IsolatedId from its program directory.
    $program=[IO.Path]::GetFullPath((Join-Path $Root 'program')).TrimEnd('\','/')
    try { $id = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($program.ToUpperInvariant())))).Replace('-','').ToLowerInvariant().Substring(0,16) }
    finally { $hash.Dispose() }
    return 'Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamWrapper-Installer-Test-' + $id + '_is1'
}
function Get-InstallerBoundaryOwnedDataFiles {
    return @('profiles.toml','backups/profiles-20261006T1020301234567Z-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.toml',
        'bin/SteamWrapperRunner.exe','bin/runner-manifest.json','ui-settings.json','cache/covers/123.cover',
        ('cache/updates/setup-' + ('a' * 64) + '.exe'),'logs/runner-123.log','logs/manager-startup.log')
}
function Get-InstallerBoundaryCleanupCases {
    $groups = [ordered]@{
        restore = @(); profiles = @('profiles.toml'); backups = @('backups/profiles-20261006T1020301234567Z-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.toml')
        runner = @('bin/SteamWrapperRunner.exe','bin/runner-manifest.json'); settings = @('ui-settings.json')
        cache = @('cache/covers/123.cover',('cache/updates/setup-' + ('a' * 64) + '.exe')); logs = @('logs/runner-123.log','logs/manager-startup.log')
    }
    foreach ($name in $groups.Keys) {
        [pscustomobject]@{name=$name;action=('cleanup-' + $name);restoreSteam=($name -ceq 'restore');removedData=@($groups[$name]);recognizedLaunchOptions=($name -cnotin @('profiles','runner'))}
    }
    [pscustomobject]@{name='sensitive';action='cleanup-sensitive';restoreSteam=$true;removedData=@($groups.profiles + $groups.runner);recognizedLaunchOptions=$true}
    [pscustomobject]@{name='all';action='cleanup-all';restoreSteam=$true;removedData=@(Get-InstallerBoundaryOwnedDataFiles);recognizedLaunchOptions=$true}
}
function Get-InstallerBoundaryCleanupCase([string]$Name) {
    $cases = @(Get-InstallerBoundaryCleanupCases | Where-Object name -CEQ $Name)
    Assert-InstallerBoundary ($cases.Count -eq 1) 'Expected one of the seven independent or two reviewed interaction cases.'
    return $cases[0]
}
function Assert-InstallerBoundaryDataResult($Plan, [Collections.IDictionary]$Before, [Collections.IDictionary]$After) {
    $known = Get-InstallerBoundaryCleanupCase $Plan.name
    Assert-InstallerBoundary (($Plan.removedData -join ',') -ceq ($known.removedData -join ',') -and $Plan.restoreSteam -eq $known.restoreSteam) 'The observed cleanup plan differs from its bounded selection.'
    foreach ($path in $Before.Keys) {
        if ($path -cin $known.removedData) { Assert-InstallerBoundary (-not $After.Contains($path)) ('Selected disposable data was retained: ' + $path) }
        else { Assert-InstallerBoundary ($After.Contains($path) -and $After[$path] -ceq $Before[$path]) ('Unselected or protected data changed: ' + $path) }
    }
}
function Assert-InstallerBoundaryGuestContext($Context, $Descriptor) {
    Assert-InstallerBoundary ($Descriptor.schemaVersion -eq 1 -and $Descriptor.runId -cmatch '^[a-f0-9]{32}$' -and
        $Descriptor.sandboxOnly -is [bool] -and $Descriptor.sandboxOnly -and $Descriptor.networkingDisabled -is [bool] -and $Descriptor.networkingDisabled -and
        $Descriptor.hostComputerName -is [string] -and $Descriptor.hostComputerName.Length -gt 0 -and
        $Context.computerName -ine $Descriptor.hostComputerName -and $Context.userName -ieq 'WDAGUtilityAccount' -and
        $Context.profile.TrimEnd('\') -ieq 'C:\Users\WDAGUtilityAccount' -and $Context.manufacturer -ceq 'Microsoft Corporation' -and
        $Context.model -ceq 'Virtual Machine' -and $Context.build -ge 26100 -and $Context.productType -eq 1 -and
        $Context.x64 -is [bool] -and $Context.x64 -and $Context.sessionId -gt 0 -and $Context.administrator -is [bool] -and $Context.administrator) 'Virtual-volume acceptance is permitted only in its fresh Windows Sandbox guest, never on the host.'
}
function New-InstallerBoundaryDiskFullReport($Context, $Descriptor) {
    Assert-InstallerBoundaryGuestContext $Context $Descriptor
    return [ordered]@{schemaVersion=1;result='running';scenario='NativeAotMidCopyDiskFull';environment='Windows Sandbox';context=$Context;runId=$Descriptor.runId;capacityMiB=512;actualInno=$false;localPayloadFixture=$true;manifestsRebuilt=$true;numericPeVersionsVerified=$true;baselineTag=$Descriptor.baseline.tag;targetTag=$Descriptor.target.tag;hostDigestVerified=$false;newVirtualDiskVerified=$false;journalWritten=$false;stagingCopyObserved=$false;stagingIncomplete=$false;hostExitCode=$null;freeBytesAtFailure=-1;currentInstallationUnchanged=$false;repairSucceeded=$false;dataUnchanged=$false;productRecoveryPassed=$false;noProcessesKilled=$true;machinePolicyChanged=$false;cleanup=[ordered]@{status='not-started';detached=$false};failure=$null}
}
function New-InstallerBoundaryDiskPartCommands([string]$VhdPath, [string]$DriveLetter, [int]$CapacityMB, [string]$RunId) {
    Assert-InstallerBoundary ($RunId -cmatch '^[a-f0-9]{32}$' -and $VhdPath -ceq ('C:\Users\Public\SteamWrapperInstallerBoundary-' + $RunId + '\failure.vhd') -and
        $DriveLetter -cmatch '^[R-Z]$' -and $CapacityMB -ge 256 -and $CapacityMB -le 512) 'Only a new guest-local 256–512 MiB fixed virtual disk and unused R–Z drive may be used.'
    return @(('create vdisk file="' + $VhdPath + '" maximum=' + $CapacityMB + ' type=fixed'),
        ('select vdisk file="' + $VhdPath + '"'),'attach vdisk','create partition primary',
        ('format fs=ntfs quick label="SwBd-' + $RunId.Substring(0,12) + '"'),('assign letter=' + $DriveLetter)) -join "`r`n"
}
function Wait-InstallerBoundaryVirtualDisk([string]$VhdPath, [string]$DriveLetter,
    [scriptblock]$ReadImage, [scriptblock]$ReadDisk, [scriptblock]$ReadPartition,
    [int]$TimeoutMilliseconds=30000, [int]$PollMilliseconds=250) {
    Assert-InstallerBoundary ($TimeoutMilliseconds -gt 0 -and $TimeoutMilliseconds -le 30000 -and
        $PollMilliseconds -gt 0 -and $PollMilliseconds -le 1000) 'Storage enumeration must have a bounded wait.'
    $timer=[Diagnostics.Stopwatch]::StartNew();$attempts=0;$lastFailure='No complete Storage image/disk/partition result.'
    do {
        $attempts++;$observedImage=$null;$observedDisk=$null;$observedPartition=$null
        try {
            $observedImage=& $ReadImage $VhdPath
            if($null -ne $observedImage){$observedDisk=& $ReadDisk $observedImage}
            if($null -ne $observedDisk){$observedPartition=& $ReadPartition $DriveLetter}
        } catch {$lastFailure=$_.Exception.Message}
        if($null -ne $observedImage -and $null -ne $observedDisk -and $null -ne $observedPartition) {
            Assert-InstallerBoundary (@($observedImage).Count -eq 1 -and @($observedDisk).Count -eq 1 -and @($observedPartition).Count -eq 1) 'Expected one actual VHD, disk and partition.'
            foreach($pair in @(@($observedImage,'Attached'),@($observedDisk,'Number'),@($observedDisk,'Size'),@($observedPartition,'DiskNumber'),@($observedPartition,'DriveLetter'))) {
                Assert-InstallerBoundary ($null -ne $pair[0].PSObject.Properties[$pair[1]]) 'Storage binding returned an incomplete object.'
            }
            Assert-InstallerBoundary ($observedImage.Attached -and $observedDisk.Number -eq $observedPartition.DiskNumber -and
                $observedPartition.DriveLetter -ceq $DriveLetter -and $observedDisk.Size -le 512MB -and $observedDisk.Size -ge 500MB) 'The assigned drive is not the newly created bounded VHD.'
            return [pscustomobject]@{image=$observedImage;disk=$observedDisk;partition=$observedPartition;attempts=$attempts}
        }
        if($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds){break}
        Start-Sleep -Milliseconds $PollMilliseconds
    } while($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    throw ('The new VHD did not appear in the bounded Storage enumeration wait: ' + $lastFailure)
}
function Assert-InstallerBoundaryLegacyFact([bool]$Condition,[string]$Message) {
    if(-not $Condition){throw [IO.InvalidDataException]::new($Message)}
}
function Wait-InstallerBoundaryLegacyVirtualDisk([string]$VhdPath,[string]$DriveLetter,
    [scriptblock]$ReadImage,[scriptblock]$ReadDrives,[scriptblock]$ReadPartitions,[scriptblock]$ReadLogicalDisks,
    [scriptblock]$ReadVolumes,[scriptblock]$ReadDeviceLength,[scriptblock]$ReadVolumeGuid,
    [int]$TimeoutMilliseconds=30000,[int]$PollMilliseconds=250) {
    Assert-InstallerBoundaryLegacyFact ($VhdPath -cmatch '^C:\\Users\\Public\\SteamWrapperInstallerBoundary-[a-f0-9]{32}\\failure\.vhd$' -and
        $DriveLetter -cmatch '^[R-Z]$' -and $TimeoutMilliseconds -gt 0 -and $TimeoutMilliseconds -le 30000 -and
        $PollMilliseconds -gt 0 -and $PollMilliseconds -le 1000) 'Only the bounded own guest image and drive may be probed.'
    $timer=[Diagnostics.Stopwatch]::StartNew();$attempts=0;$lastFailure='No complete Win32 disk association chain.'
    $readBinding={
        $frames=@(& $ReadImage $VhdPath);if($frames.Count -eq 0){return $null}
        Assert-InstallerBoundaryLegacyFact ($frames.Count -eq 1) 'The exact image query was ambiguous.'
        $frame=$frames[0];$image=$frame.image
        $expectedPath=$VhdPath;$nodes=@($frame.pathNodes)
        foreach($node in $nodes){
            Assert-InstallerBoundaryLegacyFact ($null -ne $expectedPath -and $node.FullName -ieq $expectedPath -and
                $node.IsContainer -is [bool] -and $node.IsContainer -eq ($expectedPath -ine $VhdPath) -and
                -not($node.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'The actual image file/ancestor path is incomplete, redirected or not regular.'
            $expectedPath=[IO.Path]::GetDirectoryName($expectedPath)
        }
        Assert-InstallerBoundaryLegacyFact ($nodes.Count -gt 1 -and $null -eq $expectedPath -and $image.ImagePath -ieq $VhdPath -and
            $image.Attached -is [bool] -and $image.Attached -and $image.Size -eq 512MB -and
            $image.DevicePath -imatch '^\\\\\.\\PHYSICALDRIVE(?<number>[1-9][0-9]{0,4})$') 'The exact mounted 512 MiB VHD did not identify a non-system physical device.'
        $number=[int]$Matches['number']
        Assert-InstallerBoundaryLegacyFact ($image.Number -eq $number) 'Image device path and actual image number differ.'
        $drives=@(& $ReadDrives $image);if($drives.Count -eq 0){return $null}
        Assert-InstallerBoundaryLegacyFact ($drives.Count -eq 1) 'The exact Win32 drive query was ambiguous.'
        $disk=$drives[0]
        Assert-InstallerBoundaryLegacyFact ($disk.DeviceID -ieq $image.DevicePath -and $disk.Index -eq $number -and
            $disk.Index -gt 0 -and $disk.Size -ge 500MB -and $disk.Size -le 512MB) 'Win32 drive identity or bounded geometry differs from the own VHD.'
        # Win32 Size is CHS geometry. Read the exact device length only after
        # the sealed image and unique non-system drive identity have matched.
        $lengths=@(& $ReadDeviceLength $image)
        Assert-InstallerBoundaryLegacyFact ($lengths.Count -eq 1 -and $lengths[0] -eq 512MB) 'The actual read-only device length is not exactly 512 MiB.'
        $partitions=@(& $ReadPartitions $disk);if($partitions.Count -eq 0){return $null}
        Assert-InstallerBoundaryLegacyFact ($partitions.Count -eq 1) 'The actual drive-to-partition association was ambiguous.'
        $partition=$partitions[0]
        Assert-InstallerBoundaryLegacyFact ($partition.DiskIndex -eq $number -and $partition.Index -ge 0 -and
            $partition.DeviceID -ceq ('Disk #'+$number+', Partition #'+$partition.Index) -and $partition.StartingOffset -ge 0 -and
            $partition.Size -ge 500MB -and $partition.Size -le 512MB -and
            [decimal]$partition.StartingOffset+[decimal]$partition.Size -le [decimal]$lengths[0]) 'The unique actual partition is outside the verified device.'
        $logicalDisks=@(& $ReadLogicalDisks $partition);if($logicalDisks.Count -eq 0){return $null}
        Assert-InstallerBoundaryLegacyFact ($logicalDisks.Count -eq 1) 'The actual partition-to-logical-disk association was ambiguous.'
        $logical=$logicalDisks[0]
        Assert-InstallerBoundaryLegacyFact ($logical.DeviceID -ceq ($DriveLetter+':') -and $logical.DriveType -eq 3 -and
            $logical.FileSystem -ieq 'NTFS' -and $logical.Size -ge 500MB -and $logical.Size -le $partition.Size -and
            $logical.FreeSpace -ge 0 -and $logical.FreeSpace -le $logical.Size) 'The actual associated logical disk is not the own bounded fixed NTFS volume.'
        $volumes=@(& $ReadVolumes $logical);if($volumes.Count -eq 0){return $null}
        Assert-InstallerBoundaryLegacyFact ($volumes.Count -eq 1) 'The exact Win32 volume query was ambiguous.'
        $volume=$volumes[0];$guids=@(& $ReadVolumeGuid $DriveLetter)
        Assert-InstallerBoundaryLegacyFact ($guids.Count -eq 1 -and $guids[0] -is [string] -and
            $guids[0] -imatch '^\\\\\?\\Volume\{[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\}\\$' -and
            $volume.DeviceID -ieq $guids[0] -and $volume.DriveLetter -ceq $logical.DeviceID -and
            $volume.FileSystem -ieq 'NTFS' -and $volume.Capacity -eq $logical.Size) 'Win32 volume identity/capacity does not match the actual mounted Volume GUID.'
        return [pscustomobject]@{provider='Win32';image=$image;disk=$disk;partition=$partition;logicalDisk=$logical;volume=$volume;deviceLength=$lengths[0];volumeGuid=$guids[0]}
    }
    do {
        $attempts++
        try {$binding=& $readBinding;if($null -ne $binding){$binding|Add-Member -NotePropertyName attempts -NotePropertyValue $attempts;return $binding}}
        catch {if($_.Exception.GetBaseException() -is [IO.InvalidDataException]){throw};$lastFailure=$_.Exception.GetBaseException().Message}
        if($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds){break};Start-Sleep -Milliseconds $PollMilliseconds
    } while($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    throw ('The bounded actual Win32 VHD association wait failed: '+$lastFailure)
}
function Get-InstallerBoundaryDiskReaderSource {
    return @'
using System;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;
public static class SteamWrapperBoundaryDiskReader {
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]
    static extern bool DeviceIoControl(SafeFileHandle handle,uint code,IntPtr input,uint inputBytes,out long length,uint outputBytes,out uint returned,IntPtr overlapped);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern bool GetVolumeNameForVolumeMountPointW(string mount,StringBuilder name,uint characters);
    static void RequireGuest() {
        if(!Environment.UserName.Equals("WDAGUtilityAccount",StringComparison.OrdinalIgnoreCase) ||
            !Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).Equals(@"C:\Users\WDAGUtilityAccount",StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Read-only virtual-device probes are refused outside the guest.");
    }
    public static long ReadLength(string imagePath,string devicePath,int number) {
        RequireGuest();
        if(!Regex.IsMatch(imagePath,@"^C:\\Users\\Public\\SteamWrapperInstallerBoundary-[a-f0-9]{32}\\failure\.vhd$") || number<=0 ||
            !string.Equals(devicePath,@"\\.\PHYSICALDRIVE"+number.ToString(CultureInfo.InvariantCulture),StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Only an already bound non-system own VHD device may be read.");
        // GENERIC_READ only; never request write access or enable privileges.
        using(SafeFileHandle handle=CreateFileW(devicePath,0x80000000,3,IntPtr.Zero,3,0,IntPtr.Zero)) {
            if(handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(),"Opening the bound VHD for read-only length failed.");
            long length;uint returned;
            if(!DeviceIoControl(handle,0x7405c,IntPtr.Zero,0,out length,8,out returned,IntPtr.Zero) || returned!=8)
                throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only IOCTL_DISK_GET_LENGTH_INFO failed.");
            return length;
        }
    }
    public static string ReadVolumeGuid(string letter) {
        RequireGuest();
        if(!Regex.IsMatch(letter,"^[R-Z]$")) throw new InvalidOperationException("Only the bound guest drive letter may be queried.");
        StringBuilder name=new StringBuilder(128);
        if(!GetVolumeNameForVolumeMountPointW(letter+@":\",name,128))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Reading the actual own mount-point Volume GUID failed.");
        return name.ToString();
    }
}
'@
}
function Assert-InstallerBoundaryDiskFullResult($Facts) {
    foreach ($name in @('hostDigestVerified','newVirtualDiskVerified','journalWritten','stagingCopyObserved','stagingIncomplete','currentInstallationUnchanged','repairSucceeded','dataUnchanged')) {
        Assert-InstallerBoundary ($Facts.$name -is [bool] -and $Facts.$name) ('Disk-full evidence did not establish ' + $name + '.')
    }
    Assert-InstallerBoundary ($Facts.hostExitCode -eq 11 -and $Facts.freeBytesAtFailure -ge 0 -and $Facts.freeBytesAtFailure -le 4096) 'A successful copy, space preflight refusal or non-exhausted volume is not a mid-copy disk-full pass.'
}
function Assert-InstallerBoundaryDiskFullCompletion($Facts) {
    Assert-InstallerBoundaryDiskFullResult $Facts
    Assert-InstallerBoundary ($Facts.result -ceq 'passed' -and $Facts.productRecoveryPassed -is [bool] -and $Facts.productRecoveryPassed -and
        $Facts.cleanup.status -ceq 'passed' -and $Facts.cleanup.detached -is [bool] -and $Facts.cleanup.detached) 'Copy/recovery success with an unresolved live process or normal-volume cleanup failure is not a complete acceptance pass.'
}
function Assert-InstallerBoundaryAssetPath([string]$Relative) {
    Assert-InstallerBoundary ($Relative.Length -ge 3 -and $Relative.Length -le 240 -and $Relative -cmatch '^(baseline|target)/' -and
        $Relative -notmatch '[\\:\x00-\x1f]') 'Only a bounded relative baseline/target payload asset is allowed.'
    foreach ($part in $Relative.Split('/')) {
        Assert-InstallerBoundary ($part -notin @('','.','..') -and $part -notmatch '[. ]$' -and
            $part -notmatch '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -and $part -notmatch '^(?i:\.env(?:\..*)?|\.git|profiles\.toml|ui-settings\.json(?:\..*)?|logs|backups|cache)$') 'Acceptance payload paths cannot redirect, expose private data or name Windows devices.'
    }
}
function Get-InstallerBoundaryDiskFillerSource {
    return @'
using System;
using System.IO;
using System.Threading;
using System.Text.RegularExpressions;
public sealed class SteamWrapperBoundaryDiskFiller {
    readonly string program, filler, volume;
    Thread thread;
    volatile bool stop;
    public bool JournalSeen, CopySeen, Exhausted;
    public long FreeBytes = -1, WitnessBytes;
    public string WitnessPath = "", Failure = "";
    public SteamWrapperBoundaryDiskFiller(string programRoot) {
        if (!Regex.IsMatch(programRoot, @"^[R-Z]:\\SteamWrapperInstallerBoundary-[a-f0-9]{32}\\program$"))
            throw new ArgumentException("Only the exact guest virtual-volume fixture is accepted.");
        program = programRoot; volume = programRoot.Substring(0,3);
        filler = Path.Combine(Path.GetDirectoryName(programRoot), "own-space-filler.bin");
    }
    public void Start() {
        if (!Environment.UserName.Equals("WDAGUtilityAccount", StringComparison.OrdinalIgnoreCase) ||
            !Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).Equals(@"C:\Users\WDAGUtilityAccount", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Disk filler is refused outside the Windows Sandbox guest.");
        if (thread != null) throw new InvalidOperationException("The filler can start only once.");
        thread = new Thread(Run); thread.IsBackground = true; thread.Start();
    }
    void Run() {
        try {
            var deadline = DateTime.UtcNow.AddSeconds(120);
            var journal = Path.Combine(program, "installation-journal.json");
            while (!stop && DateTime.UtcNow < deadline) {
                if (File.Exists(journal)) {
                    JournalSeen = true;
                    foreach (var stage in Directory.GetDirectories(program, ".staging-*"))
                        foreach (var path in Directory.GetFiles(stage, "*", SearchOption.AllDirectories)) {
                            if (Path.GetFileName(path).Equals("deployment-manifest.json", StringComparison.OrdinalIgnoreCase)) continue;
                            var length = new FileInfo(path).Length;
                            if (length > 0) { CopySeen = true; WitnessPath = path; WitnessBytes = length; break; }
                        }
                    if (CopySeen) break;
                }
                Thread.Sleep(1);
            }
            if (stop || !CopySeen) return;
            using (var file = new FileStream(filler, FileMode.CreateNew, FileAccess.Write, FileShare.Read)) {
                for (int attempt = 0; !stop && attempt < 128; attempt++) {
                    long free = new DriveInfo(volume).AvailableFreeSpace;
                    if (free <= 4096) { FreeBytes = free; Exhausted = true; break; }
                    long length = file.Length, extend = Math.Max(4096, free - 4096);
                    try { file.SetLength(checked(length + extend)); file.Position = file.Length - 1; file.WriteByte(0); file.Flush(true); }
                    catch (IOException) {
                        free = new DriveInfo(volume).AvailableFreeSpace;
                        if (free <= 4096) { FreeBytes = free; Exhausted = true; break; }
                        long smaller = Math.Max(4096, free / 2);
                        try { file.SetLength(checked(file.Length + smaller)); file.Position = file.Length - 1; file.WriteByte(0); file.Flush(true); }
                        catch (IOException) { }
                    }
                }
                FreeBytes = new DriveInfo(volume).AvailableFreeSpace;
                Exhausted = FreeBytes <= 4096;
            }
        } catch (Exception error) { Failure = error.GetType().Name + ": " + error.Message; }
    }
    public void Stop() { stop = true; if (thread != null && !thread.Join(10000)) throw new TimeoutException("The owned filler did not stop; no process was killed."); }
}
'@
}
function Get-InstallerBoundaryRegistryFaultSource {
    return @'
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Threading;
using System.Runtime.InteropServices;
public sealed class SteamWrapperBoundaryRegistryFault {
    readonly string state, key;
    readonly byte[] descriptor;
    Thread thread;
    volatile bool stop;
    public bool StateSeen, Applied;
    public string Failure = "";
    public SteamWrapperBoundaryRegistryFault(string programRoot, string subKey, byte[] securityDescriptor) {
        string root = Path.GetDirectoryName(Path.GetFullPath(programRoot));
        if (Path.GetFileName(programRoot) != "program" || !Regex.IsMatch(Path.GetFileName(root), @"^installer-options-ui-[a-f0-9]{32}$") ||
            root.IndexOf(Path.Combine("target", "winui") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) < 0)
            throw new ArgumentException("Only the exact isolated installer fixture is accepted.");
        string id;
        using (SHA256 sha = SHA256.Create()) {
            byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(programRoot).ToUpperInvariant()));
            id = BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant().Substring(0,16);
        }
        string expected = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamWrapper-Installer-Test-" + id + "_is1";
        if (subKey != expected || securityDescriptor == null || securityDescriptor.Length < 20 || securityDescriptor.Length > 65536)
            throw new ArgumentException("Only this fresh isolated AppId descriptor may be changed.");
        state = Path.Combine(programRoot, "installation.json"); key = subKey; descriptor = (byte[])securityDescriptor.Clone();
    }
    public void Start() {
        if (thread != null || File.Exists(state)) throw new InvalidOperationException("Start once before the actual first activation.");
        thread = new Thread(Run); thread.IsBackground = true; thread.Start();
    }
    public void SetOwnDescriptor(byte[] value) {
        if (value == null || value.Length < 20 || value.Length > 65536) throw new ArgumentException("The own descriptor exceeds its bound.");
        IntPtr handle = IntPtr.Zero;
        try {
            int error = RegOpenKeyEx(new IntPtr(unchecked((int)0x80000001)), key, 0, 0x60000 | 0x100, out handle);
            if (error != 0) throw new IOException("The own isolated HKCU descriptor handle was unavailable: " + error);
            error = RegSetKeySecurity(handle, 4, value);
            if (error != 0) throw new IOException("The own isolated DACL operation failed: " + error);
        } finally { if (handle != IntPtr.Zero) RegCloseKey(handle); }
    }
    void Run() {
        try {
            var deadline = DateTime.UtcNow.AddSeconds(120);
            while (!stop && DateTime.UtcNow < deadline && !File.Exists(state)) Thread.Sleep(1);
            if (stop || !File.Exists(state)) return;
            StateSeen = true;
            SetOwnDescriptor(descriptor);
            Applied = true;
        } catch (Exception error) { Failure = error.GetType().Name + ": " + error.Message; }
    }
    public void Stop() { stop = true; if (thread != null && !thread.Join(10000)) throw new TimeoutException("The own registry watcher did not stop; no process was killed."); }
    [DllImport("advapi32.dll", EntryPoint="RegOpenKeyExW", CharSet=CharSet.Unicode)] static extern int RegOpenKeyEx(IntPtr root,string subKey,uint options,uint access,out IntPtr key);
    [DllImport("advapi32.dll")] static extern int RegSetKeySecurity(IntPtr key,uint information,byte[] descriptor);
    [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr key);
}
'@
}
