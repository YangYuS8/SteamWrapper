[CmdletBinding()]
param(
    [ValidateRange(5, 30)][int]$Repetitions = 6,
    [ValidateRange(1, 30)][int]$SettleSeconds = 5,
    [int]$Seed = 20260907,
    [switch]$StaticOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This comparison requires Windows.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$winuiRoot = Join-Path $repoRoot 'target/winui/publish'
$dioxusRoot = Join-Path $repoRoot 'target/dx/SteamWrapperManager/release/windows/app'
$runner = Join-Path $winuiRoot 'Runner/SteamWrapperRunner.exe'
foreach ($path in @((Join-Path $winuiRoot 'SteamWrapper.Manager.exe'), (Join-Path $dioxusRoot 'SteamWrapperManager.exe'), $runner)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Build both release applications first; missing $path" }
}

$resultRoot = Join-Path $repoRoot ('target/manager-comparison/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resultRoot | Out-Null

function Get-Footprint([string]$Name, [string]$Directory) {
    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse)
    [pscustomobject]@{
        Name = $Name
        Directory = $Directory
        FileCount = $files.Count
        Bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
        Files = @($files | ForEach-Object {
            [pscustomobject]@{ Path = [IO.Path]::GetRelativePath($Directory, $_.FullName); Bytes = $_.Length }
        })
    }
}

# dx build's app folder does not stage bundle resources. Prepare a complete isolated
# launch layout without changing release artifacts or adding the E2E driver.
$dioxusStage = Join-Path $resultRoot 'dioxus-app'
New-Item -ItemType Directory -Path $dioxusStage | Out-Null
Get-ChildItem -LiteralPath $dioxusRoot | Copy-Item -Destination $dioxusStage -Recurse
Copy-Item -LiteralPath $runner -Destination (Join-Path $dioxusStage 'SteamWrapperRunner.exe')
$footprints = @(
    (Get-Footprint 'WinUI self-contained publish' $winuiRoot),
    (Get-Footprint 'Dioxus raw dx build (Runner absent)' $dioxusRoot),
    (Get-Footprint 'Dioxus staged app including same Runner' $dioxusStage)
)
$footprints | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resultRoot 'footprints.json') -Encoding utf8NoBOM
Write-Output "Comparison evidence: $resultRoot"
$footprints | Select-Object Name, FileCount, Bytes | Format-Table | Out-String | Write-Output
if ($StaticOnly) { return }

