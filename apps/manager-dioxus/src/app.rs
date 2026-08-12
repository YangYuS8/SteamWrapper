use std::{cell::RefCell, path::Path};

use dioxus::prelude::*;
use steamwrapper_manager_core::{
    AppPaths, ConfiguredProfile, LocalSteamGame, RunnerLogEntry, RunnerStatus, SaveProfileRequest,
};

use crate::services;

const APP_CSS: Asset = asset!("/assets/manager.css");
const BRAND: Asset = asset!("/assets/steamwrapper.svg");

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum View {
    #[default]
    Library,
    Configured,
    Logs,
    Settings,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct GameDraft {
    appid: String,
    name: String,
    install_dir: String,
    cover_path: Option<String>,
}

impl From<LocalSteamGame> for GameDraft {
    fn from(game: LocalSteamGame) -> Self {
        Self {
            appid: game.appid,
            name: game.name,
            install_dir: game.install_dir.unwrap_or_default(),
            cover_path: game.cover_path,
        }
    }
}

impl From<ConfiguredProfile> for GameDraft {
    fn from(profile: ConfiguredProfile) -> Self {
        Self {
            appid: profile.appid,
            name: profile.name,
            install_dir: profile.game_dir,
            cover_path: None,
        }
    }
}

impl GameDraft {
    fn manual() -> Self {
        let appid = format!("manual-{}", chrono_free_nonce());
        Self {
            appid,
            name: "手动添加的游戏".to_string(),
            install_dir: String::new(),
            cover_path: None,
        }
    }
}

#[component]
pub fn App() -> Element {
    let window = dioxus::desktop::window();
    let drag_window = window.clone();
    let minimize_window = window.clone();
    let maximize_window = window.clone();
    let mut active_view = use_signal(View::default);
    let mut sidebar_collapsed = use_signal(|| false);
    let mut games = use_signal(Vec::<LocalSteamGame>::new);
    let mut profiles = use_signal(Vec::<ConfiguredProfile>::new);
    let mut logs = use_signal(Vec::<RunnerLogEntry>::new);
    let mut paths = use_signal(|| None::<AppPaths>);
    let mut runner_status = use_signal(|| None::<RunnerStatus>);
    let mut selected_game = use_signal(|| None::<GameDraft>);
    let mut target_path = use_signal(String::new);
    let mut launch_option = use_signal(String::new);
    let mut dialog_open = use_signal(|| false);
    let mut runner_busy = use_signal(|| false);
    let mut status_text = use_signal(|| "准备就绪".to_string());

    use_effect(move || {
        if let Err(error) = services::bootstrap() {
            status_text.set(format!("Runner 初始化失败：{error}"));
        }
        refresh_profiles(&mut profiles, &mut status_text);
        refresh_logs(&mut logs, &mut status_text);
        refresh_paths(&mut paths, &mut status_text);
        refresh_runner_status(&mut runner_status, &mut status_text);
    });

    let scan_games = move |_| {
        status_text.set("正在扫描本地 Steam 游戏……".to_string());
        match services::scan_games() {
            Ok(scanned) => {
                let count = scanned.len();
                games.set(scanned);
                status_text.set(if count == 0 {
                    "没有扫描到本地 Steam 游戏".to_string()
                } else {
                    format!("已找到 {count} 个本地 Steam 游戏")
                });
            }
            Err(error) => status_text.set(format!("扫描失败：{error}")),
        }
    };

    let add_manual_game = move |_| {
        let game = GameDraft::manual();
        selected_game.set(Some(game));
        target_path.set(String::new());
        launch_option.set(String::new());
        dialog_open.set(true);
        status_text.set("已创建手动游戏条目，请选择目标程序后保存".to_string());
    };

    let refresh_profiles_action = move |_| refresh_profiles(&mut profiles, &mut status_text);
    let refresh_logs_action = move |_| refresh_logs(&mut logs, &mut status_text);
    let refresh_paths_action = move |_| refresh_paths(&mut paths, &mut status_text);
    let refresh_runner_action =
        move |_| refresh_runner_status(&mut runner_status, &mut status_text);

    rsx! {
        document::Title { "SteamWrapper Manager" }
        document::Link { rel: "icon", href: BRAND }
        Stylesheet { href: APP_CSS }

        main { class: "manager-shell", "data-testid": "manager-root",
            header { class: "app-titlebar", "data-testid": "app-titlebar", onmousedown: move |_| drag_window.drag(),
                div { class: "app-titlebar__brand",
                    img { src: BRAND, alt: "SteamWrapper" }
                    span { "SteamWrapper" }
                }
                strong { class: "app-titlebar__title", "SteamWrapper Manager" }
                div { class: "window-controls",
                    button {
                        class: "window-control",
                        "data-testid": "window-minimize",
                        "aria-label": "最小化窗口",
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| minimize_window.set_minimized(true),
                        "—"
                    }
                    button {
                        class: "window-control",
                        "data-testid": "window-maximize",
                        "aria-label": "最大化或还原窗口",
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| maximize_window.toggle_maximized(),
                        "□"
                    }
                    button {
                        class: "window-control window-control--close",
                        "data-testid": "window-close",
                        "aria-label": "关闭窗口",
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| window.close(),
                        "×"
                    }
                }
            }

            div { class: "app-frame",
                aside { class: if sidebar_collapsed() { "sidebar sidebar--collapsed" } else { "sidebar" },
                    div { class: "brand",
                        img { src: BRAND, alt: "SteamWrapper" }
                        if !sidebar_collapsed() {
                            div {
                                strong { "SteamWrapper" }
                                span { "Manager v2 · Dioxus preview" }
                            }
                        }
                    }
                    nav { class: "navigation",
                        NavButton { label: "游戏库", icon: "▦", active: active_view() == View::Library,
                            onclick: move |_| active_view.set(View::Library) }
                        NavButton { label: "已配置游戏", icon: "✓", active: active_view() == View::Configured,
                            onclick: move |_| active_view.set(View::Configured) }
                        NavButton { label: "日志", icon: "≡", active: active_view() == View::Logs,
                            onclick: move |_| active_view.set(View::Logs) }
                        NavButton { label: "设置", icon: "⚙", active: active_view() == View::Settings,
                            onclick: move |_| active_view.set(View::Settings) }
                    }
                    button { class: "sidebar-toggle", onclick: move |_| sidebar_collapsed.toggle(),
                        if sidebar_collapsed() { "›" } else { "‹  折叠侧边栏" }
                    }
                }

                section { class: "workspace",
                    header { class: "workspace-toolbar",
                        p { class: "status", "data-testid": "status-text", "{status_text}" }
                    }
                    section { class: "content",
                        match active_view() {
                            View::Library => rsx! {
                                LibraryView {
                                    games: games(),
                                    selected_appid: selected_game().as_ref().map(|game| game.appid.clone()),
                                    on_scan: scan_games,
                                    on_manual: add_manual_game,
                                    on_open: move |game: LocalSteamGame| {
                                        selected_game.set(Some(game.into()));
                                        target_path.set(String::new());
                                        launch_option.set(String::new());
                                        dialog_open.set(true);
                                        status_text.set("正在配置游戏启动目标".to_string());
                                    },
                                }
                            },
                            View::Configured => rsx! {
                                ConfiguredView {
                                    profiles: profiles(),
                                    on_refresh: refresh_profiles_action,
                                    on_open: move |profile: ConfiguredProfile| {
                                        target_path.set(profile.target.clone());
                                        launch_option.set(profile.launch_option.clone());
                                        selected_game.set(Some(profile.into()));
                                        dialog_open.set(true);
                                        status_text.set("正在编辑已保存的游戏配置".to_string());
                                    },
                                }
                            },
                            View::Logs => rsx! {
                                LogsView { logs: logs(), on_refresh: refresh_logs_action }
                            },
                            View::Settings => rsx! {
                                SettingsView {
                                    paths: paths(),
                                    runner_status: runner_status(),
                                    runner_busy: runner_busy(),
                                    on_refresh_paths: refresh_paths_action,
                                    on_refresh_runner: refresh_runner_action,
                                    on_install: move |_| {
                                        runner_busy.set(true);
                                        match services::install_runner() {
                                            Ok(outcome) => {
                                                let message = if outcome.changed {
                                                    "Runner 已安装到稳定路径"
                                                } else {
                                                    "Runner 已是当前版本，无需重复复制"
                                                };
                                                runner_status.set(Some(outcome.status));
                                                status_text.set(message.to_string());
                                            }
                                            Err(error) => status_text.set(format!("Runner 操作失败：{error}")),
                                        }
                                        runner_busy.set(false);
                                    },
                                }
                            },
                        }
                    }
                }
            }

            if dialog_open() {
                ConfigDialog {
                    game: selected_game(),
                    target_path: target_path(),
                    launch_option: launch_option(),
                    on_close: move |_| dialog_open.set(false),
                    on_target_change: move |value| target_path.set(value),
                    on_choose_target: move |event: FormEvent| {
                        if let Some(path) = services::selected_path(event.files()) {
                            let game = selected_game();
                            if let Some(mut game) = game {
                                if game.appid.starts_with("manual-") {
                                    let path_info = path_info(&path);
                                    if game.name == "手动添加的游戏" {
                                        game.name = path_info.name;
                                    }
                                    if game.install_dir.is_empty() {
                                        game.install_dir = path_info.directory;
                                    }
                                    selected_game.set(Some(game));
                                }
                            }
                            target_path.set(path);
                            status_text.set("已选择目标程序".to_string());
                        }
                    },
                    on_generate: move |_| {
                        if let Some(game) = selected_game() {
                            match services::generate_launch_option(&game.appid) {
                                Ok(option) => {
                                    launch_option.set(option);
                                    status_text.set("已生成启动选项".to_string());
                                }
                                Err(error) => status_text.set(format!("无法生成可用启动选项：{error}")),
                            }
                        }
                    },
                    on_save: move |_| {
                        let Some(game) = selected_game() else {
                            status_text.set("请先选择一个游戏".to_string());
                            return;
                        };
                        if game.install_dir.trim().is_empty() {
                            status_text.set("当前游戏缺少安装目录，暂时无法保存配置".to_string());
                            return;
                        }
                        let target = target_path().trim().to_string();
                        if target.is_empty() {
                            status_text.set("请填写真正要启动的 exe 或 launcher 路径".to_string());
                            return;
                        }
                        match services::save_profile(SaveProfileRequest {
                            appid: game.appid.clone(),
                            name: game.name.clone(),
                            game_dir: game.install_dir.clone(),
                            target,
                        }) {
                            Ok(()) => {
                                match services::generate_launch_option(&game.appid) {
                                    Ok(option) => {
                                        launch_option.set(option);
                                        status_text.set("配置已保存，并已生成 Launch Options".to_string());
                                    }
                                    Err(error) => status_text.set(format!("配置已保存，但 Runner 尚不可用：{error}")),
                                }
                                refresh_profiles(&mut profiles, &mut status_text);
                            }
                            Err(error) => status_text.set(format!("保存失败：{error}")),
                        }
                    },
                }
            }
        }
    }
}

#[component]
fn NavButton(
    label: &'static str,
    icon: &'static str,
    active: bool,
    onclick: EventHandler<MouseEvent>,
) -> Element {
    rsx! {
        button {
            class: if active { "nav-button nav-button--active" } else { "nav-button" },
            "data-testid": "nav-{label}",
            onclick,
            span { class: "nav-icon", "{icon}" }
            span { class: "nav-label", "{label}" }
        }
    }
}

#[component]
fn LibraryView(
    games: Vec<LocalSteamGame>,
    selected_appid: Option<String>,
    on_scan: EventHandler<MouseEvent>,
    on_manual: EventHandler<MouseEvent>,
    on_open: EventHandler<LocalSteamGame>,
) -> Element {
    rsx! {
        section { class: "hero-card",
            div { class: "hero-copy",
                span { class: "eyebrow", "本地扫描 · 不联网拉取封面" }
                h1 { "游戏库" }
                p { "按照步骤完成配置；选择游戏后填写真正需要启动的 exe 或 launcher。" }
            }
            div { class: "action-row",
                button { class: "button button--primary", "data-testid": "scan-games", onclick: on_scan, "扫描本地 Steam 游戏" }
                button { class: "button", "data-testid": "manual-add-game", onclick: on_manual, "手动添加游戏" }
            }
            div { class: "guide-grid",
                GuideCard { number: "1", title: "扫描", description: "读取本地 Steam 游戏库" }
                GuideCard { number: "2", title: "选择", description: "填写实际启动的程序" }
                GuideCard { number: "3", title: "保存", description: "生成 Launch Options" }
            }
        }
        section { class: "game-grid",
            if games.is_empty() {
                EmptyState { title: "还没有游戏列表", description: "点击“扫描本地 Steam 游戏”开始。" }
            } else {
                for game in games {
                    {
                        let is_selected = selected_appid.as_deref() == Some(game.appid.as_str());
                        let game_for_click = game.clone();
                        let id = game.appid.clone();
                        let install_dir = game
                            .install_dir
                            .clone()
                            .unwrap_or_else(|| "未找到安装目录".to_string());
                        rsx! {
                            button {
                                class: if is_selected { "game-card game-card--selected" } else { "game-card" },
                                "data-testid": "game-card-{id}",
                                onclick: move |_| on_open.call(game_for_click.clone()),
                                GameCover { game: game.clone() }
                                div { class: "game-card__body",
                                    div { class: "game-card__title", span { "{game.name}" } span { class: "arrow", "›" } }
                                    span { class: "muted", "AppID: {game.appid}" }
                                    div { class: "game-path", "{install_dir}" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn GameCover(game: LocalSteamGame) -> Element {
    let image_url = game.cover_path.as_deref().and_then(file_url);
    rsx! {
        div { class: "game-cover",
            if let Some(url) = image_url {
                img { src: url, alt: "{game.name} 的本地封面" }
            } else {
                div { class: "cover-placeholder", span { "▧" } small { "本地封面缓存未找到" } }
            }
        }
    }
}

#[component]
fn GuideCard(number: &'static str, title: &'static str, description: &'static str) -> Element {
    rsx! { div { class: "guide-card", span { class: "guide-number", "{number}" } strong { "{title}" } p { "{description}" } } }
}

#[component]
fn ConfiguredView(
    profiles: Vec<ConfiguredProfile>,
    on_refresh: EventHandler<MouseEvent>,
    on_open: EventHandler<ConfiguredProfile>,
) -> Element {
    rsx! {
        section { class: "panel",
            header { class: "panel-header",
                div { h1 { "已配置游戏" } p { "这里读取本机 profiles.toml，点击条目可以继续编辑。" } }
                button { class: "button", "data-testid": "refresh-profiles", onclick: on_refresh, "刷新" }
            }
            div { class: "list-stack",
                if profiles.is_empty() {
                    EmptyState { title: "还没有保存过配置", description: "先到游戏库选择一个游戏，保存后会出现在这里。" }
                } else {
                    for profile in profiles {
                        {
                            let profile_for_click = profile.clone();
                            let id = profile.appid.clone();
                            rsx! {
                                button { class: "profile-card", "data-testid": "configured-profile-{id}", onclick: move |_| on_open.call(profile_for_click.clone()),
                                    div { class: "profile-card__heading", div { strong { "{profile.name}" } span { class: "muted", "AppID: {profile.appid}" } } span { class: "arrow", "›" } }
                                    div { class: "path-grid",
                                        PathLine { label: "游戏目录", value: profile.game_dir.clone() }
                                        PathLine { label: "目标程序", value: profile.target.clone() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn LogsView(logs: Vec<RunnerLogEntry>, on_refresh: EventHandler<MouseEvent>) -> Element {
    rsx! {
        section { class: "panel",
            header { class: "panel-header",
                div { h1 { "日志" } p { "显示 logs 目录下最近的 Runner 日志，便于排查启动失败。" } }
                button { class: "button", "data-testid": "refresh-logs", onclick: on_refresh, "刷新" }
            }
            div { class: "list-stack",
                if logs.is_empty() {
                    EmptyState { title: "暂无日志", description: "Runner 启动过游戏后，这里会显示日志文件。" }
                } else {
                    for log in logs {
                        {
                            let content = if log.content.is_empty() {
                                "日志为空".to_string()
                            } else {
                                log.content.clone()
                            };
                            rsx! {
                                article { class: "log-card", "data-testid": "runner-log-{log.file_name}",
                                    strong { "{log.file_name}" }
                                    p { class: "muted break-all", "{log.path}" }
                                    pre { "{content}" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn SettingsView(
    paths: Option<AppPaths>,
    runner_status: Option<RunnerStatus>,
    runner_busy: bool,
    on_refresh_paths: EventHandler<MouseEvent>,
    on_refresh_runner: EventHandler<MouseEvent>,
    on_install: EventHandler<MouseEvent>,
) -> Element {
    let status_label = runner_status
        .as_ref()
        .map(|status| {
            if status.healthy {
                "已安装"
            } else if status.needs_install {
                "未安装"
            } else if status.needs_update {
                "需要更新"
            } else {
                "检查失败"
            }
        })
        .unwrap_or("正在读取……");
    let runner_path = runner_status
        .as_ref()
        .map(|item| item.path.clone())
        .or_else(|| paths.as_ref().map(|item| item.runner_path.clone()))
        .unwrap_or_else(|| "正在读取……".to_string());
    let bundled_hash = runner_status
        .as_ref()
        .and_then(|item| item.bundled_version.as_ref())
        .map(|hash| short_hash(hash))
        .unwrap_or_else(|| "未知".to_string());
    rsx! {
        section { class: "panel", "data-testid": "app-paths",
            header { class: "panel-header",
                div { h1 { "设置" } p { "查看稳定数据目录和 Steam 启动所需的 Runner 状态。" } }
                div { class: "action-row",
                    button { class: "button", "data-testid": "refresh-runner-status", onclick: on_refresh_runner, "检查 Runner" }
                    button { class: "button", "data-testid": "refresh-paths", onclick: on_refresh_paths, "刷新路径" }
                }
            }
            article { class: "runner-card",
                div {
                    h2 { "SteamWrapper Runner" }
                    p { "data-testid": "runner-status", "Runner 状态：{status_label}" }
                    p { class: "muted break-all", "data-testid": "runner-path", "Runner 路径：{runner_path}" }
                    p { class: "muted break-all", "data-testid": "runner-version",
                        "随包摘要：{bundled_hash}"
                    }
                    if let Some(error) = runner_status.as_ref().and_then(|item| item.last_error.as_ref()) {
                        p { class: "error", "data-testid": "runner-error", "{error}" }
                    }
                }
                if runner_status.as_ref().is_some_and(|status| !status.healthy) {
                    button {
                        class: "button button--primary",
                        "data-testid": if runner_status.as_ref().is_some_and(|status| status.needs_install) { "runner-install" } else { "runner-repair" },
                        disabled: runner_busy,
                        onclick: on_install,
                        if runner_busy { "正在处理……" } else if runner_status.as_ref().is_some_and(|status| status.needs_install) { "安装 Runner" } else { "重新安装 / 修复 Runner" }
                    }
                }
            }
            div { class: "path-grid",
                if let Some(paths) = paths {
                    PathCard { label: "用户数据目录", value: paths.app_data_dir }
                    PathCard { label: "profiles.toml", value: paths.profiles_path }
                    PathCard { label: "Runner 稳定路径", value: paths.runner_path }
                    PathCard { label: "日志目录", value: paths.logs_dir }
                    PathCard { label: "备份目录", value: paths.backups_dir }
                    PathCard { label: "缓存目录", value: paths.cache_dir }
                } else {
                    EmptyState { title: "路径信息未加载", description: "点击刷新重新读取。" }
                }
            }
        }
    }
}

#[component]
fn ConfigDialog(
    game: Option<GameDraft>,
    target_path: String,
    launch_option: String,
    on_close: EventHandler<MouseEvent>,
    on_target_change: EventHandler<String>,
    on_choose_target: EventHandler<FormEvent>,
    on_generate: EventHandler<MouseEvent>,
    on_save: EventHandler<MouseEvent>,
) -> Element {
    let Some(game) = game else {
        return rsx! {};
    };
    let game_directory = if game.install_dir.is_empty() {
        "请选择目标程序，或输入游戏目录。".to_string()
    } else {
        game.install_dir.clone()
    };
    rsx! {
        div { class: "dialog-backdrop", "data-testid": "config-dialog",
            article { class: "dialog-card",
                header { class: "dialog-header",
                    div { h1 { "配置启动目标" } p { "{game.name} · AppID {game.appid}" } }
                    button { class: "icon-button", onclick: on_close, "×" }
                }
                div { class: "game-directory", strong { "游戏目录" } p { "{game_directory}" } }
                label { class: "field", span { "真正要启动的程序" }
                    div { class: "file-input-row",
                        input {
                            r#type: "text",
                            "data-testid": "target-path",
                            value: "{target_path}",
                            placeholder: "例如 Game_CHS.exe 或 launcher.exe",
                            oninput: move |event| on_target_change.call(event.value()),
                        }
                        label { class: "button file-button", "浏览",
                            input { r#type: "file", accept: ".exe,.bat,.cmd,.sh,.desktop", onchange: on_choose_target }
                        }
                    }
                }
                div { class: "action-row",
                    button { class: "button button--primary", "data-testid": "save-profile", onclick: on_save, "保存并生成启动选项" }
                    button { class: "button", onclick: on_generate, "仅生成启动选项" }
                    button { class: "button button--disabled", disabled: true, "测试启动（稍后实现）" }
                }
                label { class: "field", span { "Launch Options" }
                    textarea { "data-testid": "launch-option", readonly: true, value: "{launch_option}", placeholder: "保存配置后生成" }
                }
            }
        }
    }
}

#[component]
fn EmptyState(title: &'static str, description: &'static str) -> Element {
    rsx! { div { class: "empty-state", strong { "{title}" } p { "{description}" } } }
}

#[component]
fn PathLine(label: &'static str, value: String) -> Element {
    rsx! { div { class: "path-line", small { "{label}" } p { "{value}" } } }
}

#[component]
fn PathCard(label: &'static str, value: String) -> Element {
    rsx! { div { class: "path-card", strong { "{label}" } p { "{value}" } } }
}

fn refresh_profiles(profiles: &mut Signal<Vec<ConfiguredProfile>>, status: &mut Signal<String>) {
    match services::list_profiles() {
        Ok(items) => profiles.set(items),
        Err(error) => status.set(format!("读取配置失败：{error}")),
    }
}

fn refresh_logs(logs: &mut Signal<Vec<RunnerLogEntry>>, status: &mut Signal<String>) {
    match services::list_logs() {
        Ok(items) => logs.set(items),
        Err(error) => status.set(format!("读取日志失败：{error}")),
    }
}

fn refresh_paths(paths: &mut Signal<Option<AppPaths>>, status: &mut Signal<String>) {
    match services::paths() {
        Ok(items) => paths.set(Some(items)),
        Err(error) => status.set(format!("读取路径失败：{error}")),
    }
}

fn refresh_runner_status(
    status_signal: &mut Signal<Option<RunnerStatus>>,
    status: &mut Signal<String>,
) {
    match services::runner_status() {
        Ok(item) => status_signal.set(Some(item)),
        Err(error) => status.set(format!("检查 Runner 失败：{error}")),
    }
}

fn short_hash(hash: &str) -> String {
    hash.chars().take(12).collect()
}

fn file_url(path: &str) -> Option<String> {
    let path = Path::new(path);
    let absolute = path.canonicalize().ok()?;
    let mut url = String::from("file://");
    #[cfg(target_os = "windows")]
    url.push('/');
    url.push_str(
        &absolute
            .to_string_lossy()
            .replace('\\', "/")
            .replace(' ', "%20"),
    );
    Some(url)
}

fn path_info(path: &str) -> PathInfo {
    let path = Path::new(path);
    let name = path
        .file_stem()
        .and_then(|name| name.to_str())
        .unwrap_or("手动添加的游戏")
        .to_string();
    let directory = path
        .parent()
        .map(|parent| parent.to_string_lossy().to_string())
        .unwrap_or_default();
    PathInfo { name, directory }
}

struct PathInfo {
    name: String,
    directory: String,
}

fn chrono_free_nonce() -> u128 {
    thread_local! {
        static COUNTER: RefCell<u128> = const { RefCell::new(0) };
    }
    COUNTER.with(|counter| {
        let mut counter = counter.borrow_mut();
        *counter += 1;
        let base = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|time| time.as_millis())
            .unwrap_or_default();
        base * 1000 + *counter
    })
}

#[cfg(test)]
mod tests {
    use super::{file_url, path_info, short_hash};

    #[test]
    fn extracts_a_manual_game_name_and_directory_from_a_target_path() {
        let info = path_info("/games/Example Game/launcher.sh");
        assert_eq!(info.name, "launcher");
        assert_eq!(info.directory, "/games/Example Game");
    }

    #[test]
    fn short_hash_is_safe_for_short_values() {
        assert_eq!(short_hash("abcd"), "abcd");
    }

    #[test]
    fn missing_cover_path_does_not_become_a_broken_url() {
        assert!(file_url("/path/that/does/not/exist.png").is_none());
    }
}
