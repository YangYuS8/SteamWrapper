mod app;
mod i18n;
mod services;

use dioxus::desktop::{Config, LogicalSize, WindowBuilder};

fn main() {
    if let Err(error) = services::bootstrap() {
        eprintln!("failed to install SteamWrapper Runner during startup: {error}");
    }

    let icon =
        dioxus::desktop::icon_from_memory(include_bytes!("../assets/icons/steamwrapper.png"))
            .expect("the embedded SteamWrapper PNG must be a valid window icon");
    let config = Config::new()
        .with_window(
            WindowBuilder::new()
                .with_title("SteamWrapper Manager")
                .with_decorations(false)
                .with_inner_size(LogicalSize::new(1180.0, 760.0))
                .with_min_inner_size(LogicalSize::new(980.0, 680.0)),
        )
        .with_icon(icon);

    #[cfg(feature = "e2e")]
    let config = wdio_dioxus_embedded_driver::install(config);

    dioxus::LaunchBuilder::desktop()
        .with_cfg(config)
        .launch(app::App);
}
