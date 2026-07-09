use anyhow::{bail, Context};
use std::process::Command;
use steamwrapper_core::{Profile, WaitMode};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

pub fn launch_profile(profile: &Profile) -> anyhow::Result<u8> {
    let target = profile.resolve_target();
    let working_dir = profile.resolve_working_dir();

    if !target.exists() {
        bail!("target executable does not exist: {}", target.display());
    }

    if !working_dir.exists() {
        bail!(
            "working directory does not exist: {}",
            working_dir.display()
        );
    }

    let mut command = Command::new(&target);
    command.current_dir(&working_dir);
    command.args(&profile.args);

    #[cfg(target_os = "windows")]
    {
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start target {}", target.display()))?;

    match profile.wait_mode {
        WaitMode::None => Ok(0),
        WaitMode::Root | WaitMode::Job | WaitMode::ProcessName | WaitMode::ProcessGroup => {
            // v2.0 provides the reliable root-process baseline.
            // Job Object, process-name and process-group strategies are planned follow-ups.
            let status = child
                .wait()
                .context("failed while waiting for target process")?;
            Ok(normalize_exit_code(status.code()))
        }
    }
}

fn normalize_exit_code(code: Option<i32>) -> u8 {
    let code = code.unwrap_or(0);
    if code < 0 {
        1
    } else if code > u8::MAX as i32 {
        u8::MAX
    } else {
        code as u8
    }
}

#[cfg(target_os = "windows")]
mod windows;

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
mod unix;