# Identical configuration, games and local covers. Separate processes use the SAME
# stable data directory; neither home screen scans a real library. No game is run.
$fixture = Join-Path $resultRoot 'fixture'
$steam = Join-Path $fixture 'Steam'
$localData = Join-Path $fixture 'local-app-data'
$data = Join-Path $localData 'SteamWrapper'
$webviewData = Join-Path $fixture 'webview2'
$coverRoot = Join-Path $steam 'appcache/librarycache'
foreach ($directory in @($data, (Join-Path $data 'bin'), $coverRoot, (Join-Path $fixture 'xdg-data'), $webviewData)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
Copy-Item -LiteralPath $runner -Destination (Join-Path $data 'bin/SteamWrapperRunner.exe')
Copy-Item -LiteralPath (Join-Path $winuiRoot 'Runner/runner-manifest.json') -Destination (Join-Path $data 'bin/runner-manifest.json')
$profiles = [Text.StringBuilder]::new("version = 2`n")
$pixel = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2kAAAAASUVORK5CYII=')
for ($index = 0; $index -lt 10; $index++) {
    $appId = 480 + $index
    $gameName = "比较示例 $index"
    $game = Join-Path $steam "steamapps/common/$gameName"
    New-Item -ItemType Directory -Path $game -Force | Out-Null
    $manifest = "`"AppState`"`n{`n    `"appid`" `"$appId`"`n    `"name`" `"$gameName`"`n    `"installdir`" `"$gameName`"`n}`n"
    [IO.File]::WriteAllText((Join-Path $steam "steamapps/appmanifest_$appId.acf"), $manifest)
    [IO.File]::WriteAllBytes((Join-Path $coverRoot "$($appId)_library_600x900.png"), $pixel)
    # The fixture target exists but is never launched by the benchmark.
    Copy-Item -LiteralPath $runner -Destination (Join-Path $game 'fixture.exe')
    [void]$profiles.Append("`n[profiles.'$appId']`nname = '$gameName'`napp_id = '$appId'`nplatform = 'windows'`ngame_dir = '$game'`ntarget = 'fixture.exe'`nargs = []`nwait_mode = 'job'`n")
}
$profilePath = Join-Path $data 'profiles.toml'
[IO.File]::WriteAllText($profilePath, $profiles.ToString())
$profileHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash

# Toolhelp snapshots find only descendants of our new Manager process. This avoids
# charging unrelated Edge/Codex/WebView2 processes to Dioxus, or closing them.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ManagerComparisonProcesses {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Entry {
        public uint Size, Usage, ProcessId;
        public UIntPtr DefaultHeap;
        public uint ModuleId, Threads, ParentId;
        public int Priority;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string Exe;
    }
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint id);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern bool Process32FirstW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern bool Process32NextW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    public static int[] Descendants(int root) {
        var snapshot = CreateToolhelp32Snapshot(2, 0);
        if (snapshot == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception();
        try {
            var parents = new Dictionary<int,int>();
            var entry = new Entry { Size = (uint)Marshal.SizeOf<Entry>() };
            if (Process32FirstW(snapshot, ref entry)) {
                do { parents[(int)entry.ProcessId] = (int)entry.ParentId; } while (Process32NextW(snapshot, ref entry));
            }
            var ids = new HashSet<int> { root };
            bool changed;
            do { changed = false; foreach (var pair in parents) if (ids.Contains(pair.Value)) changed |= ids.Add(pair.Key); } while(changed);
            var result = new int[ids.Count]; ids.CopyTo(result); return result;
        } finally { CloseHandle(snapshot); }
    }
}
'@

function Get-TreeSample([Diagnostics.Process]$Manager, [hashtable]$Owned) {
    $items = @(foreach ($processId in [ManagerComparisonProcesses]::Descendants($Manager.Id)) {
        try {
            $process = [Diagnostics.Process]::GetProcessById($processId)
            $process.Refresh()
            $started = $process.StartTime.ToUniversalTime().Ticks
            if ($started -lt $Manager.StartTime.ToUniversalTime().Ticks) { continue }
            $Owned[$processId] = $started
            [pscustomobject]@{
                ProcessId = $processId; Name = $process.ProcessName
                PrivateBytes = $process.PrivateMemorySize64; WorkingSetBytes = $process.WorkingSet64
                CpuMilliseconds = $process.TotalProcessorTime.TotalMilliseconds
                Executable = $process.MainModule.FileName
            }
        } catch [ArgumentException] { } catch [InvalidOperationException] { }
    })
    [pscustomobject]@{
        AtUtc = [DateTime]::UtcNow.ToString('o')
        ProcessCount = $items.Count
        PrivateBytes = [long](($items | Measure-Object -Property PrivateBytes -Sum).Sum)
        SummedWorkingSetBytes = [long](($items | Measure-Object -Property WorkingSetBytes -Sum).Sum)
        Processes = $items
    }
}

function Stop-Owned([Diagnostics.Process]$Manager, [hashtable]$Owned) {
    if (-not $Manager.HasExited) {
        $null = Get-TreeSample $Manager $Owned
        [void]$Manager.CloseMainWindow()
        if (-not $Manager.WaitForExit(4000)) { $Manager.Kill($true); $Manager.WaitForExit() }
    }
    foreach ($entry in $Owned.GetEnumerator()) {
        try {
            $process = [Diagnostics.Process]::GetProcessById([int]$entry.Key)
            if ($process.StartTime.ToUniversalTime().Ticks -eq $entry.Value -and -not $process.HasExited) {
                $process.Kill(); [void]$process.WaitForExit(4000)
            }
        } catch [ArgumentException] { } catch [InvalidOperationException] { }
    }
    $Manager.Dispose()
}

