use std::{env, path::PathBuf, sync::OnceLock};

use steamwrapper_manager_core::{
    AppPaths, ConfiguredProfile, ErrorCode, Language, LocalSteamGame, ManagerError, ManagerPaths,
    ManagerService, RunnerInstallOutcome, RunnerLogEntry, RunnerStatus, SaveProfileRequest,
    UiSettingsStore,
};

const RUNNER_RESOURCE_DIR: &str = "resources/runner";

pub fn manager_service() -> Result<&'static ManagerService, ManagerError> {
    static SERVICE: OnceLock<Result<ManagerService, ManagerError>> = OnceLock::new();
    SERVICE
        .get_or_init(build_manager_service)
        .as_ref()
        .map_err(Clone::clone)
}

pub fn bootstrap() -> Result<(), ManagerError> {
    manager_service()?.install_runner().map(|_| ())
}

pub fn selected_path(files: Vec<dioxus::html::FileData>) -> Option<String> {
    files
        .into_iter()
        .next()
        .map(|file| file.path().to_string_lossy().to_string())
}

pub fn scan_games() -> Result<Vec<LocalSteamGame>, ManagerError> {
    Ok(manager_service()?.scan_local_steam_games())
}

pub fn list_profiles() -> Result<Vec<ConfiguredProfile>, ManagerError> {
    manager_service()?.list_profiles()
}

pub fn list_logs() -> Result<Vec<RunnerLogEntry>, ManagerError> {
    manager_service()?.list_runner_logs()
}

pub fn paths() -> Result<AppPaths, ManagerError> {
    manager_service()?.app_paths()
}

pub fn runner_status() -> Result<RunnerStatus, ManagerError> {
    manager_service()?.runner_status()
}

pub fn install_runner() -> Result<RunnerInstallOutcome, ManagerError> {
    manager_service()?.install_runner()
}

pub fn generate_launch_option(appid: &str) -> Result<String, ManagerError> {
    manager_service()?.generate_launch_option(appid)
}

pub fn save_profile(request: SaveProfileRequest) -> Result<(), ManagerError> {
    manager_service()?.save_profile(request)
}

fn data_paths() -> ManagerPaths {
    match env::var_os("STEAMWRAPPER_E2E_ROOT") {
        Some(root) => ManagerPaths::from_app_data_dir(PathBuf::from(root).join(if cfg!(windows) {
            "local-app-data/SteamWrapper"
        } else {
            "xdg-data/SteamWrapper"
        })),
        None => ManagerPaths::current(),
    }
}

pub fn load_language() -> Result<Language, ManagerError> {
    UiSettingsStore::new(data_paths().app_data_dir).load_language()
}

pub fn save_language(language: Language) -> Result<(), ManagerError> {
    UiSettingsStore::new(data_paths().app_data_dir).save_language(language)
}

fn build_manager_service() -> Result<ManagerService, ManagerError> {
    let bundled_runner = bundled_runner_path()?;
    let service = ManagerService::with_paths(data_paths(), bundled_runner);
    service.prepare()?;
    Ok(service)
}

fn bundled_runner_path() -> Result<PathBuf, ManagerError> {
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

    Err(ManagerError::new(
        ErrorCode::ResourceMissing,
        resource_root.display(),
    ))
}

fn executable_resource_root() -> Result<PathBuf, ManagerError> {
    if let Some(root) = env::var_os("STEAMWRAPPER_BUNDLED_RESOURCE_ROOT") {
        return Ok(PathBuf::from(root));
    }

    let executable =
        env::current_exe().map_err(|error| ManagerError::new(ErrorCode::ExecutableRead, error))?;
    let executable_dir = executable
        .parent()
        .ok_or_else(|| ManagerError::new(ErrorCode::ExecutableParent, executable.display()))?;

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
            .and_then(std::path::Path::parent)
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
