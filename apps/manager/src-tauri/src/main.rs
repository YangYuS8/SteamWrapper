mod runner_manager;

use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};
use steamwrapper_core::{
    app_data_dir, build_launch_option, default_profiles_path, default_runner_path, ensure_app_dirs,
    scan_local_steam_games, LocalSteamGame, Platform, Profile, SteamWrapperConfig,
};
use tauri::{path::BaseDirectory, Manager};

#[derive(Debug, Deserialize)]
struct SaveProfileRequest {
    appid: String,
    name: String,
    game_dir: String,
    target: String,
}

#[derive(Debug, Serialize)]
struct ConfiguredProfile {
    appid: String,
    name: String,
    game_dir: String,
    target: String,
    launch_option: String,
}

#[derive(Debug, Serialize)]
struct AppPaths {
    app_data_dir: String,
    profiles_path: String,
    runner_path: String,
    logs_dir: String,
    backups_dir: String,
    cache_dir: String,
}

#[derive(Debug, Serialize)]
struct RunnerLogEntry {
    file_name: String,
    path: String,
    content: String,
}

fn bundled_runner_paths(app: &tauri::AppHandle) -> Result<runner_manager::RunnerPaths, String> {
    let runner_name = if cfg!(target_os = "windows") {
        "SteamWrapperRunner.exe"
    } else {
        "steamwrapper-runner"
    };
    let bundled = app
        .path()
        .resolve(format!("runner/{runner_name}"), BaseDirectory::Resource)
        .map_err(|err| format!("无法定位随包 Runner 资源：{err}"))?;

    Ok(runner_manager::RunnerPaths::new(
        bundled,
        default_runner_path(),
    ))
}

#[tauri::command]
fn get_runner_status(app: tauri::AppHandle) -> Result<runner_manager::RunnerStatus, String> {
    ensure_app_dirs().map_err(|err| err.to_string())?;
    let paths = bundled_runner_paths(&app)?;
    Ok(runner_manager::inspect_runner(&paths))
}

#[tauri::command]
fn install_runner(app: tauri::AppHandle) -> Result<runner_manager::RunnerInstallOutcome, String> {
    ensure_app_dirs().map_err(|err| err.to_string())?;
    let paths = bundled_runner_paths(&app)?;
    runner_manager::install_or_repair(&paths)
}

#[tauri::command]
fn repair_runner(app: tauri::AppHandle) -> Result<runner_manager::RunnerInstallOutcome, String> {
    install_runner(app)
}

#[tauri::command]
fn generate_launch_option(app: tauri::AppHandle, appid: String) -> Result<String, String> {
    let paths = bundled_runner_paths(&app)?;
    let status = runner_manager::inspect_runner(&paths);
    if !status.healthy {
        return Err(status
            .last_error
            .unwrap_or_else(|| "Runner 尚未安装或需要修复，请先在设置页完成安装。".to_string()));
    }

    Ok(build_launch_option(default_runner_path(), &appid))
}

#[tauri::command]
fn get_default_runner_path() -> String {
    default_runner_path().to_string_lossy().to_string()
}

#[tauri::command]
fn scan_local_steam_games_command() -> Vec<LocalSteamGame> {
    scan_local_steam_games()
}

#[tauri::command]
fn list_profiles(app: tauri::AppHandle) -> Result<Vec<ConfiguredProfile>, String> {
    let profiles_path = default_profiles_path();
    if !profiles_path.exists() {
        return Ok(Vec::new());
    }

    let runner_healthy = bundled_runner_paths(&app)
        .map(|paths| runner_manager::inspect_runner(&paths).healthy)
        .unwrap_or(false);
    let config = SteamWrapperConfig::load(&profiles_path).map_err(|err| err.to_string())?;
    let mut profiles: Vec<ConfiguredProfile> = config
        .profiles
        .into_iter()
        .map(|(appid, profile)| ConfiguredProfile {
            launch_option: runner_healthy
                .then(|| build_launch_option(default_runner_path(), &appid))
                .unwrap_or_default(),
            appid,
            name: profile.name,
            game_dir: profile.game_dir.to_string_lossy().to_string(),
            target: profile.target.to_string_lossy().to_string(),
        })
        .collect();

    profiles.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(profiles)
}

#[tauri::command]
fn get_app_paths() -> Result<AppPaths, String> {
    ensure_app_dirs().map_err(|err| err.to_string())?;

    let app_data_dir = app_data_dir();
    Ok(AppPaths {
        app_data_dir: app_data_dir.to_string_lossy().to_string(),
        profiles_path: default_profiles_path().to_string_lossy().to_string(),
        runner_path: default_runner_path().to_string_lossy().to_string(),
        logs_dir: app_data_dir.join("logs").to_string_lossy().to_string(),
        backups_dir: app_data_dir.join("backups").to_string_lossy().to_string(),
        cache_dir: app_data_dir.join("cache").to_string_lossy().to_string(),
    })
}

#[tauri::command]
fn list_runner_logs() -> Result<Vec<RunnerLogEntry>, String> {
    ensure_app_dirs().map_err(|err| err.to_string())?;

    let logs_dir = app_data_dir().join("logs");
    let mut logs = Vec::new();
    let entries = fs::read_dir(&logs_dir).map_err(|err| err.to_string())?;

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

#[tauri::command]
fn save_profile(request: SaveProfileRequest) -> Result<(), String> {
    ensure_app_dirs().map_err(|err| err.to_string())?;

    let profiles_path = default_profiles_path();
    let mut config = if profiles_path.exists() {
        SteamWrapperConfig::load(&profiles_path).map_err(|err| err.to_string())?
    } else {
        SteamWrapperConfig::default()
    };

    let platform = if cfg!(target_os = "windows") {
        Platform::Windows
    } else if cfg!(target_os = "linux") {
        Platform::Linux
    } else {
        Platform::SteamOs
    };

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
    config.save(&profiles_path).map_err(|err| err.to_string())
}

fn main() {
    if let Err(err) = ensure_app_dirs() {
        eprintln!("failed to create SteamWrapper app directories: {err}");
    }

    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            if let Err(err) = ensure_app_dirs() {
                eprintln!("failed to create SteamWrapper app directories: {err}");
                return Ok(());
            }

            let result = bundled_runner_paths(&app.handle())
                .and_then(|paths| runner_manager::install_or_repair(&paths).map(|_| ()));
            if let Err(err) = result {
                eprintln!("failed to install SteamWrapper Runner: {err}");
            }
            Ok(())
        });

    #[cfg(feature = "e2e")]
    let builder = builder
        .plugin(tauri_plugin_wdio::init())
        .plugin(tauri_plugin_wdio_webdriver::init());

    builder
        .invoke_handler(tauri::generate_handler![
            generate_launch_option,
            get_default_runner_path,
            get_app_paths,
            get_runner_status,
            install_runner,
            list_profiles,
            list_runner_logs,
            repair_runner,
            scan_local_steam_games_command,
            save_profile
        ])
        .run(tauri::generate_context!())
        .expect("failed to run SteamWrapper Manager");
}
