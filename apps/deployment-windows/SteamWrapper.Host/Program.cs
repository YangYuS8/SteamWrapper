using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using SteamWrapper.Deployment;

var selectedLanguage = "en";
var launchRequested = args.Length == 0;
var updateRequested = args.Contains("--apply-update", StringComparer.Ordinal);
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
        if (argument is "--install" or "--uninstall" or "--repair" or "--rollback" or "--apply-update" or "--test-root" or "--restore-steam")
        { if (!switches.Add(argument)) throw new InvalidDataException("Duplicate option."); }
        else if (argument is "--root" or "--payload" or "--lease-session" or "--session-token" or "--session-timeout-seconds" or "--language" or
            "--installer" or "--sha256" or "--bytes" or "--release-tag" or "--expires" or "--parent-pid" or "--parent-start" or "--transaction" or "--cleanup")
        { if (++index == args.Length || !options.TryAdd(argument, args[index])) throw new InvalidDataException("Missing or duplicate option value."); }
        else throw new InvalidDataException("Unsupported deployment option.");
    }
    var test = switches.Remove("--test-root");
    var restoreSteam = switches.Remove("--restore-steam");
    if ((restoreSteam || options.ContainsKey("--cleanup")) && !switches.Contains("--uninstall"))
        throw new InvalidDataException("Cleanup and Steam restoration require explicit uninstall.");
    if (test && Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST") != "1") throw new InvalidDataException("A test root requires the explicit isolated test environment.");
    if (options.TryGetValue("--language", out var language))
    { if (language is not ("en" or "zh-CN")) throw new InvalidDataException("Unsupported language."); selectedLanguage = language; }
    var root = options.GetValueOrDefault("--root") ?? (switches.Count == 0 ? AppContext.BaseDirectory : DeploymentEngine.DefaultRoot);
    var engine = new DeploymentEngine(root, test);
    if (!options.ContainsKey("--language")) selectedLanguage = DeploymentMessages.ReadPreferredLanguage(IsolatedPreferencePath(engine.Root, test));
    if (switches.Count > 1) throw new InvalidDataException("Select one deployment operation.");
    if (updateRequested)
    {
        if (options.Keys.Any(key => key is "--payload" or "--lease-session" or "--session-token" or "--session-timeout-seconds"))
            throw new InvalidDataException("Update installation cannot mix deployment operations.");
        var updateCache = UpdateInstallerHandoff.DefaultCacheRoot;
        if (test)
        {
            var preferencePath = IsolatedPreferencePath(engine.Root, true) ?? throw new InvalidDataException("Update tests require explicit isolated data paths.");
            updateCache = Path.Combine(Path.GetDirectoryName(preferencePath)!, "cache", "updates");
        }
        string Required(string key) => options.GetValueOrDefault(key) ?? throw new InvalidDataException("Missing update handoff field.");
        UpdateInstallerHandoff.Apply(engine, updateCache, Required("--installer"), Required("--sha256"),
            long.Parse(Required("--bytes"), System.Globalization.CultureInfo.InvariantCulture), Required("--release-tag"),
            DateTimeOffset.FromUnixTimeSeconds(long.Parse(Required("--expires"), System.Globalization.CultureInfo.InvariantCulture)), Required("--transaction"),
            int.Parse(Required("--parent-pid"), System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(Required("--parent-start"), System.Globalization.CultureInfo.InvariantCulture), selectedLanguage);
        Launch(engine, selectedLanguage);
        return 0;
    }
    if (options.Keys.Any(key => key is "--installer" or "--sha256" or "--bytes" or "--release-tag" or "--expires" or "--parent-pid" or "--parent-start" or "--transaction"))
        throw new InvalidDataException("Update fields require an update operation.");
    if (switches.Contains("--install")) engine.ValidateLocation();
    launchRequested = switches.Count == 0;
    Action operation = switches.FirstOrDefault() switch
    {
        "--install" => () => engine.InstallUnderLease(options.GetValueOrDefault("--payload") ?? throw new InvalidDataException("Install needs a complete payload directory.")),
        "--uninstall" => () => Uninstall(engine, test, restoreSteam, options.GetValueOrDefault("--cleanup"), options.GetValueOrDefault("--lease-session")),
        "--repair" => () => engine.RepairUnderLease(),
        "--rollback" => () => engine.RollbackUnderLease(),
        null => () => Launch(engine, selectedLanguage),
        _ => throw new InvalidDataException("Unknown operation.")
    };
    if (options.TryGetValue("--lease-session", out var session))
    {
        if (switches.Count != 1) throw new InvalidDataException("A lease session is for a mutation operation only.");
        var seconds = options.TryGetValue("--session-timeout-seconds", out var timeout) ? int.Parse(timeout, System.Globalization.CultureInfo.InvariantCulture) : 300;
        return DeploymentHostSession.Run(engine.Root, session, options.GetValueOrDefault("--session-token") ?? "", seconds, operation);
    }
    if (options.ContainsKey("--session-token") || options.ContainsKey("--session-timeout-seconds")) throw new InvalidDataException("Session options require a lease session.");
    if (switches.Count == 0) operation();
    else { using var lease = DeploymentLease.AcquireExclusive(engine.Root); operation(); }
    return 0;
}
catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or FormatException or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or ArgumentException or OverflowException)
{
    var message = DeploymentMessages.ForError(error, selectedLanguage);
    Console.Error.WriteLine(message);
    if ((launchRequested || updateRequested) && OperatingSystem.IsWindows()) NativeDialog.Show(message, selectedLanguage);
    return error is DeploymentException { Code: "Busy" } ? 10 : 11;
}

