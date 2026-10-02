namespace SteamWrapper.Deployment;

/// <summary>User messages are separate from diagnostic exceptions; identifiers, paths and user data are never translated.</summary>
public static class DeploymentMessages
{
    public static string ReadPreferredLanguage(string? settingsPath = null)
    {
        var path = settingsPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper", "ui-settings.json");
        try
        {
            SafePaths.CheckAncestors(path);
            var bytes = DeploymentManifest.ReadJson(path, 64 * 1024);
            using var document = System.Text.Json.JsonDocument.Parse(bytes);
            var root = document.RootElement;
            return root.ValueKind == System.Text.Json.JsonValueKind.Object && root.TryGetProperty("language", out var language) &&
                language.ValueKind == System.Text.Json.JsonValueKind.String && language.GetString() == "zh-CN" ? "zh-CN" : "en";
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or ArgumentException)
        { return "en"; } // Read-only preference failure cannot block recovery or modify user settings.
    }
    public static string ForError(Exception error, string language = "en")
    {
        var chinese = language == "zh-CN";
        var code = error is DeploymentException deployment ? deployment.Code : error is InvalidDataException or System.Text.Json.JsonException ? "Invalid" : "Io";
        return (code, chinese) switch
        {
            ("Busy", false) => "SteamWrapper Manager is still running or another installation is active. Close Manager normally and retry. Games will not be closed.",
            ("Busy", true) => "SteamWrapper 管理器仍在运行，或另一个安装正在进行。请正常关闭管理器后重试；游戏不会被关闭。",
            ("Downgrade", false) => "This installer is older than the installed Manager. Use the explicit rollback command for a verified compatible previous version.",
            ("Downgrade", true) => "此安装包比已安装的管理器更旧。要返回经过验证的兼容版本，请使用明确的回退命令。",
            ("SameVersion", false) => "This release has different bytes for the same version. Download the matching original installer or a newer release; existing files are preserved.",
            ("SameVersion", true) => "此发行包与同版本的原文件不同。请下载匹配的原始安装包或更新版本；现有文件已保留。",
            ("Space", false) => "There is not enough disk space for a complete staged update. Free space and retry; the active Manager is preserved.",
            ("Space", true) => "磁盘空间不足，无法暂存完整更新。请释放空间后重试；当前管理器已保留。",
            ("Missing", false) => "No complete Manager installation is available. Run the matching verified installer to install or repair it.",
            ("Missing", true) => "没有可用的完整管理器安装。请运行匹配且经过验证的安装包进行安装或修复。",
            ("Previous", false) => "No verified previous Manager is available. Reinstall from the matching original installer.",
            ("Previous", true) => "没有经过验证的旧版管理器。请使用匹配的原始安装包重新安装。",
            ("Recovery", false) => "An interrupted installation needs repair. Run the verified installer or the repair command before launching Manager.",
            ("Recovery", true) => "之前中断的安装需要修复。启动管理器前，请运行经过验证的安装包或修复命令。",
            ("Contract" or "Version" or "Transaction", false) => "The selected Manager version or startup receipt is incompatible. Use the stable launcher or the matching installer; Runner and game data are preserved.",
            ("Contract" or "Version" or "Transaction", true) => "所选管理器版本或启动凭据不兼容。请使用固定启动器或匹配的安装包；Runner 和游戏数据已保留。",
            ("Invalid", false) => "The package or installation could not be safely verified. Unknown files are preserved. Use the matching original installer and review the recovery guidance.",
            ("Invalid", true) => "无法安全验证安装包或现有安装。未知文件已保留。请使用匹配的原始安装包，并查看恢复说明。",
            (_, false) => "The operation could not complete. Close Manager normally, check available disk space and file access, then retry. No game is terminated.",
            (_, true) => "操作未能完成。请正常关闭管理器，检查磁盘空间和文件访问权限后重试；游戏不会被终止。"
        };
    }
    public static string SlowStartup(string language = "en") => language == "zh-CN"
        ? "管理器仍在启动。没有终止该进程，也没有自动回退。请等待，或在其正常退出后使用修复或回退命令。"
        : "Manager is still starting. It was not terminated or automatically rolled back. Wait, or use repair or rollback after it exits normally.";
}
