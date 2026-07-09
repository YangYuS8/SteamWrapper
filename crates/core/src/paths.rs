use std::env;
use std::fs;
use std::path::PathBuf;

pub fn app_data_dir() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        if let Some(local_app_data) = env::var_os("LOCALAPPDATA") {
            return PathBuf::from(local_app_data).join("SteamWrapper");
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        if let Some(xdg_data_home) = env::var_os("XDG_DATA_HOME") {
            return PathBuf::from(xdg_data_home).join("SteamWrapper");
        }

        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home)
                .join(".local")
                .join("share")
                .join("SteamWrapper");
        }
    }

    env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("SteamWrapper")
}

pub fn default_profiles_path() -> PathBuf {
    app_data_dir().join("profiles.toml")
}

pub fn default_runner_path() -> PathBuf {
    let file_name = if cfg!(target_os = "windows") {
        "SteamWrapperRunner.exe"
    } else {
        "steamwrapper-runner"
    };

    app_data_dir().join("bin").join(file_name)
}

pub fn ensure_app_dirs() -> std::io::Result<()> {
    let base = app_data_dir();
    fs::create_dir_all(base.join("bin"))?;
    fs::create_dir_all(base.join("logs"))?;
    fs::create_dir_all(base.join("backups"))?;
    fs::create_dir_all(base.join("cache"))?;
    Ok(())
}
