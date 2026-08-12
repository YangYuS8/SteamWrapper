use std::fs;

#[test]
fn manager_renders_the_required_navigation_and_primary_actions() {
    let source = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/app.rs"))
        .expect("read Dioxus Manager source");

    for required_text in [
        "游戏库",
        "已配置游戏",
        "日志",
        "设置",
        "扫描本地 Steam 游戏",
        "手动添加游戏",
        "配置启动目标",
        "保存并生成启动选项",
        "SteamWrapper Runner",
    ] {
        assert!(
            source.contains(required_text),
            "Dioxus Manager must retain the player-facing flow: {required_text}"
        );
    }
}

#[test]
fn manager_keeps_native_file_selection_and_uses_the_shared_service_boundary() {
    let app = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/app.rs"))
        .expect("read Dioxus Manager component");
    let services = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/services.rs"))
        .expect("read Manager services");

    assert!(app.contains("r#type: \"file\""));
    assert!(app.contains("services::selected_path(event.files())"));
    assert!(services.contains("ManagerService"));
    assert!(services.contains("generate_launch_option"));
    assert!(services.contains("save_profile"));
}

#[test]
fn manager_uses_the_canonical_brand_asset_instead_of_a_substitute() {
    let brand = fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/assets/steamwrapper.svg"
    ))
    .expect("read Dioxus Manager brand asset");
    let canonical = fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../assets/brand/steamwrapper.svg"
    ))
    .expect("read canonical project brand asset");

    assert_eq!(
        brand, canonical,
        "Manager must use the canonical project mark"
    );
}

#[test]
fn bundle_configuration_declares_both_platform_runner_resources() {
    let config = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/Dioxus.toml"))
        .expect("read Dioxus bundle configuration");

    assert!(config.contains("resources/runner/SteamWrapperRunner.exe"));
    assert!(config.contains("resources/runner/steamwrapper-runner"));
    assert!(config.contains("install_mode = \"CurrentUser\""));

    let stage_script = fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/scripts/stage-runner.sh"
    ))
    .expect("read Runner staging script");
    assert!(stage_script.contains("$source.exe"));
    assert!(stage_script.contains("SteamWrapperRunner.exe"));
    assert!(
        stage_script.contains(": > \"$destination\"")
            && stage_script.contains("windows_destination"),
        "each platform bundle needs an empty placeholder for the other platform resource"
    );
}

#[test]
fn manager_bootstraps_the_stable_runner_before_showing_the_ui() {
    let main = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"))
        .expect("read Dioxus Manager entrypoint");
    let services = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/services.rs"))
        .expect("read Manager services");

    assert!(main.contains("services::bootstrap()"));
    assert!(services.contains("pub fn bootstrap()"));
    assert!(services.contains(".install_runner()"));
}

#[test]
fn manager_uses_a_frameless_desktop_shell_with_a_fixed_sidebar_and_scrollable_workspace() {
    let main = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"))
        .expect("read Dioxus Manager entrypoint");
    let app = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/app.rs"))
        .expect("read Dioxus Manager component");
    let css = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/assets/manager.css"))
        .expect("read Manager stylesheet");

    assert!(main.contains(".with_decorations(false)"));
    assert!(app.contains("window.drag()"));
    assert!(app.contains("window.toggle_maximized()"));
    assert!(app.contains("window.close()"));
    assert!(app.contains("fn Sidebar(mut active_view: Signal<View>) -> Element"));
    assert!(app.contains("Sidebar { active_view }"));
    assert!(app.contains("\"data-testid\": \"sidebar\""));
    assert!(app.contains("\"data-testid\": \"sidebar-toggle\""));
    assert!(app.contains("onerror: move |_| failed.set(true)"));
    assert!(app.contains("封面暂不可用"));
    assert!(app.contains("本地缓存优先，官方 Steam CDN 回退"));
    assert!(app.contains("class: \"app-titlebar\""));
    assert!(app.contains("\"data-testid\": \"app-titlebar\""));
    assert!(app.contains("\"data-testid\": \"window-minimize\""));
    assert!(app.contains("\"data-testid\": \"window-maximize\""));
    assert!(app.contains("\"data-testid\": \"window-close\""));
    assert!(app.contains("class: \"window-control window-control--close\""));
    assert!(css.contains(".manager-shell { display: flex; height: 100vh;"));
    assert!(css.contains(".app-titlebar { height: 38px;"));
    assert!(css.contains("background: #0a1625"));
    assert!(css.contains(".app-frame { position: relative;"));
    assert!(css.contains(".sidebar { position: absolute;"));
    assert!(css.contains("transition: transform .18s cubic-bezier(.2, .8, .2, 1)"));
    assert!(css.contains(".sidebar--collapsed { transform: translateX(-188px); }"));
    assert!(css.contains(".sidebar--collapsed .brand img, .sidebar--collapsed .nav-button, .sidebar--collapsed .sidebar-toggle { transform: translateX(188px); }"));
    assert!(css.contains(
        ".workspace { display: flex; min-width: 0; min-height: 0; flex: 1; margin-left: 264px;"
    ));
    assert!(css.contains("transition: margin-left .18s cubic-bezier(.2, .8, .2, 1)"));
    assert!(css.contains(".sidebar--collapsed + .workspace { margin-left: 76px; }"));
    assert!(css.contains(".content { min-height: 0; flex: 1;"));
    assert!(css.contains("scroll-behavior: smooth"));
    assert!(css.contains("overscroll-behavior: contain"));
    assert!(css.contains("scrollbar-gutter: stable"));
}

#[test]
fn repository_no_longer_keeps_the_retired_tauri_react_manager() {
    let repository_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("resolve repository root");

    assert!(
        !repository_root.join("apps/manager").exists(),
        "the retired Tauri/React Manager must be removed after Dioxus becomes the sole Manager"
    );
    assert!(
        !repository_root.join("apps/manager-e2e").exists(),
        "the retired Tauri E2E suite must be removed with its Manager"
    );

    let workspace_manifest =
        fs::read_to_string(repository_root.join("Cargo.toml")).expect("read workspace manifest");
    assert!(
        !workspace_manifest.contains("tauri ="),
        "the Dioxus-only workspace must not retain a Tauri dependency"
    );
}
