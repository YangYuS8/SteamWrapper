use std::{
    fs,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use steamwrapper_manager_core::{ManagerPaths, ManagerService, SaveProfileRequest};

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time before Unix epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("steamwrapper-{label}-{nonce}"));
        fs::create_dir_all(&path).expect("create test directory");
        Self(path)
    }

    fn path(&self) -> &std::path::Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn saves_and_lists_profiles_without_changing_the_v2_toml_contract() {
    let root = TempDir::new("manager-profile-service");
    let app_data = root.path().join("SteamWrapper");
    let service = ManagerService::with_paths(
        ManagerPaths::from_app_data_dir(&app_data),
        root.path().join("bundle/steamwrapper-runner"),
    );

    service
        .save_profile(SaveProfileRequest {
            appid: "123456".to_string(),
            name: "Example Game".to_string(),
            game_dir: "/games/Example Game".to_string(),
            target: "launcher.sh".to_string(),
        })
        .expect("save profile");

    let raw = fs::read_to_string(app_data.join("profiles.toml")).expect("read profiles");
    assert!(raw.contains("version = 2"));
    assert!(raw.contains("[profiles.123456]"));
    assert!(raw.contains("app_id = \"123456\""));
    assert!(raw.contains("target = \"launcher.sh\""));
    if cfg!(target_os = "windows") {
        assert!(raw.contains("wait_mode = \"job\""));
    } else {
        assert!(raw.contains("wait_mode = \"process_group\""));
    }

    let profiles = service.list_profiles().expect("list profiles");
    assert_eq!(profiles.len(), 1);
    assert_eq!(profiles[0].appid, "123456");
    assert_eq!(profiles[0].name, "Example Game");
    assert!(profiles[0].launch_option.is_empty());
}

#[test]
fn repair_only_replaces_the_stable_runner_file() {
    let root = TempDir::new("manager-runner-service");
    let app_data = root.path().join("SteamWrapper");
    let bundled = root.path().join("bundle/steamwrapper-runner");
    let paths = ManagerPaths::from_app_data_dir(&app_data);
    fs::create_dir_all(bundled.parent().expect("bundle parent")).expect("create bundle parent");
    fs::write(&bundled, b"runner-v2").expect("write bundled runner");
    fs::create_dir_all(app_data.join("logs")).expect("create logs");
    fs::write(app_data.join("profiles.toml"), "version = 2\n").expect("write profiles");
    fs::write(app_data.join("logs/runner-123.log"), "keep\n").expect("write logs");

    let service = ManagerService::with_paths(paths.clone(), bundled);
    let installed = service.install_runner().expect("install runner");

    assert!(installed.changed);
    assert!(installed.status.healthy);
    assert_eq!(fs::read(&paths.runner_path).unwrap(), b"runner-v2");
    assert_eq!(
        fs::read_to_string(app_data.join("profiles.toml")).unwrap(),
        "version = 2\n"
    );
    assert_eq!(
        fs::read_to_string(app_data.join("logs/runner-123.log")).unwrap(),
        "keep\n"
    );
}

#[test]
fn launch_options_are_blocked_until_the_stable_runner_is_healthy() {
    let root = TempDir::new("manager-launch-option-service");
    let service = ManagerService::with_paths(
        ManagerPaths::from_app_data_dir(root.path().join("SteamWrapper")),
        root.path().join("bundle/missing-runner"),
    );

    let error = service
        .generate_launch_option("123456")
        .expect_err("missing bundled runner must not produce launch options");

    assert!(error.to_string().contains("Runner"));
}
