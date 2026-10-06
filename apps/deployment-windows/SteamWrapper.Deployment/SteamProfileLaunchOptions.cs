using System.Diagnostics;
using System.Globalization;

namespace SteamWrapper.Deployment;

public sealed record SteamProfileLaunchInspection(int RecognizedCommands, int UnrecognizedReferences)
{
    public bool HasReferences => RecognizedCommands != 0 || UnrecognizedReferences != 0;
}

public sealed record SteamProfileLaunchRestoreResult(int ClearedCommands, int RemainingReferences);

/// <summary>Selected-game removal of recognized integration, without reconstructing unknown historical arguments.</summary>
public static class SteamProfileLaunchOptions
{
    public static Task<SteamProfileLaunchInspection> InspectSelectedAsync(string dataRoot, string steamRoot, string appId,
        CancellationToken cancellationToken = default) => RunAsync(() =>
        {
            Validate(dataRoot, steamRoot, appId);
            return Inspection(SteamLaunchRestoration.Inspect(steamRoot, dataRoot, appId, cancellationToken));
        }, cancellationToken);

    public static Task<SteamProfileLaunchRestoreResult> RestoreSelectedAsync(string dataRoot, string steamRoot, string appId,
        CancellationToken cancellationToken = default) => RestoreSelectedAsync(dataRoot, steamRoot, appId, IsSteamRunning,
            cancellationToken: cancellationToken);

    public static Task EnsureRemovalAllowedAsync(string dataRoot, string steamRoot, string appId,
        CancellationToken cancellationToken = default) => EnsureRemovalAllowedAsync(dataRoot, steamRoot, appId, IsSteamRunning, cancellationToken);

    public static Task EnsureRemovalAllowedAsync(string dataRoot, string steamRoot, string appId, string profileKey,
        CancellationToken cancellationToken = default) => EnsureRemovalAllowedAsync(dataRoot, steamRoot, appId, profileKey, IsSteamRunning, cancellationToken);

    internal static Task EnsureRemovalAllowedAsync(string dataRoot, string steamRoot, string appId, string profileKey,
        Func<bool> steamRunning, CancellationToken cancellationToken = default)
        => RunAsync(() =>
        {
            Validate(dataRoot, steamRoot, appId);
            // The bounded reference matcher is not a Windows command-line decoder. Preserve
            // profiles whose keys require escaping rather than claim their references were absent.
            if (string.IsNullOrEmpty(profileKey) || profileKey.Any(character => character is '\\' or '"' || char.IsControl(character)))
                throw new InvalidDataException("The profile key cannot be safely checked for escaped Runner references; the profile was preserved.");
            RequireSteamStopped(steamRunning);
            var inspection = Inspection(SteamLaunchRestoration.Inspect(steamRoot, dataRoot, appId, cancellationToken, profileKey));
            RequireSteamStopped(steamRunning);
            if (inspection.HasReferences)
                throw new DeploymentException("SteamReferences", "Steam Launch Options still reference this configuration. Clear recognized integration first; preserve and review custom options manually.");
            return true;
        }, cancellationToken);

    internal static Task<SteamProfileLaunchRestoreResult> RestoreSelectedAsync(string dataRoot, string steamRoot, string appId,
        Func<bool> steamRunning, Action<string>? beforeReplace = null, CancellationToken cancellationToken = default)
        => RunAsync(() =>
        {
            Validate(dataRoot, steamRoot, appId);
            RequireSteamStopped(steamRunning);
            using var lease = AcquireDataLease(dataRoot);
            var plan = SteamLaunchRestoration.Inspect(steamRoot, dataRoot, appId, cancellationToken);
            RequireSteamStopped(steamRunning);
            cancellationToken.ThrowIfCancellationRequested();
            var cleared = SteamLaunchRestoration.Restore(plan, dataRoot, steamRunning, path =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                RequireSteamStopped(steamRunning);
                beforeReplace?.Invoke(path);
            });
            var after = Inspection(SteamLaunchRestoration.Inspect(steamRoot, dataRoot, appId, cancellationToken));
            return new SteamProfileLaunchRestoreResult(cleared, after.RecognizedCommands + after.UnrecognizedReferences);
        }, cancellationToken);

    internal static Task EnsureRemovalAllowedAsync(string dataRoot, string steamRoot, string appId, Func<bool> steamRunning,
        CancellationToken cancellationToken = default) => EnsureRemovalAllowedAsync(dataRoot, steamRoot, appId, appId, steamRunning, cancellationToken);

    private static SteamProfileLaunchInspection Inspection(SteamLaunchPlan plan) =>
        new(plan.Changes.Sum(change => change.Count), plan.UnrecognizedReferences);

    private static void Validate(string dataRoot, string steamRoot, string appId)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Selected Steam launch-option restoration requires Windows file semantics.");
        if (!uint.TryParse(appId, NumberStyles.None, CultureInfo.InvariantCulture, out var id) || id == 0 ||
            id.ToString(CultureInfo.InvariantCulture) != appId)
            throw new InvalidDataException("Select one unambiguous numeric Steam AppID before removing launch integration.");
        foreach (var path in new[] { dataRoot, steamRoot })
        {
            if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal))
                throw new InvalidDataException("Launch-option restoration requires fully qualified local data and Steam paths.");
            SafePaths.CheckAncestors(path);
        }
    }

    private static FileStream AcquireDataLease(string dataRoot)
    {
        var path = Path.Combine(dataRoot, "profiles.toml.lock");
        SafePaths.CheckAncestors(path);
        Directory.CreateDirectory(dataRoot);
        try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException error) { throw new DeploymentException("SteamDataBusy", "Configuration data is busy. Wait for another save or restoration to finish, then retry.", error); }
    }

    private static void RequireSteamStopped(Func<bool> steamRunning)
    {
        if (steamRunning()) throw new DeploymentException("SteamBusy", "Exit Steam normally before restoring launch options or removing this configuration.");
    }

    private static bool IsSteamRunning()
    {
        var processes = Process.GetProcessesByName("steam").Concat(Process.GetProcessesByName("steamwebhelper")).ToArray();
        try { return processes.Length != 0; }
        finally { foreach (var process in processes) process.Dispose(); }
    }

    private static Task<T> RunAsync<T>(Func<T> operation, CancellationToken cancellationToken) => Task.Run(() =>
    {
        cancellationToken.ThrowIfCancellationRequested();
        try { return operation(); }
        catch (Exception error) when (error is not DeploymentException &&
            error is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.DecoderFallbackException)
        {
            throw new DeploymentException("SteamInspect", "Steam integration could not be safely inspected or changed. Files and available backups were preserved; reload and review the reported cause.", error);
        }
    }, cancellationToken);
}
