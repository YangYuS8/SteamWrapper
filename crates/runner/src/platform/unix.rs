use anyhow::Context;
use nix::{errno::Errno, sys::signal::killpg, unistd::Pid};
use std::{
    os::unix::process::CommandExt,
    process::{Command, ExitStatus},
    thread,
    time::{Duration, Instant},
};

const PROCESS_GROUP_POLL_INTERVAL: Duration = Duration::from_millis(50);
const PROCESS_GROUP_MAX_WAIT: Duration = Duration::from_secs(24 * 60 * 60);

pub(super) fn launch_process_group(mut command: Command) -> anyhow::Result<ExitStatus> {
    command.process_group(0);
    let mut child = command
        .spawn()
        .context("failed to start process-group target")?;
    let process_group = Pid::from_raw(
        i32::try_from(child.id()).context("target process id does not fit a Unix process id")?,
    );
    let status = child
        .wait()
        .context("failed while waiting for process-group leader")?;
    let wait_started = Instant::now();

    loop {
        match killpg(process_group, None) {
            Ok(()) | Err(Errno::EPERM) if wait_started.elapsed() < PROCESS_GROUP_MAX_WAIT => {
                thread::sleep(PROCESS_GROUP_POLL_INTERVAL)
            }
            Ok(()) | Err(Errno::EPERM) => {
                anyhow::bail!(
                    "process group {process_group} was still alive after {} seconds",
                    PROCESS_GROUP_MAX_WAIT.as_secs()
                )
            }
            Err(Errno::ESRCH) => break,
            Err(err) => {
                return Err(std::io::Error::from(err))
                    .context("failed while checking the target process group")
            }
        }
    }

    Ok(status)
}
