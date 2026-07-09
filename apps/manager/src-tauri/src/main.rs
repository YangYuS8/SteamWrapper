use serde::Deserialize;
use std::path::PathBuf;
use steamwrapper_core::{
    build_launch_option, default_profiles_path, default_runner_path, ensure_app_dirs,
    scan_local_steam_games, LocalSteamGame, Platform, Profile, SteamWrapperConfig, WaitMode,
};

#[derive(Debug, Deserialize)]
struct SaveProfileRequest {
    appid: String,
    name: String,
    game_dir: String,
    target: String,
}

#[tauri::command]
fn generate_launch_option(appid: String) -> String {
    let runner_path = default_runner_path();
    build_launch_option(runner_path, &appid)
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
        wait_mode: WaitMode::Root,
        process_name: None,
    };

    config.profiles.insert(request.appid, profile);
    config.save(&profiles_path).map_err(|err| err.to_string())
}

fn main() {
    if let Err(err) = ensure_app_dirs() {
        eprintln!("failed to create SteamWrapper app directories: {err}");
    }

    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            generate_launch_option,
            get_default_runner_path,
            scan_local_steam_games_command,
            save_profile
        ])
        .run(tauri::generate_context!())
        .expect("failed to run SteamWrapper Manager");
}
