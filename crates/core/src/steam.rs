use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LocalSteamGame {
    pub appid: String,
    pub name: String,
    pub install_dir: Option<String>,
    pub cover_path: Option<String>,
}

pub fn scan_local_steam_games() -> Vec<LocalSteamGame> {
    let Some(steam_dir) = find_steam_dir() else {
        return Vec::new();
    };

    scan_steam_games_in(&steam_dir)
}

fn scan_steam_games_in(steam_dir: &Path) -> Vec<LocalSteamGame> {
    let libraries = find_steam_libraries(&steam_dir);
    let mut games = BTreeMap::new();

    for library in libraries {
        let steamapps = library.join("steamapps");
        let Ok(entries) = fs::read_dir(&steamapps) else {
            continue;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let Some(file_name) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };

            if !file_name.starts_with("appmanifest_") || !file_name.ends_with(".acf") {
                continue;
            }

            let Ok(text) = fs::read_to_string(&path) else {
                continue;
            };

            let appid = parse_vdf_value(&text, "appid")
                .or_else(|| appid_from_manifest_name(file_name))
                .unwrap_or_default();

            if appid.is_empty() {
                continue;
            }

            let name =
                parse_vdf_value(&text, "name").unwrap_or_else(|| format!("Steam App {appid}"));
            let install_dir_name = parse_vdf_value(&text, "installdir");

            if is_non_game_steam_app(&appid, &name, install_dir_name.as_deref()) {
                continue;
            }

            let install_dir = install_dir_name.as_deref().map(|dir| {
                steamapps
                    .join("common")
                    .join(dir)
                    .to_string_lossy()
                    .to_string()
            });
            let cover_path = find_local_cover(&steam_dir, &appid)
                .map(|path| path.to_string_lossy().to_string())
                .or_else(|| official_steam_cover_url(&appid));

            let game = LocalSteamGame {
                appid: appid.clone(),
                name,
                install_dir,
                cover_path,
            };

            games
                .entry(appid)
                .and_modify(|existing| merge_game_metadata(existing, &game))
                .or_insert(game);
        }
    }

    let mut games: Vec<LocalSteamGame> = games.into_values().collect();
    games.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    games
}

fn merge_game_metadata(existing: &mut LocalSteamGame, candidate: &LocalSteamGame) {
    if existing.install_dir.is_none() && candidate.install_dir.is_some() {
        existing.install_dir.clone_from(&candidate.install_dir);
    }

    if existing.cover_path.is_none() && candidate.cover_path.is_some() {
        existing.cover_path.clone_from(&candidate.cover_path);
    }
}

fn is_non_game_steam_app(appid: &str, name: &str, install_dir: Option<&str>) -> bool {
    let normalized_name = name.to_ascii_lowercase();
    let normalized_install_dir = install_dir.unwrap_or_default().to_ascii_lowercase();

    appid == "228980"
        || normalized_name == "steamworks common redistributables"
        || normalized_name.starts_with("proton ")
        || normalized_name == "proton experimental"
        || normalized_name.starts_with("steam linux runtime")
        || normalized_install_dir.starts_with("proton ")
        || normalized_install_dir.starts_with("steamlinuxruntime")
}

