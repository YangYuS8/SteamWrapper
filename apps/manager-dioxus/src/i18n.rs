use steamwrapper_manager_core::{Language, ManagerError};

macro_rules! catalog {
    ($($key:ident => ($en:literal, $zh:literal)),+ $(,)?) => {
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub enum Text { $($key),+ }
        impl Text {
            pub fn text(self, language: Language) -> &'static str {
                match (self, language) {
                    $((Self::$key, Language::English) => $en,
                      (Self::$key, Language::SimplifiedChinese) => $zh),+
                }
            }
            #[cfg(test)]
            pub const ALL: &'static [Self] = &[$(Self::$key),+];
        }
    };
}

catalog! {
    Ready => ("Ready", "准备就绪"),
    ManualName => ("Manually added game", "手动添加的游戏"),
    BootstrapFailed => ("Runner initialization failed:", "Runner 初始化失败："),
    Scanning => ("Scanning local Steam games…", "正在扫描本地 Steam 游戏……"),
    NoGamesFound => ("No local Steam games found", "没有扫描到本地 Steam 游戏"),
    GamesFound => ("Found {count} local Steam game(s)", "已找到 {count} 个本地 Steam 游戏"),
    ScanFailed => ("Scan failed:", "扫描失败："),
    ManualCreated => ("Manual game created. Choose a target program, then save.", "已创建手动游戏条目，请选择目标程序后保存"),
    Configuring => ("Configuring the game launch target", "正在配置游戏启动目标"),
    Editing => ("Editing the saved game profile", "正在编辑已保存的游戏配置"),
    RunnerInstalled => ("Runner installed at the stable path", "Runner 已安装到稳定路径"),
    RunnerCurrent => ("Runner is up to date; no files need copying", "Runner 已是当前版本，无需重复复制"),
    RunnerFailed => ("Runner operation failed:", "Runner 操作失败："),
    TargetSelected => ("Target program selected", "已选择目标程序"),
    OptionsGenerated => ("Launch options generated", "已生成启动选项"),
    GenerateFailed => ("Could not generate usable launch options:", "无法生成可用启动选项："),
    ChooseGame => ("Choose a game first", "请先选择一个游戏"),
    MissingDirectory => ("This game has no install folder; the profile cannot be saved yet", "当前游戏缺少安装目录，暂时无法保存配置"),
    EnterTarget => ("Enter the path to the executable or launcher to start", "请填写真正要启动的 exe 或 launcher 路径"),
    Saved => ("Profile saved and launch options generated", "配置已保存，并已生成启动选项"),
    SavedRunnerUnavailable => ("Profile saved, but Runner is not ready:", "配置已保存，但 Runner 尚不可用："),
    SaveFailed => ("Save failed:", "保存失败："),
    ProfilesFailed => ("Could not load profiles:", "读取配置失败："),
    LogsFailed => ("Could not load logs:", "读取日志失败："),
    PathsFailed => ("Could not load paths:", "读取路径失败："),
    RunnerCheckFailed => ("Could not check Runner:", "检查 Runner 失败："),
    Minimize => ("Minimize window", "最小化窗口"),
    Maximize => ("Maximize or restore window", "最大化或还原窗口"),
    CloseWindow => ("Close window", "关闭窗口"),
    LanguageLabel => ("Language", "语言"),
    Library => ("Game library", "游戏库"),
    Configured => ("Configured games", "已配置游戏"),
    Logs => ("Logs", "日志"),
    Settings => ("Settings", "设置"),
    Preview => ("Manager v2 · Dioxus preview", "Manager v2 · Dioxus 预览版"),
    Collapse => ("Collapse sidebar", "折叠侧边栏"),
    Expand => ("Expand sidebar", "展开侧边栏"),
    CoverSources => ("Local scan · Local covers first, official Steam CDN fallback", "本地扫描 · 本地缓存优先，官方 Steam CDN 回退"),
    LibraryHelp => ("Choose a game, then enter the executable or launcher you want Steam to start.", "按照步骤完成配置；选择游戏后填写真正需要启动的 exe 或 launcher。"),
    ScanGames => ("Scan local Steam games", "扫描本地 Steam 游戏"),
    AddGame => ("Add game manually", "手动添加游戏"),
    Scan => ("Scan", "扫描"),
    ScanHelp => ("Read the local Steam library", "读取本地 Steam 游戏库"),
    Choose => ("Choose", "选择"),
    ChooseHelp => ("Select the program to start", "填写实际启动的程序"),
    Save => ("Save", "保存"),
    SaveHelp => ("Generate Steam launch options", "生成 Steam 启动选项"),
    EmptyLibrary => ("No games listed yet", "还没有游戏列表"),
    EmptyLibraryHelp => ("Select “Scan local Steam games” to begin.", "点击“扫描本地 Steam 游戏”开始。"),
    DirectoryNotFound => ("Install folder not found", "未找到安装目录"),
    CoverAlt => ("Cover for {name}", "{name} 的封面"),
    MissingCover => ("Cover unavailable", "封面暂不可用"),
    ConfiguredHelp => ("Profiles from this computer's profiles.toml. Select one to edit it.", "这里读取本机 profiles.toml，点击条目可以继续编辑。"),
    Refresh => ("Refresh", "刷新"),
    EmptyProfiles => ("No saved profiles yet", "还没有保存过配置"),
    EmptyProfilesHelp => ("Choose a game in the library and save it to see it here.", "先到游戏库选择一个游戏，保存后会出现在这里。"),
    GameDirectory => ("Game folder", "游戏目录"),
    TargetProgram => ("Target program", "目标程序"),
    LogsHelp => ("Recent Runner logs from the logs folder help diagnose launch failures.", "显示 logs 目录下最近的 Runner 日志，便于排查启动失败。"),
    EmptyLogs => ("No logs yet", "暂无日志"),
    EmptyLogsHelp => ("Log files appear here after Runner has launched a game.", "Runner 启动过游戏后，这里会显示日志文件。"),
    EmptyLog => ("This log is empty", "日志为空"),
    Installed => ("Installed", "已安装"),
    NotInstalled => ("Not installed", "未安装"),
    UpdateNeeded => ("Update needed", "需要更新"),
    CheckFailed => ("Check failed", "检查失败"),
    Reading => ("Loading…", "正在读取……"),
    Unknown => ("Unknown", "未知"),
    SettingsHelp => ("Check the stable data folders and Runner used to launch games from Steam.", "查看稳定数据目录和 Steam 启动所需的 Runner 状态。"),
    CheckRunner => ("Check Runner", "检查 Runner"),
    RefreshPaths => ("Refresh paths", "刷新路径"),
    RunnerStatus => ("Runner status:", "Runner 状态："),
    RunnerPath => ("Runner path:", "Runner 路径："),
    BundledHash => ("Bundled checksum:", "随包摘要："),
    Working => ("Working…", "正在处理……"),
    InstallRunner => ("Install Runner", "安装 Runner"),
    RepairRunner => ("Reinstall / repair Runner", "重新安装 / 修复 Runner"),
    UserData => ("User data folder", "用户数据目录"),
    StableRunner => ("Stable Runner path", "Runner 稳定路径"),
    LogsDirectory => ("Logs folder", "日志目录"),
    BackupsDirectory => ("Backups folder", "备份目录"),
    CacheDirectory => ("Cache folder", "缓存目录"),
    EmptyPaths => ("Paths not loaded", "路径信息未加载"),
    EmptyPathsHelp => ("Select Refresh to try again.", "点击刷新重新读取。"),
    ChooseDirectory => ("Browse for the target program to select its folder.", "请浏览选择目标程序，以确定游戏目录。"),
    ConfigureTarget => ("Configure launch target", "配置启动目标"),
    CloseDialog => ("Close configuration", "关闭配置窗口"),
    ActualProgram => ("Program to start", "真正要启动的程序"),
    TargetPlaceholder => ("For example, Game_CHS.exe or launcher.exe", "例如 Game_CHS.exe 或 launcher.exe"),
    Browse => ("Browse", "浏览"),
    SaveOptions => ("Save and generate launch options", "保存并生成启动选项"),
    GenerateOptions => ("Generate launch options only", "仅生成启动选项"),
    TestLater => ("Test launch (coming later)", "测试启动（稍后实现）"),
    LaunchOptions => ("Steam launch options", "Steam 启动选项"),
    OptionsPlaceholder => ("Generated after saving the profile", "保存配置后生成"),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Message {
    Plain(Text),
    GamesFound(usize),
    Error(Text, ManagerError),
}

impl Message {
    pub fn render(&self, language: Language) -> String {
        match self {
            Self::Plain(key) => key.text(language).to_string(),
            Self::GamesFound(count) => Text::GamesFound
                .text(language)
                .replace("{count}", &count.to_string()),
            Self::Error(key, error) => {
                format!("{} {}", key.text(language), error.message(language))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn both_languages_cover_every_catalog_entry_and_keep_placeholders() {
        for key in Text::ALL {
            let en = key.text(Language::English);
            let zh = key.text(Language::SimplifiedChinese);
            assert!(!en.trim().is_empty());
            assert!(!zh.trim().is_empty());
            for placeholder in ["{count}", "{name}"] {
                assert_eq!(en.contains(placeholder), zh.contains(placeholder));
            }
        }
    }
    #[test]
    fn existing_status_and_errors_retranslate_without_altering_user_details() {
        let detail = "G:\\中文游戏\\My game.exe";
        let message = Message::Error(
            Text::SaveFailed,
            ManagerError::new(steamwrapper_manager_core::ErrorCode::ConfigRead, detail),
        );
        assert!(message
            .render(Language::English)
            .starts_with("Save failed:"));
        assert!(message
            .render(Language::SimplifiedChinese)
            .starts_with("保存失败："));
        assert!(message.render(Language::English).ends_with(detail));
        assert!(message
            .render(Language::SimplifiedChinese)
            .ends_with(detail));
        assert_eq!(
            Message::GamesFound(2).render(Language::SimplifiedChinese),
            "已找到 2 个本地 Steam 游戏"
        );
    }
}
