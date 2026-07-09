use serde::Serialize;
use steamwrapper_core::build_launch_option;

#[derive(Debug, Serialize)]
struct LocalSteamGame {
    appid: String,
    name: String,
    install_dir: Option<String>,
    cover_path: Option<String>,
}

#[tauri::command]
fn generate_launch_option(runner_path: String, appid: String) -> String {
    build_launch_option(runner_path, &appid)
}

#[tauri::command]
fn scan_local_steam_games() -> Vec<LocalSteamGame> {
    // Skeleton only. The real implementation will:
    // 1. find the Steam installation directory;
    // 2. read libraryfolders.vdf;
    // 3. parse steamapps/appmanifest_<appid>.acf;
    // 4. resolve local cover images from Steam cache;
    // 5. never fetch remote cover images in the first version.
    Vec::new()
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            generate_launch_option,
            scan_local_steam_games
        ])
        .run(tauri::generate_context!())
        .expect("failed to run SteamWrapper Manager");
}
