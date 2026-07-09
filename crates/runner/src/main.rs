mod platform;

use anyhow::Context;
use clap::Parser;
use std::path::PathBuf;
use std::process::ExitCode;
use steamwrapper_core::SteamWrapperConfig;
use tracing::{error, info};

#[derive(Debug, Parser)]
#[command(name = "steamwrapper-runner")]
#[command(about = "Headless runtime launcher called by Steam")]
struct Args {
    /// Steam app id used to find the profile.
    #[arg(long)]
    appid: String,

    /// Optional explicit config path. Defaults to ./profiles.toml for the initial skeleton.
    #[arg(long)]
    config: Option<PathBuf>,

    /// Original command expanded by Steam after `-- %command%`.
    #[arg(last = true)]
    steam_command: Vec<String>,
}

fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_target(false)
        .without_time()
        .init();

    match run() {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            error!("{err:#}");
            ExitCode::from(1)
        }
    }
}

fn run() -> anyhow::Result<u8> {
    let args = Args::parse();
    let config_path = args.config.unwrap_or_else(|| PathBuf::from("profiles.toml"));

    let config = SteamWrapperConfig::load(&config_path)
        .with_context(|| format!("failed to load config from {}", config_path.display()))?;

    let (profile_key, profile) = config
        .require_profile_by_appid(&args.appid)
        .with_context(|| format!("no SteamWrapper profile for appid {}", args.appid))?;

    info!(profile = profile_key, appid = args.appid, "launching profile");
    if !args.steam_command.is_empty() {
        info!(steam_command = ?args.steam_command, "received original Steam command");
    }

    platform::launch_profile(profile)
}
