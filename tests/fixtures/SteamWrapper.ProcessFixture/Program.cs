using System.Diagnostics;
using System.Text.Json;

var reportDirectory = Environment.GetEnvironmentVariable("STEAMWRAPPER_FIXTURE_DIR")
    ?? throw new InvalidOperationException("This fixture requires an isolated report directory.");
Directory.CreateDirectory(reportDirectory);
if (args.Length > 0 && args[0] == "--child")
{
    await File.WriteAllTextAsync(Path.Combine(reportDirectory, "child-started"), Environment.ProcessId.ToString());
    var timer = Stopwatch.StartNew();
    while (!File.Exists(Path.Combine(reportDirectory, "release-child")))
    {
        if (timer.Elapsed > TimeSpan.FromSeconds(30)) return 50;
        await Task.Delay(20);
    }
    await File.WriteAllTextAsync(Path.Combine(reportDirectory, "child-completed"), "done");
    return 0;
}
if (args.Length == 0 || args[0] != "--parent") return 51;
var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
start.ArgumentList.Add("--child");
using var child = Process.Start(start) ?? throw new InvalidOperationException("Child did not start.");
var report = JsonSerializer.Serialize(new
{
    Arguments = args,
    WorkingDirectory = Environment.CurrentDirectory,
    ProcessId = Environment.ProcessId,
    ChildProcessId = child.Id
});
await File.WriteAllTextAsync(Path.Combine(reportDirectory, "parent.json"), report);
return 7;
