use std::{env, fs, path::PathBuf};
use steamwrapper_core::{Platform, SteamWrapperConfig, WaitMode};

const LEGACY: &str = include_str!("../../../tests/contracts/legacy-v2.toml");
const EDITED_TARGET: &str = r"patch update\汉化.exe";

#[test]
fn historical_fixture_has_all_supported_profile_semantics() {
    let config: SteamWrapperConfig = toml::from_str(LEGACY).unwrap();
    assert_eq!(config.version, 2);
    assert_eq!(config.profiles.len(), 6);
    let (key, profile) = config.require_profile_by_appid("480").unwrap();
    assert_eq!(key, "translated-game");
    assert_eq!(profile.name, "汉化游戏 \"测试\"");
    assert_eq!(profile.platform, Some(Platform::Windows));
    assert_eq!(
        profile.game_dir,
        PathBuf::from(r"C:\游戏 Library\Original Game")
    );
    assert_eq!(profile.target, PathBuf::from(r"patch\旧版.exe"));
    assert_eq!(profile.working_dir, Some(PathBuf::from(r"data files\中文")));
    assert_eq!(profile.process_name.as_deref(), Some("game.exe"));
    assert_eq!(
        profile.args,
        [
            "--title",
            "中文 with spaces",
            "a\"b",
            "C:\\尾部\\",
            "",
            "line one\nline two"
        ]
    );
    assert_eq!(profile.wait_mode, WaitMode::ProcessName);
    assert_eq!(config.profiles["legacy"].wait_mode, WaitMode::Root);
    assert_eq!(config.profiles["explicit-root"].wait_mode, WaitMode::Root);
    assert_eq!(
        config.profiles["linux-game"].wait_mode,
        WaitMode::ProcessGroup
    );
    assert_eq!(config.profiles["steamdeck-game"].wait_mode, WaitMode::None);
    assert_eq!(
        config.profiles["steamdeck-game"].platform,
        Some(Platform::SteamOs)
    );
    assert_eq!(config.profiles["windows-job"].wait_mode, WaitMode::Job);
}

/// The Windows contract script first edits the shared fixture through the real C#
/// service. Ignored in Rust-only workflows because it needs that generated input.
#[test]
#[ignore = "requires C# contract output; run mise run winui:contracts"]
fn csharp_edit_preserves_every_unedited_value_and_runner_contract() {
    let directory =
        PathBuf::from(env::var_os("STEAMWRAPPER_CONTRACT_ROOT").expect("contract root"));
    let edited = fs::read_to_string(directory.join("roundtrip.toml")).unwrap();
    let mut expected: toml::Value = toml::from_str(LEGACY).unwrap();
    expected["profiles"]["translated-game"]["target"] = EDITED_TARGET.into();
    let actual: toml::Value = toml::from_str(&edited).unwrap();
    // This covers unknown top-level/profile keys, nested tables, table arrays,
    // dates, omitted fields, every argument and all unrelated profiles.
    assert_eq!(
        actual, expected,
        "C# changed more than the requested target"
    );

    let before: SteamWrapperConfig = toml::from_str(LEGACY).unwrap();
    let after = SteamWrapperConfig::load(directory.join("roundtrip.toml")).unwrap();
    for (key, original) in &before.profiles {
        let mut expected_profile = original.clone();
        if key == "translated-game" {
            expected_profile.target = EDITED_TARGET.into();
        }
        assert_eq!(
            toml::Value::try_from(&after.profiles[key]).unwrap(),
            toml::Value::try_from(&expected_profile).unwrap(),
            "Rust profile semantics changed for {key}"
        );
    }
    assert_eq!(
        after.require_profile_by_appid("480").unwrap().0,
        "translated-game"
    );
    assert_eq!(
        after.require_profile_by_appid("translated-game").unwrap().0,
        "translated-game"
    );
    assert_eq!(after.profiles["legacy"].wait_mode, WaitMode::Root);

    let created = SteamWrapperConfig::load(directory.join("new-windows.toml")).unwrap();
    assert_eq!(created.version, 2);
    assert_eq!(created.profiles.len(), 1);
    let (key, profile) = created.require_profile_by_appid("900001").unwrap();
    assert_eq!(key, "900001");
    assert_eq!(profile.platform, Some(Platform::Windows));
    assert_eq!(profile.wait_mode, WaitMode::Job);
    assert_eq!(profile.game_dir, directory.join("游戏 Library"));
    assert_eq!(
        profile.target,
        PathBuf::from(r"程序 files\SteamWrapper.ProcessFixture.exe")
    );
    assert_eq!(profile.working_dir, Some(PathBuf::from("工作 directory")));
    assert_eq!(
        profile.resolve_target(),
        directory.join("游戏 Library/程序 files/SteamWrapper.ProcessFixture.exe")
    );
    assert_eq!(
        profile.resolve_working_dir(),
        directory.join("游戏 Library/工作 directory")
    );
    assert_eq!(
        profile.args,
        [
            "--parent",
            "中文 with spaces",
            "embedded\"quote",
            "trailing\\",
            ""
        ]
    );
    assert_eq!(profile.process_name, None);
}