fn find_steam_dir() -> Option<PathBuf> {
    if let Some(path) = env::var_os("STEAM_DIR").map(PathBuf::from) {
        if path.exists() {
            return Some(path);
        }
    }

    let mut candidates = Vec::new();

    #[cfg(target_os = "windows")]
    {
        if let Some(program_files_x86) = env::var_os("ProgramFiles(x86)") {
            candidates.push(PathBuf::from(program_files_x86).join("Steam"));
        }
        if let Some(program_files) = env::var_os("ProgramFiles") {
            candidates.push(PathBuf::from(program_files).join("Steam"));
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        if let Some(home) = env::var_os("HOME") {
            let home = PathBuf::from(home);
            candidates.push(home.join(".steam").join("steam"));
            candidates.push(home.join(".local").join("share").join("Steam"));
        }
    }

    candidates.into_iter().find(|path| path.exists())
}

fn find_steam_libraries(steam_dir: &Path) -> Vec<PathBuf> {
    let mut libraries = BTreeSet::new();
    libraries.insert(normalize_existing_path(steam_dir));

    let libraryfolders = steam_dir.join("steamapps").join("libraryfolders.vdf");
    let Ok(text) = fs::read_to_string(libraryfolders) else {
        return libraries.into_iter().collect();
    };

    for line in text.lines() {
        if !line.contains("\"path\"") {
            continue;
        }

        if let Some(path) = parse_quoted_value_after_key(line, "path") {
            let path = path.replace("\\\\", "\\");
            libraries.insert(normalize_existing_path(Path::new(&path)));
        }
    }

    libraries.into_iter().collect()
}

fn normalize_existing_path(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn parse_vdf_value(text: &str, key: &str) -> Option<String> {
    text.lines()
        .find(|line| line.trim_start().starts_with(&format!("\"{key}\"")))
        .and_then(|line| parse_quoted_value_after_key(line, key))
}

fn parse_quoted_value_after_key(line: &str, key: &str) -> Option<String> {
    let marker = format!("\"{key}\"");
    let start = line.find(&marker)? + marker.len();
    let rest = &line[start..];
    let first_quote = rest.find('"')? + 1;
    let value_start = start + first_quote;
    let value_rest = &line[value_start..];
    let value_end = value_rest.find('"')?;
    Some(value_rest[..value_end].to_string())
}

fn appid_from_manifest_name(file_name: &str) -> Option<String> {
    file_name
        .strip_prefix("appmanifest_")
        .and_then(|name| name.strip_suffix(".acf"))
        .map(ToOwned::to_owned)
}

fn find_local_cover(steam_dir: &Path, appid: &str) -> Option<PathBuf> {
    let mut roots = vec![steam_dir.join("appcache").join("librarycache")];

    let userdata = steam_dir.join("userdata");
    if let Ok(users) = fs::read_dir(userdata) {
        for user in users.flatten() {
            roots.push(user.path().join("config").join("grid"));
        }
    }

    let preferred = [
        format!("{appid}_library_600x900"),
        format!("{appid}_header"),
        format!("{appid}_library_hero"),
        appid.to_string(),
    ];

    for root in roots {
        let Ok(entries) = fs::read_dir(root) else {
            continue;
        };

        let files: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
        for prefix in &preferred {
            if let Some(path) = files
                .iter()
                .find(|path| file_stem_starts_with(path, prefix))
            {
                return Some(path.clone());
            }
        }
    }

    None
}

fn official_steam_cover_url(appid: &str) -> Option<String> {
    (!appid.is_empty() && appid.chars().all(|character| character.is_ascii_digit())).then(|| {
        format!("https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg")
    })
}

fn file_stem_starts_with(path: &Path, prefix: &str) -> bool {
    let Some(ext) = path.extension().and_then(|ext| ext.to_str()) else {
        return false;
    };

    if !matches!(
        ext.to_ascii_lowercase().as_str(),
        "jpg" | "jpeg" | "png" | "webp"
    ) {
        return false;
    }

    path.file_stem()
        .and_then(|stem| stem.to_str())
        .is_some_and(|stem| stem.starts_with(prefix))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parses_vdf_value() {
        let text = r#""appid" "123456"
"name" "Example Game"
"installdir" "Example""#;

        assert_eq!(parse_vdf_value(text, "appid"), Some("123456".to_string()));
        assert_eq!(
            parse_vdf_value(text, "name"),
            Some("Example Game".to_string())
        );
    }

    #[test]
    fn falls_back_to_the_official_steam_cdn_when_no_local_cover_exists() {
        let temp_dir = unique_temp_dir();
        let steamapps = temp_dir.join("steamapps");
        fs::create_dir_all(steamapps.join("common")).unwrap();
        write_manifest(&steamapps, "123456", "Example Game", "Example Game");

        let games = scan_steam_games_in(&temp_dir);

        assert_eq!(games.len(), 1);
        assert_eq!(
            games[0].cover_path.as_deref(),
            Some("https://cdn.cloudflare.steamstatic.com/steam/apps/123456/library_600x900.jpg")
        );

        fs::remove_dir_all(temp_dir).unwrap();
    }

    #[test]
    fn does_not_generate_a_cdn_cover_for_an_empty_or_non_numeric_appid() {
        assert_eq!(official_steam_cover_url(""), None);
        assert_eq!(official_steam_cover_url("manual-123"), None);
    }

    #[test]
    fn filters_runtime_tools_and_deduplicates_games() {
        let temp_dir = unique_temp_dir();
        let steamapps = temp_dir.join("steamapps");
        let common = steamapps.join("common");
        fs::create_dir_all(&common).unwrap();

        fs::write(
            steamapps.join("libraryfolders.vdf"),
            format!(
                r#""libraryfolders"
{{
    "0"
    {{
        "path" "{}"
    }}
}}"#,
                temp_dir.display()
            ),
        )
        .unwrap();

        write_manifest(
            &steamapps,
            "228980",
            "Steamworks Common Redistributables",
            "Steamworks Shared",
        );
        write_manifest(
            &steamapps,
            "1493710",
            "Proton Experimental",
            "Proton - Experimental",
        );
        write_manifest(
            &steamapps,
            "1070560",
            "Steam Linux Runtime 1.0 (scout)",
            "SteamLinuxRuntime",
        );
        write_manifest(&steamapps, "123456", "Example Game", "Example Game");

        let games = scan_steam_games_in(&temp_dir);

        assert_eq!(games.len(), 1);
        assert_eq!(games[0].appid, "123456");
        assert_eq!(games[0].name, "Example Game");

        fs::remove_dir_all(temp_dir).unwrap();
    }

    fn write_manifest(steamapps: &Path, appid: &str, name: &str, install_dir: &str) {
        fs::write(
            steamapps.join(format!("appmanifest_{appid}.acf")),
            format!(
                r#""AppState"
{{
    "appid" "{appid}"
    "name" "{name}"
    "installdir" "{install_dir}"
    "StateFlags" "4"
}}"#
            ),
        )
        .unwrap();
    }

    fn unique_temp_dir() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("steamwrapper-test-{nanos}"))
    }
}
