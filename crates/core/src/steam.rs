use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
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

    let libraries = find_steam_libraries(&steam_dir);
    let mut games = Vec::new();

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
            let install_dir = install_dir_name.as_deref().map(|dir| {
                steamapps
                    .join("common")
                    .join(dir)
                    .to_string_lossy()
                    .to_string()
            });
            let cover_path =
                find_local_cover(&steam_dir, &appid).map(|path| path.to_string_lossy().to_string());

            games.push(LocalSteamGame {
                appid,
                name,
                install_dir,
                cover_path,
            });
        }
    }

    games.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    games
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
    libraries.insert(steam_dir.to_path_buf());

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
            libraries.insert(PathBuf::from(path));
        }
    }

    libraries.into_iter().collect()
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
}
