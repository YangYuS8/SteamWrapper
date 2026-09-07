using System.Diagnostics;
using System.Text.Json;
using SteamWrapper.Application.Profiles;

if (args.Length != 4)
    throw new ArgumentException("Expected: fixture TOML, output directory, Runner EXE, process fixture publish directory.");
if (!OperatingSystem.IsWindows())
    throw new PlatformNotSupportedException("The process contract requires Windows Job Objects.");

var fixturePath = Path.GetFullPath(args[0]);
var output = Path.GetFullPath(args[1]);
var runnerSource = Path.GetFullPath(args[2]);
var processSource = Path.GetFullPath(args[3]);
Directory.CreateDirectory(output);

var roundTripPath = Path.Combine(output, "roundtrip.toml");
File.Copy(fixturePath, roundTripPath, overwrite: false);
var store = new ProfileStore(roundTripPath);
var snapshot = await store.LoadAsync();
Require(snapshot.Profiles.Count == 6, "C# did not load all historical profiles.");
var alias = snapshot.Profiles.Single(profile => profile.Key == "translated-game");
Require(alias.AppId == "480", "The aliased AppID changed.");
Require(snapshot.Profiles.Single(profile => profile.Key == "legacy").WaitMode == "root", "Legacy missing wait_mode must mean root.");
await store.SaveAsync(snapshot, alias with { Target = @"patch update\汉化.exe" });

var localAppData = Path.Combine(output, "local-appdata");
var steamRoot = Path.Combine(output, "Steam fixture");
var dataRoot = Path.Combine(localAppData, "SteamWrapper");
var runnerPath = Path.Combine(dataRoot, "bin", "SteamWrapperRunner.exe");
Directory.CreateDirectory(Path.GetDirectoryName(runnerPath)!);
Directory.CreateDirectory(steamRoot);
File.Copy(runnerSource, runnerPath);
var gameDirectory = Path.Combine(output, "游戏 Library");
var targetDirectory = Path.Combine(gameDirectory, "程序 files");
var workingDirectory = Path.Combine(gameDirectory, "工作 directory");
Directory.CreateDirectory(targetDirectory);
Directory.CreateDirectory(workingDirectory);
foreach (var file in Directory.EnumerateFiles(processSource))
    File.Copy(file, Path.Combine(targetDirectory, Path.GetFileName(file)));

var runtimeStore = new ProfileStore(Path.Combine(dataRoot, "profiles.toml"));
var newProfile = new ProfileData(
    "900001", "汉化启动器 · 契约测试", "900001", "windows", gameDirectory,
    @"程序 files\SteamWrapper.ProcessFixture.exe", "工作 directory",
    ["--parent", "中文 with spaces", "embedded\"quote", "trailing\\", ""], "job", null);
var runtimeSnapshot = await runtimeStore.SaveAsync(await runtimeStore.LoadAsync(), newProfile, isNew: true);
File.Copy(Path.Combine(dataRoot, "profiles.toml"), Path.Combine(output, "new-windows.toml"));

await VerifyLifetimeAsync("900001", expectJobWait: true);
runtimeSnapshot = await runtimeStore.SaveAsync(runtimeSnapshot,
    newProfile with { Key = "900002", AppId = "900002", Target = "missing-target.exe" }, isNew: true);
using (var failedRunner = StartRunner("900002", Path.Combine(output, "missing-target")))
{
    await WaitForExitAsync(failedRunner, TimeSpan.FromSeconds(15));
    Require(failedRunner.ExitCode == 1, $"Missing target exit code: {failedRunner.ExitCode}");
    var log = await File.ReadAllTextAsync(Path.Combine(dataRoot, "logs", "runner-900002.log"));
    Require(log.Contains("ERROR:", StringComparison.Ordinal), "Missing target must produce a runtime error log.");
}
await runtimeStore.SaveAsync(runtimeSnapshot,
    newProfile with { Key = "900003", AppId = "900003", WaitMode = "root" }, isNew: true);
await VerifyLifetimeAsync("900003", expectJobWait: false);
Console.WriteLine("PASS: C# historical single-field edit; Rust Runner exact argv/cwd; Job descendant wait; root-only wait; missing-target exit/log.");

