using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace SteamWrapper.Deployment;

/// <summary>One-shot handoff from Manager to the existing installer; no background service.</summary>
public static class UpdateInstallerHandoff
{
    public static string DefaultCacheRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper", "cache", "updates");

    public static bool IsInstalledManager(string directory)
    {
        try { _ = InstalledRoot(directory); return true; }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException) { return false; }
    }

    private static string InstalledRoot(string directory)
    {
        if (!Path.IsPathFullyQualified(directory)) throw new InvalidDataException("Installed Manager needs its absolute executable directory.");
        var version = new DirectoryInfo(Path.GetFullPath(directory));
        if (version.Parent?.Name != "versions" || version.Parent.Parent is not { } parent)
            throw new InvalidDataException("Portable Manager must be updated in a new directory.");
        var root = InstallationRootPolicy.Normalize(parent.FullName, allowTestRoot: false);
        if (!File.Exists(Path.Combine(root, "installation.json")) || !File.Exists(Path.Combine(version.FullName, DeploymentManifest.FileName)))
            throw new InvalidDataException("Manager does not belong to a complete installation.");
        return root;
    }

    public static void Start(string managerDirectory, string installer, string sha256, long bytes,
        string releaseTag, DateTimeOffset expiresAt, string language)
    {
        var engine = new DeploymentEngine(InstalledRoot(managerDirectory));
        var state = engine.ReadCurrent();
        if (state.Current.Tag != new DirectoryInfo(managerDirectory).Name)
            throw new InvalidDataException("Only the current installed Manager can request an update.");
        RequireLanguage(language);
        using var verified = OpenVerifiedInstaller(DefaultCacheRoot, installer, sha256, bytes, expiresAt, DateTimeOffset.UtcNow);
        // Copy the already manifest-verified NativeAOT host outside the program tree,
        // so it holds no executable lock on files that the installer must replace.
        var helperDirectory = Path.Combine(DefaultCacheRoot, "handoff-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(helperDirectory);
        SafePaths.CheckAncestors(helperDirectory);
        var helper = Path.Combine(helperDirectory, "SteamWrapper.Update.exe");
        File.Copy(Path.Combine(managerDirectory, "Deployment", "SteamWrapper.exe"), helper, overwrite: false);
        using var helperFile = new FileStream(helper, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (Convert.ToHexStringLower(SHA256.HashData(helperFile)) != state.LauncherSha256)
            throw new InvalidDataException("The update helper differs from the installed deployment component.");
        using var parent = Process.GetCurrentProcess();
        var start = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = helperDirectory };
        foreach (var argument in new[] { "--apply-update", "--root", engine.Root, "--installer", Path.GetFullPath(installer),
            "--sha256", sha256, "--bytes", bytes.ToString(CultureInfo.InvariantCulture), "--release-tag", releaseTag,
            "--expires", expiresAt.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture),
            "--parent-pid", parent.Id.ToString(CultureInfo.InvariantCulture), "--parent-start", parent.StartTime.ToUniversalTime().Ticks.ToString(CultureInfo.InvariantCulture),
            "--transaction", state.Transaction, "--language", language }) start.ArgumentList.Add(argument);
        // A restarted Manager must obtain a fresh deployment receipt from its launcher.
        ClearLaunchReceipt(start);
        using var process = Process.Start(start) ?? throw new IOException("The update installer could not start.");
    }

    internal static FileStream OpenVerifiedInstaller(string cacheRoot, string installer, string sha256,
        long bytes, DateTimeOffset expiresAt, DateTimeOffset now)
    {
        if (!Path.IsPathFullyQualified(cacheRoot) || !Path.IsPathFullyQualified(installer) || installer.StartsWith(@"\\", StringComparison.Ordinal) ||
            !Path.GetFullPath(installer).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(cacheRoot)) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetExtension(installer).Equals(".exe", StringComparison.OrdinalIgnoreCase) ||
            !Regex.IsMatch(sha256, "^[0-9a-f]{64}$", RegexOptions.CultureInvariant) || bytes is < 1 or > 512L * 1024 * 1024 || expiresAt <= now)
            throw new InvalidDataException("The downloaded installer is outside its verified update contract.");
        SafePaths.CheckAncestors(installer);
        var stream = new FileStream(installer, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            if (stream.Length != bytes || Convert.ToHexStringLower(SHA256.HashData(stream)) != sha256)
                throw new InvalidDataException("The downloaded installer changed before installation.");
            stream.Position = 0;
            return stream;
        }
        catch { stream.Dispose(); throw; }
    }

    internal static void WaitForManagerExit(int processId, long startTicks, int timeoutMilliseconds = 30000)
    {
        if (processId <= 0 || processId == Environment.ProcessId || startTicks <= 0)
            throw new InvalidDataException("An update needs a valid originating Manager process.");
        Process parent;
        try { parent = Process.GetProcessById(processId); }
        catch (ArgumentException) { return; } // The original Manager already exited normally.
        using (parent)
        {
            if (parent.StartTime.ToUniversalTime().Ticks != startTicks) return; // PID was reused.
            if (!parent.WaitForExit(timeoutMilliseconds))
                throw new DeploymentException("Busy", "Manager has not closed. No application was force-closed.");
        }
    }

    internal static void Apply(DeploymentEngine engine, string cacheRoot, string installer, string sha256, long bytes,
        string releaseTag, DateTimeOffset expiresAt, string transaction, int parentPid, long parentStart, string language,
        Func<ProcessStartInfo, int>? runInstaller = null)
    {
        RequireLanguage(language);
        if (!Regex.IsMatch(releaseTag, "^v[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("The update release identity is invalid.");
        WaitForManagerExit(parentPid, parentStart);
        if (engine.ReadCurrent().Transaction != transaction)
            throw new InvalidDataException("Another installation changed Manager after the update was requested.");
        using var verified = OpenVerifiedInstaller(cacheRoot, installer, sha256, bytes, expiresAt, DateTimeOffset.UtcNow);
        var start = new ProcessStartInfo(installer) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(installer)! };
        foreach (var argument in new[] { "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=" + engine.Root, "/LANG=" + (language == "zh-CN" ? "chinesesimplified" : "english"),
            "/LOG=" + Path.Combine(Path.GetDirectoryName(installer)!, "installation.log") }) start.ArgumentList.Add(argument);
        ClearLaunchReceipt(start);
        var exit = (runInstaller ?? RunInstaller)(start);
        if (exit != 0) throw new DeploymentException("UpdateInstall", "The installer did not finish. Close other Manager windows and retry; installation log: " + Path.Combine(Path.GetDirectoryName(installer)!, "installation.log"));
        if (engine.ReadCurrent().Current.Tag != releaseTag)
            throw new InvalidDataException("The installer did not activate the expected Manager version.");
    }

    private static int RunInstaller(ProcessStartInfo start)
    {
        using var process = Process.Start(start) ?? throw new IOException("The verified installer could not start.");
        process.WaitForExit();
        return process.ExitCode;
    }

    internal static void ClearLaunchReceipt(ProcessStartInfo start)
    {
        foreach (var name in new[] { "STEAMWRAPPER_DEPLOYMENT_ROOT", "STEAMWRAPPER_DEPLOYMENT_TRANSACTION", "STEAMWRAPPER_DEPLOYMENT_LAUNCH_SESSION", "STEAMWRAPPER_DEPLOYMENT_LAUNCH_TOKEN" })
            start.Environment.Remove(name);
    }

    private static void RequireLanguage(string language)
    {
        if (language is not ("en" or "zh-CN")) throw new InvalidDataException("Unsupported installer language.");
    }
}
