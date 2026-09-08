use std::{cell::RefCell, path::Path};

use dioxus::prelude::*;
use steamwrapper_manager_core::{
    AppPaths, ConfiguredProfile, Language, LocalSteamGame, RunnerLogEntry, RunnerStatus,
    SaveProfileRequest,
};

use crate::{
    i18n::{Message, Text as K},
    services,
};

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
    generated_name: bool,
}

impl From<LocalSteamGame> for GameDraft {
    fn from(game: LocalSteamGame) -> Self {
        Self {
            appid: game.appid,
            name: game.name,
            install_dir: game.install_dir.unwrap_or_default(),
            cover_path: game.cover_path,
            generated_name: false,
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
            generated_name: false,
        }
    }
}

impl GameDraft {
    fn display_name(&self, language: Language) -> String {
        if self.generated_name {
            K::ManualName.text(language).to_string()
        } else {
            self.name.clone()
        }
    }
    fn manual() -> Self {
        let appid = format!("manual-{}", chrono_free_nonce());
        Self {
            appid,
            name: K::ManualName.text(Language::default()).to_string(),
            install_dir: String::new(),
            cover_path: None,
            generated_name: true,
        }
    }
}

#[component]
pub fn App() -> Element {
    let window = dioxus::desktop::window();
    let drag_window = window.clone();
    let minimize_window = window.clone();
    let maximize_window = window.clone();
    let preference = use_hook(services::load_language);
    let mut language = use_context_provider(|| Signal::new(preference.clone().unwrap_or_default()));
    let mut preference_error = use_signal(|| preference.err());
    let current_language = language();
    let active_view = use_signal(View::default);
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
    let mut status_text = use_signal(|| Message::Plain(K::Ready));

    use_effect(move || {
        if let Err(error) = services::bootstrap() {
            status_text.set(Message::Error(K::BootstrapFailed, error));
        }
        refresh_profiles(&mut profiles, &mut status_text);
        refresh_logs(&mut logs, &mut status_text);
        refresh_paths(&mut paths, &mut status_text);
        refresh_runner_status(&mut runner_status, &mut status_text);
    });

    let scan_games = move |_| {
        status_text.set(Message::Plain(K::Scanning));
        match services::scan_games() {
            Ok(scanned) => {
                let count = scanned.len();
                games.set(scanned);
                status_text.set(if count == 0 {
                    Message::Plain(K::NoGamesFound)
                } else {
                    Message::GamesFound(count)
                });
            }
            Err(error) => status_text.set(Message::Error(K::ScanFailed, error)),
        }
    };

    let add_manual_game = move |_| {
        let game = GameDraft::manual();
        selected_game.set(Some(game));
        target_path.set(String::new());
        launch_option.set(String::new());
        dialog_open.set(true);
        status_text.set(Message::Plain(K::ManualCreated));
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

        main { class: "manager-shell", "data-testid": "manager-root", lang: current_language.tag(),
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
                        "aria-label": K::Minimize.text(current_language),
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| minimize_window.set_minimized(true),
                        "—"
                    }
                    button {
                        class: "window-control",
                        "data-testid": "window-maximize",
                        "aria-label": K::Maximize.text(current_language),
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| maximize_window.toggle_maximized(),
                        "□"
                    }
                    button {
                        class: "window-control window-control--close",
                        "data-testid": "window-close",
                        "aria-label": K::CloseWindow.text(current_language),
                        onmousedown: move |event| event.stop_propagation(),
                        onclick: move |_| window.close(),
                        "×"
                    }
                }
            }

            div { class: "app-frame",
                Sidebar { active_view }

                section { class: "workspace",
                    header { class: "workspace-toolbar",
                        p { class: "status", "data-testid": "status-text", role: "status", "aria-live": "polite", {status_text().render(current_language)} }
                        LanguagePicker {
                            language: current_language,
                            on_change: move |selected| {
                                match services::save_language(selected) {
                                    Ok(()) => { language.set(selected); preference_error.set(None); }
                                    Err(error) => preference_error.set(Some(error)),
                                }
                            }
                        }
                    }
                    if let Some(error) = preference_error() {
                        p { class: "error", role: "alert", "data-testid": "language-error", {error.message(current_language)} }
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
                                        status_text.set(Message::Plain(K::Configuring));
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
                                        status_text.set(Message::Plain(K::Editing));
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
                                                    K::RunnerInstalled
                                                } else {
                                                    K::RunnerCurrent
                                                };
                                                runner_status.set(Some(outcome.status));
                                                status_text.set(Message::Plain(message));
                                            }
                                            Err(error) => status_text.set(Message::Error(K::RunnerFailed, error)),
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
                                    if game.generated_name && !path_info.name.is_empty() {
                                        game.name = path_info.name;
                                        game.generated_name = false;
                                    }
                                    if game.install_dir.is_empty() {
                                        game.install_dir = path_info.directory;
                                    }
                                    selected_game.set(Some(game));
                                }
                            }
                            target_path.set(path);
                            status_text.set(Message::Plain(K::TargetSelected));
                        }
                    },
                    on_generate: move |_| {
                        if let Some(game) = selected_game() {
                            match services::generate_launch_option(&game.appid) {
                                Ok(option) => {
                                    launch_option.set(option);
                                    status_text.set(Message::Plain(K::OptionsGenerated));
                                }
                                Err(error) => status_text.set(Message::Error(K::GenerateFailed, error)),
                            }
                        }
                    },
                    on_save: move |_| {
                        let Some(game) = selected_game() else {
                            status_text.set(Message::Plain(K::ChooseGame));
                            return;
                        };
                        if game.install_dir.trim().is_empty() {
                            status_text.set(Message::Plain(K::MissingDirectory));
                            return;
                        }
                        let target = target_path().trim().to_string();
                        if target.is_empty() {
                            status_text.set(Message::Plain(K::EnterTarget));
                            return;
                        }
                        match services::save_profile(SaveProfileRequest {
                            appid: game.appid.clone(),
                            name: game.display_name(language()),
                            game_dir: game.install_dir.clone(),
                            target,
                        }) {
                            Ok(()) => {
                                match services::generate_launch_option(&game.appid) {
                                    Ok(option) => {
                                        launch_option.set(option);
                                        status_text.set(Message::Plain(K::Saved));
                                    }
                                    Err(error) => status_text.set(Message::Error(K::SavedRunnerUnavailable, error)),
                                }
                                refresh_profiles(&mut profiles, &mut status_text);
                            }
                            Err(error) => status_text.set(Message::Error(K::SaveFailed, error)),
                        }
                    },
                }
            }
        }
    }
}

