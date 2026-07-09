use steamwrapper_core::{
    build_launch_option, default_runner_path, ensure_app_dirs, scan_local_steam_games, LocalSteamGame,
};

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

fn main() {
    if let Err(err) = ensure_app_dirs() {
        eprintln!("failed to create SteamWrapper app directories: {err}");
    }

    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            generate_launch_option,
            get_default_runner_path,
            scan_local_steam_games_command
        ])
        .run(tauri::generate_context!())
        .expect("failed to run SteamWrapper Manager");
}