async Task VerifyLifetimeAsync(string appId, bool expectJobWait)
{
    var reportDirectory = Path.Combine(output, $"process-{appId}");
    Directory.CreateDirectory(reportDirectory);
    using var runner = StartRunner(appId, reportDirectory);
    try
    {
        var reportPath = Path.Combine(reportDirectory, "parent.json");
        await WaitUntilAsync(() => File.Exists(reportPath), TimeSpan.FromSeconds(15), "Target did not record argv/cwd.");
        ProcessReport? report = null;
        await WaitUntilAsync(() =>
        {
            try { report = JsonSerializer.Deserialize<ProcessReport>(File.ReadAllText(reportPath)); return report is not null; }
            catch (IOException) { return false; }
            catch (JsonException) { return false; }
        }, TimeSpan.FromSeconds(5), "Target report was incomplete.");
        Require(report!.Arguments.SequenceEqual(newProfile.Arguments), "Runner changed argv or appended Steam's original command.");
        Require(string.Equals(report.WorkingDirectory, workingDirectory, StringComparison.OrdinalIgnoreCase), "Runner changed cwd.");
        await WaitUntilAsync(() => File.Exists(Path.Combine(reportDirectory, "child-started")), TimeSpan.FromSeconds(15), "Descendant did not start.");
        await WaitUntilAsync(() => HasExited(report.ProcessId), TimeSpan.FromSeconds(15), "Launcher did not exit while descendant waited.");
        if (expectJobWait)
        {
            Require(!runner.HasExited, "Job-mode Runner exited before its controlled descendant was released.");
            // WaitForExitAsync also proves it remains alive after the direct process
            // has exited. The child uses a file gate, not a guessed sleep duration.
            using var stillWaiting = new CancellationTokenSource(TimeSpan.FromMilliseconds(250));
            try { await runner.WaitForExitAsync(stillWaiting.Token); throw new InvalidOperationException("Job-mode Runner stopped while child was gated."); }
            catch (OperationCanceledException) when (stillWaiting.IsCancellationRequested) { }
        }
        else
        {
            await WaitForExitAsync(runner, TimeSpan.FromSeconds(15));
            Require(!File.Exists(Path.Combine(reportDirectory, "child-completed")), "Root-mode fixture finished before the wait distinction could be observed.");
        }
        await File.WriteAllTextAsync(Path.Combine(reportDirectory, "release-child"), "release");
        await WaitForExitAsync(runner, TimeSpan.FromSeconds(15));
        await WaitUntilAsync(() => File.Exists(Path.Combine(reportDirectory, "child-completed")), TimeSpan.FromSeconds(15), "Child did not finish after release.");
        Require(runner.ExitCode == 7, $"Runner must preserve the launcher's exit code, received {runner.ExitCode}.");
        var log = await File.ReadAllTextAsync(Path.Combine(dataRoot, "logs", $"runner-{appId}.log"));
        Require(log.Contains("Profile exited with code: 7", StringComparison.Ordinal), "Successful runtime result was not logged.");
    }
    finally
    {
        await File.WriteAllTextAsync(Path.Combine(reportDirectory, "release-child"), "release after test");
        if (!runner.HasExited)
        {
            try { await WaitForExitAsync(runner, TimeSpan.FromSeconds(5)); }
            catch (TimeoutException) { runner.Kill(entireProcessTree: true); await runner.WaitForExitAsync(); }
        }
    }
}

Process StartRunner(string appId, string reportDirectory)
{
    var start = new ProcessStartInfo(runnerPath) { UseShellExecute = false, CreateNoWindow = true };
    start.ArgumentList.Add("--appid");
    start.ArgumentList.Add(appId);
    start.ArgumentList.Add("--");
    start.ArgumentList.Add("steam-original-must-not-be-forwarded.exe");
    start.ArgumentList.Add("original steam argument");
    start.Environment["LOCALAPPDATA"] = localAppData;
    start.Environment["STEAM_DIR"] = steamRoot;
    start.Environment["STEAMWRAPPER_E2E_ROOT"] = output;
    start.Environment["XDG_DATA_HOME"] = Path.Combine(output, "xdg-data");
    start.Environment["STEAMWRAPPER_FIXTURE_DIR"] = reportDirectory;
    return Process.Start(start) ?? throw new InvalidOperationException("Runner did not start.");
}

static bool HasExited(int processId)
{
    try { using var process = Process.GetProcessById(processId); return process.HasExited; }
    catch (ArgumentException) { return true; }
}

static async Task WaitForExitAsync(Process process, TimeSpan timeout)
{
    using var cancellation = new CancellationTokenSource(timeout);
    try { await process.WaitForExitAsync(cancellation.Token); }
    catch (OperationCanceledException) { throw new TimeoutException($"Process {process.Id} did not exit within {timeout}."); }
}

static async Task WaitUntilAsync(Func<bool> condition, TimeSpan timeout, string failure)
{
    var stopwatch = Stopwatch.StartNew();
    while (!condition())
    {
        if (stopwatch.Elapsed >= timeout) throw new TimeoutException(failure);
        await Task.Delay(25);
    }
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

internal sealed record ProcessReport(string[] Arguments, string WorkingDirectory, int ProcessId, int ChildProcessId);