$executables = @{
    WinUI = Join-Path $winuiRoot 'SteamWrapper.Manager.exe'
    Dioxus = Join-Path $dioxusStage 'SteamWrapperManager.exe'
}
$runs = [Collections.Generic.List[object]]::new()
function Measure-One([string]$App, [bool]$Warmup, [int]$Pair) {
    $start = [Diagnostics.ProcessStartInfo]::new($executables[$App])
    $start.UseShellExecute = $false
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($executables[$App])
    $start.Environment['STEAM_DIR'] = $steam
    $start.Environment['LOCALAPPDATA'] = $localData
    $start.Environment['XDG_DATA_HOME'] = Join-Path $fixture 'xdg-data'
    $start.Environment['STEAMWRAPPER_E2E_ROOT'] = $fixture
    $start.Environment['WEBVIEW2_USER_DATA_FOLDER'] = $webviewData
    $start.Environment.Remove('STEAMWRAPPER_BUNDLED_RESOURCE_ROOT') | Out-Null
    $owned = @{}
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($start)
    try {
        do {
            $process.Refresh()
            if ($process.HasExited) { throw "$App exited before a window appeared (exit $($process.ExitCode))." }
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) { break }
            Start-Sleep -Milliseconds 10
        } while ($watch.Elapsed.TotalSeconds -lt 30)
        $windowMilliseconds = $watch.Elapsed.TotalMilliseconds
        if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw "$App had no main window within 30 seconds." }
        Start-Sleep -Seconds $SettleSeconds
        $samples = @(for ($sample = 0; $sample -lt 3; $sample++) {
            if ($sample -ne 0) { Start-Sleep -Milliseconds 1000 }
            if ($process.HasExited) { throw "$App exited before idle sampling." }
            Get-TreeSample $process $owned
        })
        $result = [pscustomobject]@{
            App = $App; Warmup = $Warmup; Pair = $Pair; Sequence = $runs.Count
            WindowMilliseconds = [Math]::Round($windowMilliseconds, 2)
            PrivateBytes = [long](($samples | Measure-Object -Property PrivateBytes -Average).Average)
            SummedWorkingSetBytes = [long](($samples | Measure-Object -Property SummedWorkingSetBytes -Average).Average)
            ProcessCount = $samples[-1].ProcessCount
            Samples = $samples
        }
        $runs.Add($result)
        $runs | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resultRoot 'runs.json') -Encoding utf8NoBOM
        Write-Output ("{0} pair={1} warmup={2}: window={3:N0} ms, private={4:N1} MiB, processes={5}" -f $App, $Pair, $Warmup, $windowMilliseconds, ($result.PrivateBytes / 1MB), $result.ProcessCount)
    } finally { Stop-Owned $process $owned }
    if ((Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash -ne $profileHash) {
        throw 'A benchmark changed the fixture profiles; results are invalid.'
    }
    Start-Sleep -Milliseconds 600
}

