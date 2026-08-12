use std::{env, path::PathBuf, sync::OnceLock};

use steamwrapper_manager_core::{
    AppPaths, ConfiguredProfile, LocalSteamGame, ManagerPaths, ManagerService,
    RunnerInstallOutcome, RunnerLogEntry, RunnerStatus, SaveProfileRequest,
};

const RUNNER_RESOURCE_DIR: &str = "resources/runner";

pub fn manager_service() -> Result<&'static ManagerService, String> {
    static SERVICE: OnceLock<Result<ManagerService, String>> = OnceLock::new();
    SERVICE
        .get_or_init(build_manager_service)
        .as_ref()
        .map_err(Clone::clone)
}

pub fn bootstrap() -> Result<(), String> {
    manager_service()?
        .install_runner()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

pub fn selected_path(files: Vec<dioxus::html::FileData>) -> Option<String> {
    files
        .into_iter()
        .next()
        .map(|file| file.path().to_string_lossy().to_string())
}

pub fn scan_games() -> Result<Vec<LocalSteamGame>, String> {
    Ok(manager_service()?.scan_local_steam_games())
}

pub fn list_profiles() -> Result<Vec<ConfiguredProfile>, String> {
    manager_service()?
        .list_profiles()
        .map_err(|error| error.to_string())
}

pub fn list_logs() -> Result<Vec<RunnerLogEntry>, String> {
    manager_service()?
        .list_runner_logs()
        .map_err(|error| error.to_string())
}

pub fn paths() -> Result<AppPaths, String> {
    manager_service()?
        .app_paths()
        .map_err(|error| error.to_string())
}

pub fn runner_status() -> Result<RunnerStatus, String> {
    manager_service()?
        .runner_status()
        .map_err(|error| error.to_string())
}

pub fn install_runner() -> Result<RunnerInstallOutcome, String> {
    manager_service()?
        .install_runner()
        .map_err(|error| error.to_string())
}

pub fn generate_launch_option(appid: &str) -> Result<String, String> {
    manager_service()?
        .generate_launch_option(appid)
        .map_err(|error| error.to_string())
}

pub fn save_profile(request: SaveProfileRequest) -> Result<(), String> {
    manager_service()?
        .save_profile(request)
        .map_err(|error| error.to_string())
}

fn build_manager_service() -> Result<ManagerService, String> {
    let bundled_runner = bundled_runner_path()?;
    let paths = match env::var_os("STEAMWRAPPER_E2E_ROOT") {
        Some(root) => ManagerPaths::from_app_data_dir(PathBuf::from(root).join(if cfg!(windows) {
            "local-app-data/SteamWrapper"
        } else {
            "xdg-data/SteamWrapper"
        })),
        None => ManagerPaths::current(),
    };
    let service = ManagerService::with_paths(paths, bundled_runner);
    service.prepare().map_err(|error| error.to_string())?;
    Ok(service)
}

fn bundled_runner_path() -> Result<PathBuf, String> {
    let runner_name = runner_name_for_current_platform();
    let resource_root = executable_resource_root()?;

    for path in [
        resource_root.join(runner_name),
        resource_root.join(RUNNER_RESOURCE_DIR).join(runner_name),
    ] {
        if path.is_file() {
            return Ok(path);
        }
    }

    #[cfg(debug_assertions)]
    {
        let source_resource = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join(RUNNER_RESOURCE_DIR)
            .join(runner_name);
        if source_resource.is_file() {
            return Ok(source_resource);
        }
    }

    Err(format!(
        "无法定位随包 Runner 资源；已检查 {}",
        resource_root.display()
    ))
}

fn executable_resource_root() -> Result<PathBuf, String> {
    if let Some(root) = env::var_os("STEAMWRAPPER_BUNDLED_RESOURCE_ROOT") {
        return Ok(PathBuf::from(root));
    }

    let executable =
        env::current_exe().map_err(|error| format!("无法读取 Manager 路径：{error}"))?;
    let executable_dir = executable
        .parent()
        .ok_or_else(|| format!("Manager 路径没有父目录：{}", executable.display()))?;

    #[cfg(target_os = "linux")]
    {
        if let Some(lib_dir) = executable_dir.parent().map(|prefix| prefix.join("lib")) {
            if let Ok(entries) = std::fs::read_dir(&lib_dir) {
                for entry in entries.flatten() {
                    let candidate = entry.path();
                    if candidate.is_dir()
                        && candidate.join(runner_name_for_current_platform()).is_file()
                    {
                        return Ok(candidate);
                    }
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        if let Some(root) = executable_dir
            .parent()
            .and_then(Path::parent)
            .map(|contents| contents.join("Resources"))
            .filter(|path| path.is_dir())
        {
            return Ok(root);
        }
    }

    Ok(executable_dir.to_path_buf())
}

fn runner_name_for_current_platform() -> &'static str {
    if cfg!(target_os = "windows") {
        "SteamWrapperRunner.exe"
    } else {
        "steamwrapper-runner"
    }
}

#[cfg(test)]
mod tests {
    use super::selected_path;

    #[test]
    fn selected_path_is_empty_without_a_native_file_selection() {
        assert!(selected_path(Vec::new()).is_none());
    }
}
