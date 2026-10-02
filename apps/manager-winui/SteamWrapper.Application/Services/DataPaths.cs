using SteamWrapper.Application.Localization;
namespace SteamWrapper.Application.Services;

public sealed record DataPaths(string Root)
{
    public string UiSettingsPath => Path.Combine(Root, "ui-settings.json");
    public string ProfilesPath => Path.Combine(Root, "profiles.toml");
    public string RunnerPath => Path.Combine(Root, "bin", "SteamWrapperRunner.exe");
    public string LogsDirectory => Path.Combine(Root, "logs");
    public string BackupsDirectory => Path.Combine(Root, "backups");
    public string CacheDirectory => Path.Combine(Root, "cache");

    public static DataPaths FromEnvironment(Func<string, string?>? environment = null)
    {
        environment ??= Environment.GetEnvironmentVariable;
        var local = environment("LOCALAPPDATA");
        var sandbox = environment("STEAMWRAPPER_E2E_ROOT");
        if (!string.IsNullOrWhiteSpace(sandbox) &&
            (string.IsNullOrWhiteSpace(local) || !IsWithin(local, sandbox)))
            throw Messages.Invalid("SandboxData");
        local = string.IsNullOrWhiteSpace(local)
            ? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
            : local;
        if (string.IsNullOrWhiteSpace(local) || !Path.IsPathFullyQualified(local))
            throw Messages.Invalid("DataLocation");
        return new DataPaths(Path.Combine(Path.GetFullPath(local), "SteamWrapper"));
    }

    internal static bool IsWithin(string path, string root)
    {
        if (!Path.IsPathFullyQualified(path) || !Path.IsPathFullyQualified(root)) return false;
        var prefix = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar;
        return Path.GetFullPath(path).StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
    }
}