$random = [Random]::new($Seed)
# Warm each app/profile once; then alternate apps within balanced random-order pairs.
$warmupOrder = if ($random.Next(2) -eq 0) { @('WinUI', 'Dioxus') } else { @('Dioxus', 'WinUI') }
foreach ($app in $warmupOrder) { Measure-One $app $true 0 }
$firstApps = @(@(for ($i = 0; $i -lt $Repetitions; $i++) { if ($i % 2 -eq 0) { 'WinUI' } else { 'Dioxus' } }) | Sort-Object { $random.Next() })
for ($pair = 1; $pair -le $Repetitions; $pair++) {
    $first = $firstApps[$pair - 1]
    Measure-One $first $false $pair
    Measure-One $(if ($first -eq 'WinUI') { 'Dioxus' } else { 'WinUI' }) $false $pair
}

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}
$summary = @(foreach ($app in @('WinUI', 'Dioxus')) {
    $measured = @($runs | Where-Object { $_.App -eq $app -and -not $_.Warmup })
    [pscustomobject]@{
        App = $app; Samples = $measured.Count
        WindowMillisecondsMedian = Get-Median @($measured.WindowMilliseconds)
        WindowMillisecondsMin = ($measured.WindowMilliseconds | Measure-Object -Minimum).Minimum
        WindowMillisecondsMax = ($measured.WindowMilliseconds | Measure-Object -Maximum).Maximum
        PrivateMiBMedian = (Get-Median @($measured.PrivateBytes)) / 1MB
        SummedWorkingSetMiBMedian = (Get-Median @($measured.SummedWorkingSetBytes)) / 1MB
        ProcessCountMedian = Get-Median @($measured.ProcessCount)
    }
})
$report = [pscustomobject]@{
    Completed = $true; AtUtc = [DateTime]::UtcNow.ToString('o'); Seed = $Seed
    OS = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    ProcessorCount = [Environment]::ProcessorCount; PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Repetitions = $Repetitions; SettleSeconds = $SettleSeconds; Profiles = 10
    Executables = @($executables.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ App = $_.Key; Path = $_.Value; Sha256 = (Get-FileHash -LiteralPath $_.Value -Algorithm SHA256).Hash }
    })
    Summary = $summary
    Limitations = @(
        'Same local machine, warm filesystem and WebView2 profile; not cold-start or clean-VM evidence.',
        'Time to Process.MainWindowHandle is only window creation, not first frame or usable UI. Poll interval is 10 ms.',
        'Default home screens and window dimensions differ. This measures the present products, not equivalent framework implementations.',
        'Private bytes sums private process allocations, not resident physical memory. Summed working sets can count shared pages repeatedly.',
        'Dioxus includes its child WebView2 processes but its disk footprint excludes the installed shared WebView2 runtime. WinUI includes .NET and Windows App SDK.',
        'Idle samples are taken at 5/6/7 seconds after window detection by default; background OS activity can affect these local measurements.',
        'No Steam launch, gameplay, cold cache flush, forced garbage collection or UI interaction is performed.'
    )
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resultRoot 'summary.json') -Encoding utf8NoBOM

# Collect machine and build provenance after sampling, so CIM/file inspection does
# not compete with the applications during timing or memory measurements.
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = @(Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors)
$runtimePaths = @($runs | ForEach-Object { $_.Samples } | ForEach-Object { $_.Processes } |
    Where-Object { $_.Name -eq 'msedgewebview2' } | Select-Object -ExpandProperty Executable -Unique)
$metadata = [pscustomobject]@{
    OS = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    OSCaption = (Get-CimInstance Win32_OperatingSystem).Caption
    CPU = $cpu
    PhysicalMemoryBytes = [long]$computer.TotalPhysicalMemory
    PhysicalMemoryGiB = $computer.TotalPhysicalMemory / 1GB
    CheckoutRevisionAtMeasurement = (& git -C $repoRoot rev-parse HEAD)
    CheckoutBranchAtMeasurement = (& git -C $repoRoot branch --show-current)
    BuildProvenance = 'Existing previously built release artifacts; this script does not rebuild. Checkout revision is context, not proof that dirty source matches each binary.'
    Executables = @($executables.GetEnumerator() | ForEach-Object {
        $bytes = [IO.File]::ReadAllBytes($_.Value)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        [pscustomobject]@{
            App = $_.Key; Path = $_.Value
            Sha256 = (Get-FileHash -LiteralPath $_.Value -Algorithm SHA256).Hash
            LastWriteTimeUtc = (Get-Item -LiteralPath $_.Value).LastWriteTimeUtc.ToString('o')
            PeSubsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
        }
    })
    WinUIProductAssemblies = @('SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll', 'Runner/SteamWrapperRunner.exe') | ForEach-Object {
        $artifact = Join-Path $winuiRoot $_
        [pscustomobject]@{ Path = $artifact; Sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash }
    }
    WebView2 = @($runtimePaths | ForEach-Object {
        [pscustomobject]@{ Path = $_; ProductVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($_).ProductVersion }
    })
    PeSubsystemMeaning = '2 = Windows GUI; both observed Manager binaries use GUI subsystem, not console.'
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resultRoot 'metadata.json') -Encoding utf8NoBOM
$summary | Format-Table | Out-String | Write-Output
Write-Output "Completed: $(Join-Path $resultRoot 'summary.json')"
