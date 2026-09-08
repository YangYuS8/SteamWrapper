mod localization;
mod runner;
mod ui_settings;
pub use localization::{ErrorCode, Language, ManagerError};
pub use ui_settings::UiSettingsStore;

use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};
use steamwrapper_core::{
    app_data_dir, build_launch_option, default_profiles_path, default_runner_path, ensure_app_dirs,
    scan_local_steam_games, Platform, Profile, SteamWrapperConfig,
};

pub use runner::{
    inspect_runner, install_or_repair, RunnerInstallOutcome, RunnerPaths, RunnerStatus,
};
pub use steamwrapper_core::LocalSteamGame;

#[derive(Debug, Clone)]
pub struct ManagerPaths {
    pub app_data_dir: PathBuf,
    pub profiles_path: PathBuf,
    pub runner_path: PathBuf,
    pub logs_dir: PathBuf,
    pub backups_dir: PathBuf,
    pub cache_dir: PathBuf,
}

impl ManagerPaths {
    pub fn current() -> Self {
        Self {
            app_data_dir: app_data_dir(),
            profiles_path: default_profiles_path(),
            runner_path: default_runner_path(),
            logs_dir: app_data_dir().join("logs"),
            backups_dir: app_data_dir().join("backups"),
            cache_dir: app_data_dir().join("cache"),
        }
    }