static void Uninstall(DeploymentEngine engine, bool test, bool restoreSteam, string? selected, string? session)
{
    var cleanup = ManagerDataCleanupOptions.None;
    foreach (var item in (selected ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries))
        cleanup |= item switch
        {
            "cache" => ManagerDataCleanupOptions.DownloadedCache,
            "logs" => ManagerDataCleanupOptions.Logs,
            "settings" => ManagerDataCleanupOptions.Preferences,
            "profiles" => ManagerDataCleanupOptions.Profiles,
            "profile-backups" => ManagerDataCleanupOptions.ProfileBackups,
            "runner" => ManagerDataCleanupOptions.Runner,
            _ => throw new InvalidDataException("Unknown uninstall selection.")
        };
    if (!restoreSteam && cleanup == ManagerDataCleanupOptions.None) { engine.UninstallUnderLease(); return; }
    var dataRoot = test
        ? Path.GetDirectoryName(IsolatedPreferencePath(engine.Root, true) ?? throw new InvalidDataException("Cleanup tests require isolated data paths."))!
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper");
    var removeRuntime = (cleanup & (ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.Runner)) != 0;
    var runtimeRemovalAllowed = false;
    var retained = false;
    bool SteamRunning()
    {
        if (test) return File.Exists(Path.Combine(Environment.GetEnvironmentVariable("STEAMWRAPPER_E2E_ROOT")!, "steam-running"));
        var processes = Process.GetProcessesByName("steam").Concat(Process.GetProcessesByName("steamwebhelper")).ToArray();
        foreach (var process in processes) process.Dispose();
        return processes.Length != 0;
    }
    if (restoreSteam || removeRuntime)
    {
        if (SteamRunning()) throw new DeploymentException("SteamBusy", "Steam must exit normally before removing launch integration.");
        try
        {
            string? steamRoot = null;
            if (test)
            {
                steamRoot = Environment.GetEnvironmentVariable("STEAM_DIR");
                var sandbox = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Environment.GetEnvironmentVariable("STEAMWRAPPER_E2E_ROOT")!)) + Path.DirectorySeparatorChar;
                if (string.IsNullOrWhiteSpace(steamRoot) || !Path.GetFullPath(steamRoot).StartsWith(sandbox, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Steam cleanup tests require a contained Steam fixture.");
            }
            else if (OperatingSystem.IsWindows())
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
                steamRoot = key?.GetValue("SteamPath") as string;
                steamRoot ??= new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) }
                    .Select(path => Path.Combine(path, "Steam")).FirstOrDefault(Directory.Exists);
            }
            if (string.IsNullOrWhiteSpace(steamRoot)) throw new InvalidDataException("Steam could not be located.");
            var plan = SteamLaunchRestoration.Inspect(steamRoot, dataRoot);
            if (removeRuntime && (plan.UnrecognizedReferences != 0 || !restoreSteam && plan.Changes.Count != 0))
                throw new InvalidDataException("Some Steam launch options still depend on Runner or are customized.");
            if (restoreSteam) SteamLaunchRestoration.Restore(plan, dataRoot, SteamRunning);
            var after = SteamLaunchRestoration.Inspect(steamRoot, dataRoot);
            runtimeRemovalAllowed = !SteamRunning() && after.Changes.Count == 0 && after.UnrecognizedReferences == 0;
            retained = after.UnrecognizedReferences != 0;
            if (removeRuntime && !runtimeRemovalAllowed) throw new InvalidDataException("Steam launch integration is still active.");
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException)
        { throw new DeploymentException("SteamRestore", "Steam restoration could not be safely completed; keep profiles and Runner.", error); }
    }
    engine.UninstallUnderLease();
    if (removeRuntime && SteamRunning()) runtimeRemovalAllowed = false;
    var result = ManagerDataCleanup.CleanupAt(dataRoot, cleanup, runtimeRemovalAllowed);
    retained |= result.HasRetainedFiles;
    if (session is not null)
        File.WriteAllText(Path.Combine(session, "cleanup-result.txt"), retained ? "retained" : "complete");
}

static string? IsolatedPreferencePath(string programRoot, bool test)
{
    if (!test) return null;
    var sandbox = Environment.GetEnvironmentVariable("STEAMWRAPPER_E2E_ROOT");
    if (string.IsNullOrWhiteSpace(sandbox)) return null;
    var local = Environment.GetEnvironmentVariable("LOCALAPPDATA");
    if (!Path.IsPathFullyQualified(sandbox) || string.IsNullOrWhiteSpace(local) || !Path.IsPathFullyQualified(local))
        throw new InvalidDataException("An isolated Host needs explicit sandbox data paths.");
    var prefix = Path.TrimEndingDirectorySeparator(Path.GetFullPath(sandbox)) + Path.DirectorySeparatorChar;
    var dataRoot = Path.GetFullPath(local);
    if (!programRoot.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || !dataRoot.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        throw new InvalidDataException("Isolated Host program and preference paths must stay in their sandbox.");
    return Path.Combine(dataRoot, "SteamWrapper", "ui-settings.json");
}

static void Launch(DeploymentEngine engine, string language)
{
    using var lease = DeploymentLease.AcquireShared(engine.Root);
    var current = engine.ReadCurrent();
    var token = Guid.NewGuid().ToString("N");
    var directory = Path.Combine(Path.GetTempPath(), "SteamWrapper-launch-" + token);
    Directory.CreateDirectory(directory);
    var start = new ProcessStartInfo(engine.CurrentManagerPath(current)) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(engine.CurrentManagerPath(current))! };
    UpdateInstallerHandoff.ClearLaunchReceipt(start);
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
