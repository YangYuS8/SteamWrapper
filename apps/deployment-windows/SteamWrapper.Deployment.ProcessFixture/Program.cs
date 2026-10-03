using SteamWrapper.Deployment;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

if (args.Length > 0 && args[0] is "stop-install" or "stop-repair")
{
    var install = args[0] == "stop-install";
    if (args.Length != (install ? 5 : 4) || Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST") != "1") return 2;
    var root = Path.GetFullPath(args[1]);
    var fixture = Path.GetDirectoryName(root)!;
    if (Path.GetFileName(root) != "program" ||
        !Regex.IsMatch(Path.GetFileName(fixture), "^SteamWrapper-deployment-test-[a-f0-9]{32}$", RegexOptions.CultureInvariant) ||
        !Path.GetDirectoryName(fixture)!.Equals(Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) return 2;
    var phase = args[install ? 3 : 2];
    var receipt = Path.GetFullPath(args[install ? 4 : 3]);
    if (!Path.GetDirectoryName(receipt)!.Equals(fixture, StringComparison.OrdinalIgnoreCase)) return 2;
    var permitted = install
        ? new[] { "JournalWritten", "PayloadStaged", "VersionPromoted", "LauncherReplaced", "StateCommitted" }
        : new[] { "RecoveryReceiptWritten", "RecoveryStageMoved" };
    if (!permitted.Contains(phase, StringComparer.Ordinal)) return 2;
    var engine = new DeploymentEngine(root, true, checkpoint =>
    {
        if (checkpoint != phase) return;
        using (var signal = new FileStream(receipt, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
        { signal.Write(Encoding.UTF8.GetBytes(phase)); signal.Flush(true); }
        // This isolated fixture exits without unwinding deployment/lease scopes. It
        // does not kill Manager, Runner, a game, or any process supplied by a user.
        Environment.Exit(73);
    });
    if (install)
    {
        var payload = Path.GetFullPath(args[2]);
        if (!payload.StartsWith(fixture + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return 2;
        engine.Install(payload);
    }
    else engine.Repair();
    return 4; // The selected stop was not reached; this is not recovery evidence.
}

if (args.Length > 2 && args[0] == "oem-host")
{
    // Reproduce an English Windows OEM diagnostic writer without changing the user's console
    // code page. Execute the real compiled Host entry point inside this disposable process.
    Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    var oem = Encoding.GetEncoding(437);
    Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), oem) { AutoFlush = true });
    Console.SetError(new StreamWriter(Console.OpenStandardError(), oem) { AutoFlush = true });
    var host = Assembly.LoadFrom(args[1]);
    return (int)(host.EntryPoint!.Invoke(null, [args.Skip(2).ToArray()]) ?? throw new InvalidOperationException("Missing Host exit code."));
}

if (args.Length != 4 || args[0] is not ("shared" or "exclusive" or "file-reader" or "try-file-reader")) return 2;
if (args[0] == "try-file-reader")
{
    try
    {
        using var reader = new FileStream(args[1], FileMode.Open, FileAccess.Read, FileShare.Read);
        File.WriteAllText(args[2], "opened");
        return 0;
    }
    catch (IOException) { File.WriteAllText(args[2], "blocked"); return 10; }
}
using IDisposable lease = args[0] == "file-reader"
    ? new FileStream(args[1], FileMode.Open, FileAccess.Read, FileShare.None)
    : args[0] == "shared" ? DeploymentLease.AcquireShared(args[1]) : DeploymentLease.AcquireExclusive(args[1]);
File.WriteAllText(args[2], "ready");
var deadline = DateTime.UtcNow.AddSeconds(30);
while (!File.Exists(args[3]) && DateTime.UtcNow < deadline) Thread.Sleep(25);
return File.Exists(args[3]) ? 0 : 3;