    pub fn from_app_data_dir(app_data_dir: impl Into<PathBuf>) -> Self {
        let app_data_dir = app_data_dir.into();
        let runner_name = if cfg!(target_os = "windows") {
            "SteamWrapperRunner.exe"
        } else {
            "steamwrapper-runner"
        };
        Self {
            profiles_path: app_data_dir.join("profiles.toml"),
            runner_path: app_data_dir.join("bin").join(runner_name),
            logs_dir: app_data_dir.join("logs"),
            backups_dir: app_data_dir.join("backups"),
            cache_dir: app_data_dir.join("cache"),
            app_data_dir,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct SaveProfileRequest {
    pub appid: String,
    pub name: String,
    pub game_dir: String,
    pub target: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ConfiguredProfile {
    pub appid: String,
    pub name: String,
    pub game_dir: String,
    pub target: String,
    pub launch_option: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AppPaths {
    pub app_data_dir: String,
    pub profiles_path: String,
    pub runner_path: String,
    pub logs_dir: String,
    pub backups_dir: String,
    pub cache_dir: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RunnerLogEntry {
    pub file_name: String,
    pub path: String,
    pub content: String,
}

#[derive(Debug, Clone)]
pub struct ManagerService {
    paths: ManagerPaths,
    bundled_runner: PathBuf,
}

impl ManagerService {
    pub fn new(bundled_runner: impl Into<PathBuf>) -> Self {
        Self::with_paths(ManagerPaths::current(), bundled_runner)
    }

    pub fn with_paths(paths: ManagerPaths, bundled_runner: impl Into<PathBuf>) -> Self {
        Self {
            paths,
            bundled_runner: bundled_runner.into(),
        }
    }

    pub fn paths(&self) -> &ManagerPaths {
        &self.paths
    }

    pub fn prepare(&self) -> Result<(), ManagerError> {
        if self.paths.app_data_dir == app_data_dir() {
            ensure_app_dirs()?;
        } else {
            let runner_dir = self.paths.runner_path.parent().ok_or_else(|| {
                ManagerError::new(
                    ErrorCode::InvalidRunnerPath,
                    self.paths.runner_path.display(),
                )
            })?;
            fs::create_dir_all(runner_dir)?;
            fs::create_dir_all(&self.paths.logs_dir)?;
            fs::create_dir_all(&self.paths.backups_dir)?;
            fs::create_dir_all(&self.paths.cache_dir)?;
        }
        Ok(())
    }

    pub fn runner_paths(&self) -> RunnerPaths {
        RunnerPaths::new(&self.bundled_runner, &self.paths.runner_path)
    }

    pub fn runner_status(&self) -> Result<RunnerStatus, ManagerError> {
        self.prepare()?;
        Ok(inspect_runner(&self.runner_paths()))
    }

    pub fn install_runner(&self) -> Result<RunnerInstallOutcome, ManagerError> {
        self.prepare()?;
        install_or_repair(&self.runner_paths())
    }

    pub fn generate_launch_option(&self, appid: &str) -> Result<String, ManagerError> {
        let status = self.runner_status()?;
        if !status.healthy {
            return Err(status
                .last_error
                .unwrap_or_else(|| ManagerError::new(ErrorCode::RunnerUnavailable, "")));
        }
        Ok(build_launch_option(&self.paths.runner_path, appid))
    }

    pub fn scan_local_steam_games(&self) -> Vec<LocalSteamGame> {
        scan_local_steam_games()
    }

    pub fn list_profiles(&self) -> Result<Vec<ConfiguredProfile>, ManagerError> {
        if !self.paths.profiles_path.exists() {
            return Ok(Vec::new());
        }

        let runner_healthy = self
            .runner_status()
            .map(|status| status.healthy)
            .unwrap_or(false);
        let config =
            SteamWrapperConfig::load(&self.paths.profiles_path).map_err(ManagerError::from)?;
        let mut profiles: Vec<ConfiguredProfile> = config
            .profiles
            .into_iter()
            .map(|(appid, profile)| ConfiguredProfile {
                launch_option: if runner_healthy {
                    build_launch_option(&self.paths.runner_path, &appid)
                } else {
                    String::new()
                },
                appid,
                name: profile.name,
                game_dir: profile.game_dir.to_string_lossy().to_string(),
                target: profile.target.to_string_lossy().to_string(),
            })
            .collect();
        profiles.sort_by_key(|profile| profile.name.to_lowercase());
        Ok(profiles)
    }

    pub fn app_paths(&self) -> Result<AppPaths, ManagerError> {
        self.prepare()?;
        Ok(AppPaths {
            app_data_dir: self.paths.app_data_dir.to_string_lossy().to_string(),
            profiles_path: self.paths.profiles_path.to_string_lossy().to_string(),
            runner_path: self.paths.runner_path.to_string_lossy().to_string(),
            logs_dir: self.paths.logs_dir.to_string_lossy().to_string(),
            backups_dir: self.paths.backups_dir.to_string_lossy().to_string(),
            cache_dir: self.paths.cache_dir.to_string_lossy().to_string(),
        })
    }

    pub fn list_runner_logs(&self) -> Result<Vec<RunnerLogEntry>, ManagerError> {
        self.prepare()?;
        let mut logs = Vec::new();
        let entries = fs::read_dir(&self.paths.logs_dir)
            .map_err(|err| ManagerError::new(ErrorCode::LogsRead, err))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("log") {
                continue;
            }
            let Ok(content) = fs::read_to_string(&path) else {
                continue;
            };
            let lines: Vec<&str> = content.lines().rev().take(80).collect();
            let content = lines.into_iter().rev().collect::<Vec<_>>().join("\n");
            logs.push(RunnerLogEntry {
                file_name: path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or("runner.log")
                    .to_string(),
                path: path.to_string_lossy().to_string(),
                content,
            });
        }

        logs.sort_by(|a, b| a.file_name.cmp(&b.file_name));
        Ok(logs)
    }

    pub fn save_profile(&self, request: SaveProfileRequest) -> Result<(), ManagerError> {
        self.prepare()?;
        let mut config = if self.paths.profiles_path.exists() {
            SteamWrapperConfig::load(&self.paths.profiles_path).map_err(ManagerError::from)?
        } else {
            SteamWrapperConfig::default()
        };

        let platform = current_platform();
        let profile = Profile {
            name: request.name,
            app_id: Some(request.appid.clone()),
            platform: Some(platform),
            game_dir: PathBuf::from(request.game_dir),
            target: PathBuf::from(request.target),
            working_dir: Some(PathBuf::from(".")),
            args: Vec::new(),
            wait_mode: platform.default_wait_mode(),
            process_name: None,
        };
        config.profiles.insert(request.appid, profile);
        config
            .save(&self.paths.profiles_path)
            .map_err(ManagerError::from)
    }
}

fn current_platform() -> Platform {
    if cfg!(target_os = "windows") {
        Platform::Windows
    } else if cfg!(target_os = "linux") {
        Platform::Linux
    } else {
        Platform::SteamOs
    }
}
