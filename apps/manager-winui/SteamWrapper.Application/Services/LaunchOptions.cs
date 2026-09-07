namespace SteamWrapper.Application.Services;

public static class LaunchOptions
{
    public static string Build(string stableRunnerPath, string appId)
    {
        if (string.IsNullOrWhiteSpace(stableRunnerPath) || !Path.IsPathFullyQualified(stableRunnerPath) ||
            stableRunnerPath.Any(c => c == '"' || char.IsControl(c)) ||
            !string.Equals(Path.GetFileName(stableRunnerPath), "SteamWrapperRunner.exe", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Runner 路径必须是稳定目录中的 SteamWrapperRunner.exe 完整路径。", nameof(stableRunnerPath));
        if (string.IsNullOrEmpty(appId) || appId.Any(c => c is < '0' or > '9') ||
            !uint.TryParse(appId, out var numericId) || numericId == 0)
            throw new ArgumentException("Steam AppID 必须是有效的正整数。", nameof(appId));
        return $"\"{stableRunnerPath}\" --appid \"{appId}\" -- %command%";
    }
}
