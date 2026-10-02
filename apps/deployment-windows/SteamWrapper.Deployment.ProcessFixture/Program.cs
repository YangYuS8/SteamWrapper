using SteamWrapper.Deployment;
using System.Reflection;
using System.Text;

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
