namespace SteamWrapper.Application.Services;

public sealed record DataPaths(string Root)
{
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
            throw new InvalidOperationException("沙盒模式需要位于 STEAMWRAPPER_E2E_ROOT 内的 LOCALAPPDATA，已阻止访问实际用户配置。");
        local = string.IsNullOrWhiteSpace(local)
            ? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
            : local;
        if (string.IsNullOrWhiteSpace(local) || !Path.IsPathFullyQualified(local))
            throw new InvalidOperationException("无法确定 Windows 本地应用数据目录。");
        return new DataPaths(Path.Combine(Path.GetFullPath(local), "SteamWrapper"));
    }

    internal static bool IsWithin(string path, string root)
    {
        if (!Path.IsPathFullyQualified(path) || !Path.IsPathFullyQualified(root)) return false;
        var prefix = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar;
        return Path.GetFullPath(path).StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
    }
}
