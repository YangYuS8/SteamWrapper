using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using SteamWrapper.Deployment;

var selectedLanguage = DeploymentMessages.ReadPreferredLanguage();
var launchRequested = args.Length == 0;
try
{
    // Redirected diagnostics use a fixed byte encoding on every Windows language. Configure
    // writers rather than the console code page so Explorer/WinExe startup needs no console.
    if (Console.IsOutputRedirected)
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true });
    if (Console.IsErrorRedirected)
        Console.SetError(new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true });
    var switches = new HashSet<string>(StringComparer.Ordinal);
    var options = new Dictionary<string, string>(StringComparer.Ordinal);
    for (var index = 0; index < args.Length; index++)
    {
        var argument = args[index];
        if (argument is "--install" or "--uninstall" or "--repair" or "--rollback" or "--test-root")
        { if (!switches.Add(argument)) throw new InvalidDataException("Duplicate option."); }
        else if (argument is "--root" or "--payload" or "--lease-session" or "--session-token" or "--session-timeout-seconds" or "--language")
        { if (++index == args.Length || !options.TryAdd(argument, args[index])) throw new InvalidDataException("Missing or duplicate option value."); }
        else throw new InvalidDataException("Unsupported deployment option.");
    }
    var test = switches.Remove("--test-root");
    if (test && Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST") != "1") throw new InvalidDataException("A test root requires the explicit isolated test environment.");
    if (options.TryGetValue("--language", out var language))
    { if (language is not ("en" or "zh-CN")) throw new InvalidDataException("Unsupported language."); selectedLanguage = language; }
    var root = options.GetValueOrDefault("--root") ?? (switches.Count == 0 ? AppContext.BaseDirectory : DeploymentEngine.DefaultRoot);
    var engine = new DeploymentEngine(root, test);
    if (switches.Count > 1) throw new InvalidDataException("Select one deployment operation.");
    launchRequested = switches.Count == 0;
    Action operation = switches.FirstOrDefault() switch
    {
        "--install" => () => engine.InstallUnderLease(options.GetValueOrDefault("--payload") ?? throw new InvalidDataException("Install needs a complete payload directory.")),
        "--uninstall" => engine.UninstallUnderLease,
        "--repair" => () => engine.RepairUnderLease(),
        "--rollback" => () => engine.RollbackUnderLease(),
        null => () => Launch(engine, selectedLanguage),
        _ => throw new InvalidDataException("Unknown operation.")
    };
    if (options.TryGetValue("--lease-session", out var session))
    {
        if (switches.Count != 1) throw new InvalidDataException("A lease session is for a mutation operation only.");
        var seconds = options.TryGetValue("--session-timeout-seconds", out var timeout) ? int.Parse(timeout) : 300;
        return DeploymentHostSession.Run(engine.Root, session, options.GetValueOrDefault("--session-token") ?? "", seconds, operation);
    }
    if (options.ContainsKey("--session-token") || options.ContainsKey("--session-timeout-seconds")) throw new InvalidDataException("Session options require a lease session.");
    if (switches.Count == 0) operation();
    else { using var lease = DeploymentLease.AcquireExclusive(engine.Root); operation(); }
    return 0;
}
catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or FormatException or System.Text.Json.JsonException)
{
    var message = DeploymentMessages.ForError(error, selectedLanguage);
    Console.Error.WriteLine(message);
    if (launchRequested && OperatingSystem.IsWindows()) NativeDialog.Show(message, selectedLanguage);
    return error is DeploymentException { Code: "Busy" } ? 10 : 11;
}

static void Launch(DeploymentEngine engine, string language)
{
    using var lease = DeploymentLease.AcquireShared(engine.Root);
    var current = engine.ReadCurrent();
    var token = Guid.NewGuid().ToString("N");
    var directory = Path.Combine(Path.GetTempPath(), "SteamWrapper-launch-" + token);
    Directory.CreateDirectory(directory);
    var start = new ProcessStartInfo(engine.CurrentManagerPath(current)) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(engine.CurrentManagerPath(current))! };
    start.Environment["STEAMWRAPPER_DEPLOYMENT_ROOT"] = engine.Root;
    start.Environment["STEAMWRAPPER_DEPLOYMENT_TRANSACTION"] = current.Transaction;
    start.Environment["STEAMWRAPPER_DEPLOYMENT_LAUNCH_SESSION"] = directory;
    start.Environment["STEAMWRAPPER_DEPLOYMENT_LAUNCH_TOKEN"] = token;
    using var process = Process.Start(start) ?? throw new IOException("Manager could not start.");
    var deadline = DateTime.UtcNow.AddSeconds(30);
    while (DateTime.UtcNow < deadline)
    {
        var receipt = Path.Combine(directory, "ready.txt");
        if (File.Exists(receipt) && new FileInfo(receipt).Length <= 64 && File.ReadAllText(receipt) == token) return;
        if (process.HasExited) throw new IOException("Manager exited before initialization. Use the verified repair or rollback operation.");
        Thread.Sleep(50);
    }
    // Never terminate or start a competing version when a slow Manager is still alive.
    Console.Error.WriteLine(DeploymentMessages.SlowStartup(language));
}

internal static class NativeDialog
{
    public static void Show(string message, string language) => MessageBoxW(0, message,
        language == "zh-CN" ? "SteamWrapper 管理器" : "SteamWrapper Manager", 0x10);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(nint window, string message, string title, uint flags);
}
