use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    Windows,
    Linux,
    SteamOs,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WaitMode {
    /// Wait for only the directly started target process.
    Root,
    /// Windows-first plan: wait for the full process group through Job Object.
    Job,
    /// Wait for a specific process name after the launcher starts it.
    ProcessName,
    /// Linux/SteamOS plan: wait for the process group/session.
    ProcessGroup,
    /// Start the target and exit immediately.
    None,
}

impl Default for WaitMode {
    fn default() -> Self {
        Self::Root
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub name: String,
    #[serde(default)]
    pub app_id: Option<String>,
    #[serde(default)]
    pub platform: Option<Platform>,
    pub game_dir: PathBuf,
    pub target: PathBuf,
    #[serde(default)]
    pub working_dir: Option<PathBuf>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub wait_mode: WaitMode,
    #[serde(default)]
    pub process_name: Option<String>,
}

impl Profile {
    pub fn resolve_target(&self) -> PathBuf {
        if self.target.is_absolute() {
            self.target.clone()
        } else {
            self.game_dir.join(&self.target)
        }
    }

    pub fn resolve_working_dir(&self) -> PathBuf {
        match &self.working_dir {
            Some(path) if path.is_absolute() => path.clone(),
            Some(path) => self.game_dir.join(path),
            None => self.game_dir.clone(),
        }
    }
}
