using SteamWrapper.Application.Localization;
namespace SteamWrapper.Application.Services;

public static class LaunchOptions
{
    public static string Build(string stableRunnerPath, string appId)
    {
        if (string.IsNullOrWhiteSpace(stableRunnerPath) || !Path.IsPathFullyQualified(stableRunnerPath) ||
            stableRunnerPath.Any(c => c == '"' || char.IsControl(c)) ||
            !string.Equals(Path.GetFileName(stableRunnerPath), "SteamWrapperRunner.exe", StringComparison.OrdinalIgnoreCase))
            throw Messages.Argument("RunnerPath", nameof(stableRunnerPath));
        if (string.IsNullOrEmpty(appId) || appId.Any(c => c is < '0' or > '9') ||
            !uint.TryParse(appId, out var numericId) || numericId == 0)
            throw Messages.Argument("AppIdInvalid", nameof(appId));
        return $"\"{stableRunnerPath}\" --appid \"{appId}\" -- %command%";
    }
}
