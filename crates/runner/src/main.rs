mod platform;

use anyhow::Context;
use clap::Parser;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::process::ExitCode;
use steamwrapper_core::{default_profiles_path, ensure_app_dirs, SteamWrapperConfig};

#[derive(Debug, Parser)]
#[command(name = "steamwrapper-runner")]
#[command(about = "Headless runtime launcher called by Steam")]
struct Args {
    /// Steam app id used to find the profile.
    #[arg(long)]
    appid: String,

    /// Optional explicit config path. Defaults to the stable SteamWrapper data directory.
    #[arg(long)]
    config: Option<PathBuf>,

    /// Original command expanded by Steam after `-- %command%`.
    #[arg(last = true)]
    steam_command: Vec<String>,
}

struct RuntimeLog {
    file: Option<File>,
}

impl RuntimeLog {
    fn open(appid: &str) -> Self {
        let _ = ensure_app_dirs();
        let path = steamwrapper_core::app_data_dir()
            .join("logs")
            .join(format!("runner-{appid}.log"));

        let file = OpenOptions::new().create(true).append(true).open(path).ok();
        Self { file }
    }

    fn line(&mut self, message: impl AsRef<str>) {
        if let Some(file) = &mut self.file {
            let _ = writeln!(file, "{}", message.as_ref());
        }
    }
}

fn main() -> ExitCode {
    let args = Args::parse();
    let mut log = RuntimeLog::open(&args.appid);

    match run(args, &mut log) {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            log.line(format!("ERROR: {err:#}"));
            eprintln!("SteamWrapperRunner error: {err:#}");
            ExitCode::from(1)
        }
    }
}

fn run(args: Args, log: &mut RuntimeLog) -> anyhow::Result<u8> {
    let config_path = args.config.unwrap_or_else(default_profiles_path);
    log.line(format!("Loading config: {}", config_path.display()));

    let config = SteamWrapperConfig::load(&config_path)
        .with_context(|| format!("failed to load config from {}", config_path.display()))?;

    let (profile_key, profile) = config
        .require_profile_by_appid(&args.appid)
        .with_context(|| format!("no SteamWrapper profile for appid {}", args.appid))?;

    log.line(format!("Launching profile: {profile_key}"));
    if !args.steam_command.is_empty() {
        log.line(format!("Original Steam command: {:?}", args.steam_command));
    }

    let exit_code = platform::launch_profile(profile)
        .with_context(|| format!("failed to launch profile {profile_key}"))?;
    log.line(format!("Profile exited with code: {exit_code}"));
    Ok(exit_code)
}
