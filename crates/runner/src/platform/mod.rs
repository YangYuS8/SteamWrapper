use anyhow::Context;
use std::process::Command;
use steamwrapper_core::{Profile, WaitMode};
use tracing::info;

pub fn launch_profile(profile: &Profile) -> anyhow::Result<u8> {
    let target = profile.resolve_target();
    let working_dir = profile.resolve_working_dir();

    let mut command = Command::new(&target);
    command.current_dir(&working_dir);
    command.args(&profile.args);

    info!(target = %target.display(), working_dir = %working_dir.display(), "starting target");

    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start target {}", target.display()))?;

    match profile.wait_mode {
        WaitMode::None => Ok(0),
        WaitMode::Root | WaitMode::Job | WaitMode::ProcessName | WaitMode::ProcessGroup => {
            // Initial v2 skeleton waits for the root process only.
            // Platform-specific Job Object / process group / process-name strategies will be added next.
            let status = child.wait().context("failed while waiting for target process")?;
            Ok(status.code().unwrap_or(0) as u8)
        }
    }
}

#[cfg(target_os = "windows")]
mod windows;

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
mod unix;