#[component]
fn LanguagePicker(language: Language, on_change: EventHandler<Language>) -> Element {
    rsx! {
        div { class: "action-row", role: "group", "aria-label": K::LanguageLabel.text(language), "data-testid": "language-picker",
            button {
                class: "button", "data-testid": "language-en", lang: "en-US",
                "aria-pressed": (language == Language::English).to_string(),
                onclick: move |_| on_change.call(Language::English), "English"
            }
            button {
                class: "button", "data-testid": "language-zh", lang: "zh-CN",
                "aria-pressed": (language == Language::SimplifiedChinese).to_string(),
                onclick: move |_| on_change.call(Language::SimplifiedChinese), "简体中文"
            }
        }
    }
}

#[component]
fn NavButton(
    label: &'static str,
    test_id: &'static str,
    icon: &'static str,
    active: bool,
    onclick: EventHandler<MouseEvent>,
) -> Element {
    rsx! {
        button {
            class: if active { "nav-button nav-button--active" } else { "nav-button" },
            "data-testid": "nav-{test_id}",
            onclick,
            span { class: "nav-icon", "{icon}" }
            span { class: "nav-label", "{label}" }
        }
    }
}

#[component]
fn Sidebar(mut active_view: Signal<View>) -> Element {
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    let mut collapsed = use_signal(|| false);

    rsx! {
        aside {
            class: if collapsed() { "sidebar sidebar--collapsed" } else { "sidebar" },
            "data-testid": "sidebar",
            div { class: "brand",
                img { src: BRAND, alt: "SteamWrapper" }
                div { class: "brand-copy",
                    strong { "SteamWrapper" }
                    span { {t(K::Preview)} }
                }
            }
            nav { class: "navigation",
                NavButton { label: t(K::Library), test_id: "library", icon: "▦", active: active_view() == View::Library,
                    onclick: move |_| active_view.set(View::Library) }
                NavButton { label: t(K::Configured), test_id: "configured", icon: "✓", active: active_view() == View::Configured,
                    onclick: move |_| active_view.set(View::Configured) }
                NavButton { label: t(K::Logs), test_id: "logs", icon: "≡", active: active_view() == View::Logs,
                    onclick: move |_| active_view.set(View::Logs) }
                NavButton { label: t(K::Settings), test_id: "settings", icon: "⚙", active: active_view() == View::Settings,
                    onclick: move |_| active_view.set(View::Settings) }
            }
            button {
                class: "sidebar-toggle",
                "data-testid": "sidebar-toggle",
                "aria-label": if collapsed() { t(K::Expand) } else { t(K::Collapse) },
                onclick: move |_| collapsed.toggle(),
                if collapsed() { "›" } else { {format!("‹  {}", t(K::Collapse))} }
            }
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    rsx! {
        section { class: "hero-card",
            div { class: "hero-copy",
                span { class: "eyebrow", {t(K::CoverSources)} }
                h1 { {t(K::Library)} }
                p { {t(K::LibraryHelp)} }
            }
            div { class: "action-row",
                button { class: "button button--primary", "data-testid": "scan-games", onclick: on_scan, {t(K::ScanGames)} }
                button { class: "button", "data-testid": "manual-add-game", onclick: on_manual, {t(K::AddGame)} }
            }
            div { class: "guide-grid",
                GuideCard { number: "1", title: t(K::Scan), description: t(K::ScanHelp) }
                GuideCard { number: "2", title: t(K::Choose), description: t(K::ChooseHelp) }
                GuideCard { number: "3", title: t(K::Save), description: t(K::SaveHelp) }
            }
        }
        section { class: "game-grid",
            if games.is_empty() {
                EmptyState { title: t(K::EmptyLibrary), description: t(K::EmptyLibraryHelp) }
            } else {
                for game in games {
                    {
                        let is_selected = selected_appid.as_deref() == Some(game.appid.as_str());
                        let game_for_click = game.clone();
                        let id = game.appid.clone();
                        let install_dir = game
                            .install_dir
                            .clone()
                            .unwrap_or_else(|| t(K::DirectoryNotFound).to_string());
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    let mut failed = use_signal(|| false);
    let image_url = game.cover_path.as_deref().and_then(cover_url);

    rsx! {
        div { class: "game-cover", "data-testid": "game-cover-{game.appid}",
            if let Some(url) = image_url.filter(|_| !failed()) {
                img {
                    src: url,
                    alt: t(K::CoverAlt).replace("{name}", &game.name),
                    onerror: move |_| failed.set(true),
                }
            } else {
                div { class: "cover-placeholder", span { "▧" } small { {t(K::MissingCover)} } }
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    rsx! {
        section { class: "panel",
            header { class: "panel-header",
                div { h1 { {t(K::Configured)} } p { {t(K::ConfiguredHelp)} } }
                button { class: "button", "data-testid": "refresh-profiles", onclick: on_refresh, {t(K::Refresh)} }
            }
            div { class: "list-stack",
                if profiles.is_empty() {
                    EmptyState { title: t(K::EmptyProfiles), description: t(K::EmptyProfilesHelp) }
                } else {
                    for profile in profiles {
                        {
                            let profile_for_click = profile.clone();
                            let id = profile.appid.clone();
                            rsx! {
                                button { class: "profile-card", "data-testid": "configured-profile-{id}", onclick: move |_| on_open.call(profile_for_click.clone()),
                                    div { class: "profile-card__heading", div { strong { "{profile.name}" } span { class: "muted", "AppID: {profile.appid}" } } span { class: "arrow", "›" } }
                                    div { class: "path-grid",
                                        PathLine { label: t(K::GameDirectory), value: profile.game_dir.clone() }
                                        PathLine { label: t(K::TargetProgram), value: profile.target.clone() }
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    rsx! {
        section { class: "panel",
            header { class: "panel-header",
                div { h1 { {t(K::Logs)} } p { {t(K::LogsHelp)} } }
                button { class: "button", "data-testid": "refresh-logs", onclick: on_refresh, {t(K::Refresh)} }
            }
            div { class: "list-stack",
                if logs.is_empty() {
                    EmptyState { title: t(K::EmptyLogs), description: t(K::EmptyLogsHelp) }
                } else {
                    for log in logs {
                        {
                            let content = if log.content.is_empty() {
                                t(K::EmptyLog).to_string()
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    let status_label = runner_status
        .as_ref()
        .map(|status| {
            if status.healthy {
                t(K::Installed)
            } else if status.needs_install {
                t(K::NotInstalled)
            } else if status.needs_update {
                t(K::UpdateNeeded)
            } else {
                t(K::CheckFailed)
            }
        })
        .unwrap_or(t(K::Reading));
    let runner_path = runner_status
        .as_ref()
        .map(|item| item.path.clone())
        .or_else(|| paths.as_ref().map(|item| item.runner_path.clone()))
        .unwrap_or_else(|| t(K::Reading).to_string());
    let bundled_hash = runner_status
        .as_ref()
        .and_then(|item| item.bundled_version.as_ref())
        .map(|hash| short_hash(hash))
        .unwrap_or_else(|| t(K::Unknown).to_string());
    rsx! {
        section { class: "panel", "data-testid": "app-paths",
            header { class: "panel-header",
                div { h1 { {t(K::Settings)} } p { {t(K::SettingsHelp)} } }
                div { class: "action-row",
                    button { class: "button", "data-testid": "refresh-runner-status", onclick: on_refresh_runner, {t(K::CheckRunner)} }
                    button { class: "button", "data-testid": "refresh-paths", onclick: on_refresh_paths, {t(K::RefreshPaths)} }
                }
            }
            article { class: "runner-card",
                div {
                    h2 { "SteamWrapper Runner" }
                    p { "data-testid": "runner-status", {format!("{} {status_label}", t(K::RunnerStatus))} }
                    p { class: "muted break-all", "data-testid": "runner-path", {format!("{} {runner_path}", t(K::RunnerPath))} }
                    p { class: "muted break-all", "data-testid": "runner-version",
                        {format!("{} {bundled_hash}", t(K::BundledHash))}
                    }
                    if let Some(error) = runner_status.as_ref().and_then(|item| item.last_error.as_ref()) {
                        p { class: "error", "data-testid": "runner-error", {error.message(language)} }
                    }
                }
                if runner_status.as_ref().is_some_and(|status| !status.healthy) {
                    button {
                        class: "button button--primary",
                        "data-testid": if runner_status.as_ref().is_some_and(|status| status.needs_install) { "runner-install" } else { "runner-repair" },
                        disabled: runner_busy,
                        onclick: on_install,
                        if runner_busy { {t(K::Working)} } else if runner_status.as_ref().is_some_and(|status| status.needs_install) { {t(K::InstallRunner)} } else { {t(K::RepairRunner)} }
                    }
                }
            }
            div { class: "path-grid",
                if let Some(paths) = paths {
                    PathCard { label: t(K::UserData), value: paths.app_data_dir }
                    PathCard { label: "profiles.toml", value: paths.profiles_path }
                    PathCard { label: t(K::StableRunner), value: paths.runner_path }
                    PathCard { label: t(K::LogsDirectory), value: paths.logs_dir }
                    PathCard { label: t(K::BackupsDirectory), value: paths.backups_dir }
                    PathCard { label: t(K::CacheDirectory), value: paths.cache_dir }
                } else {
                    EmptyState { title: t(K::EmptyPaths), description: t(K::EmptyPathsHelp) }
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
    let language = use_context::<Signal<Language>>()();
    let t = |key: K| key.text(language);
    let Some(game) = game else {
        return rsx! {};
    };
    let game_name = game.display_name(language);
    let game_directory = if game.install_dir.is_empty() {
        t(K::ChooseDirectory).to_string()
    } else {
        game.install_dir.clone()
    };
    rsx! {
        div { class: "dialog-backdrop", "data-testid": "config-dialog",
            article { class: "dialog-card", role: "dialog", "aria-modal": "true", "aria-label": t(K::ConfigureTarget),
                header { class: "dialog-header",
                    div { h1 { {t(K::ConfigureTarget)} } p { "{game_name} · AppID {game.appid}" } }
                    button { class: "icon-button", "data-testid": "close-config", "aria-label": t(K::CloseDialog), onclick: on_close, "×" }
                }
                div { class: "game-directory", strong { {t(K::GameDirectory)} } p { "{game_directory}" } }
                label { class: "field", span { {t(K::ActualProgram)} }
                    div { class: "file-input-row",
                        input {
                            r#type: "text",
                            "data-testid": "target-path",
                            "aria-label": t(K::ActualProgram),
                            value: "{target_path}",
                            placeholder: t(K::TargetPlaceholder),
                            oninput: move |event| on_target_change.call(event.value()),
                        }
                        label { class: "button file-button", {t(K::Browse)}
                            input { r#type: "file", "aria-label": t(K::Browse), accept: ".exe,.bat,.cmd,.sh,.desktop", onchange: on_choose_target }
                        }
                    }
                }
                div { class: "action-row",
                    button { class: "button button--primary", "data-testid": "save-profile", onclick: on_save, {t(K::SaveOptions)} }
                    button { class: "button", onclick: on_generate, {t(K::GenerateOptions)} }
                    button { class: "button button--disabled", disabled: true, {t(K::TestLater)} }
                }
                label { class: "field", span { {t(K::LaunchOptions)} }
                    textarea { "data-testid": "launch-option", "aria-label": t(K::LaunchOptions), readonly: true, value: "{launch_option}", placeholder: t(K::OptionsPlaceholder) }
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

fn refresh_profiles(profiles: &mut Signal<Vec<ConfiguredProfile>>, status: &mut Signal<Message>) {
    match services::list_profiles() {
        Ok(items) => profiles.set(items),
        Err(error) => status.set(Message::Error(K::ProfilesFailed, error)),
    }
}

fn refresh_logs(logs: &mut Signal<Vec<RunnerLogEntry>>, status: &mut Signal<Message>) {
    match services::list_logs() {
        Ok(items) => logs.set(items),
        Err(error) => status.set(Message::Error(K::LogsFailed, error)),
    }
}

fn refresh_paths(paths: &mut Signal<Option<AppPaths>>, status: &mut Signal<Message>) {
    match services::paths() {
        Ok(items) => paths.set(Some(items)),
        Err(error) => status.set(Message::Error(K::PathsFailed, error)),
    }
}

fn refresh_runner_status(
    status_signal: &mut Signal<Option<RunnerStatus>>,
    status: &mut Signal<Message>,
) {
    match services::runner_status() {
        Ok(item) => status_signal.set(Some(item)),
        Err(error) => status.set(Message::Error(K::RunnerCheckFailed, error)),
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

fn cover_url(path: &str) -> Option<String> {
    if path.starts_with("https://") {
        return Some(path.to_string());
    }
    file_url(path)
}

fn path_info(path: &str) -> PathInfo {
    let path = Path::new(path);
    let name = path
        .file_stem()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
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
    #[test]
    fn manually_added_game_defaults_to_english() {
        assert_eq!(super::GameDraft::manual().name, "Manually added game");
    }
    use super::{cover_url, file_url, path_info, short_hash};

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

    #[test]
    fn official_cover_url_is_used_without_local_file_canonicalization() {
        let url = "https://cdn.cloudflare.steamstatic.com/steam/apps/123456/library_600x900.jpg";
        assert_eq!(cover_url(url), Some(url.to_string()));
    }
}
