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
