use serde::Serialize;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Language {
    #[default]
    English,
    SimplifiedChinese,
}

impl Language {
    pub fn parse(value: &str) -> Self {
        match value.trim().to_ascii_lowercase().as_str() {
            "zh-cn" | "zh-hans" => Self::SimplifiedChinese,
            _ => Self::English,
        }
    }

    pub fn tag(self) -> &'static str {
        match self {
            Self::English => "en-US",
            Self::SimplifiedChinese => "zh-CN",
        }
    }
}

macro_rules! errors {
    ($($key:ident => ($en:literal, $zh:literal)),+ $(,)?) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
        pub enum ErrorCode { $($key),+ }
        impl ErrorCode {
            pub fn text(self, language: Language) -> &'static str {
                match (self, language) {
                    $((Self::$key, Language::English) => $en,
                      (Self::$key, Language::SimplifiedChinese) => $zh),+
                }
            }
        }
    };
}

errors! {
    PrepareDirectories => ("Could not prepare the data folders.", "无法准备数据目录。"),
    InvalidRunnerPath => ("The stable Runner path has no parent folder.", "Runner 稳定路径没有父目录。"),
    BundledRunnerRead => ("Could not read the bundled Runner.", "无法读取随包 Runner。"),
    InstalledRunnerRead => ("Could not inspect the installed Runner.", "无法检查已安装的 Runner。"),
    RunnerUnavailable => ("Install or repair Runner in Settings first.", "请先在设置中安装或修复 Runner。"),
    RunnerInstall => ("Could not install or repair Runner.", "无法安装或修复 Runner。"),
    RunnerVerification => ("Runner verification failed after installation.", "Runner 安装后校验失败。"),
    ConfigRead => ("Could not read the profile file.", "无法读取游戏配置文件。"),
    ConfigParse => ("The profile file contains invalid TOML.", "游戏配置文件的 TOML 格式无效。"),
    ConfigSerialize => ("Could not serialize the profile file.", "无法序列化游戏配置文件。"),
    ProfileMissing => ("No profile was found for this AppID.", "未找到此 AppID 的配置。"),
    LogsRead => ("Could not read the log folder.", "无法读取日志目录。"),
    ResourceMissing => ("Could not locate the bundled Runner in the checked resource folder.", "在已检查的资源目录中找不到随包 Runner。"),
    ExecutableRead => ("Could not read the Manager executable path.", "无法读取 Manager 程序路径。"),
    ExecutableParent => ("The Manager executable path has no parent folder.", "Manager 程序路径没有父目录。"),
    SettingsRead => ("Could not read the UI settings file. Its contents have been preserved.", "无法读取界面设置文件，原文件已保留。"),
    SettingsInvalid => ("The UI settings file is not a valid JSON object. It has been preserved; repair it before saving a language preference.", "界面设置文件不是有效的 JSON 对象。原文件已保留，请修复后再保存语言偏好。"),
    SettingsTooLarge => ("The UI settings file exceeds the 64 KiB limit. Its contents have been preserved.", "界面设置文件超过 64 KiB 大小限制，原文件已保留。"),
    SettingsWrite => ("Could not save the language preference. The previous preference has been preserved.", "无法保存语言偏好，原有偏好已保留。"),
}

/// Keep application-owned explanations separate from paths and diagnostic details.
/// The UI can change language without translating user data or parsing error strings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ManagerError {
    pub code: ErrorCode,
    pub detail: String,
}

impl ManagerError {
    pub fn new(code: ErrorCode, detail: impl ToString) -> Self {
        Self {
            code,
            detail: detail.to_string(),
        }
    }
    pub fn message(&self, language: Language) -> String {
        let explanation = self.code.text(language);
        if self.detail.is_empty() {
            explanation.to_string()
        } else {
            format!("{explanation} {}", self.detail)
        }
    }
}

impl std::fmt::Display for ManagerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message(Language::English))
    }
}
impl std::error::Error for ManagerError {}
impl From<std::io::Error> for ManagerError {
    fn from(error: std::io::Error) -> Self {
        Self::new(ErrorCode::PrepareDirectories, error)
    }
}
impl From<steamwrapper_core::ConfigError> for ManagerError {
    fn from(error: steamwrapper_core::ConfigError) -> Self {
        use steamwrapper_core::ConfigError;
        match error {
            ConfigError::Read(error) => Self::new(ErrorCode::ConfigRead, error),
            ConfigError::Parse(error) => Self::new(ErrorCode::ConfigParse, error),
            ConfigError::Serialize(error) => Self::new(ErrorCode::ConfigSerialize, error),
            ConfigError::ProfileNotFound(appid) => Self::new(ErrorCode::ProfileMissing, appid),
        }
    }
}
