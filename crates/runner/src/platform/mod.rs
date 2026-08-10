use anyhow::{bail, Context};
use std::process::Command;
use steamwrapper_core::{Profile, WaitMode};

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

    if profile.wait_mode == WaitMode::ProcessName {
        bail!("process_name wait mode is not implemented yet; use root, job, or process_group");
    }

    let mut command = Command::new(&target);
    command.current_dir(&working_dir);
    command.args(&profile.args);
    prepare_command(&mut command);

    let status = match profile.wait_mode {
        WaitMode::None => {
            command
                .spawn()
                .with_context(|| format!("failed to start target {}", target.display()))?;
            return Ok(0);
        }
        WaitMode::Root => {
            let mut child = command
                .spawn()
                .with_context(|| format!("failed to start target {}", target.display()))?;
            child
                .wait()
                .context("failed while waiting for target process")?
        }
        WaitMode::Job => launch_job(command)?,
        WaitMode::ProcessGroup => launch_process_group(command)?,
        WaitMode::ProcessName => unreachable!("process_name mode is rejected before spawn"),
    };

    Ok(normalize_exit_code(status.code()))
}

fn prepare_command(command: &mut Command) {
    #[cfg(target_os = "windows")]
    windows::prepare_command(command);

    #[cfg(not(target_os = "windows"))]
    let _ = command;
}

#[cfg(target_os = "windows")]
fn launch_job(command: Command) -> anyhow::Result<std::process::ExitStatus> {
    windows::launch_job(command)
}

#[cfg(not(target_os = "windows"))]
fn launch_job(_command: Command) -> anyhow::Result<std::process::ExitStatus> {
    bail!("job wait mode is only supported on Windows")
}

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
fn launch_process_group(command: Command) -> anyhow::Result<std::process::ExitStatus> {
    unix::launch_process_group(command)
}

#[cfg(not(any(target_os = "linux", target_os = "freebsd")))]
fn launch_process_group(_command: Command) -> anyhow::Result<std::process::ExitStatus> {
    bail!("process_group wait mode is only supported on Unix-like systems")
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        path::{Path, PathBuf},
        time::{Duration, Instant, SystemTime, UNIX_EPOCH},
    };
    use steamwrapper_core::Platform;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time before Unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!("steamwrapper-{label}-{nonce}"));
            fs::create_dir_all(&path).expect("create test directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn process_group_waits_for_descendants_after_launcher_exits() {
        let root = TempDir::new("process-group");
        let marker = root.path().join("descendant-finished.txt");
        let profile = Profile {
            name: "process group fixture".to_string(),
            app_id: Some("process-group-fixture".to_string()),
            platform: Some(Platform::Linux),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("/bin/sh"),
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "-c".to_string(),
                "(sleep 0.4; printf done > \"$1\") & exit 7".to_string(),
                "steamwrapper-process-group-test".to_string(),
                marker.to_string_lossy().to_string(),
            ],
            wait_mode: WaitMode::ProcessGroup,
            process_name: None,
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch process group fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() >= Duration::from_millis(300),
            "runner returned before the descendant process exited"
        );
        assert_eq!(fs::read_to_string(marker).unwrap(), "done");
    }

    #[test]
    fn process_name_mode_fails_before_launching_the_target() {
        let root = TempDir::new("process-name");
        let marker = root.path().join("target-started.txt");
        let profile = Profile {
            name: "process name fixture".to_string(),
            app_id: Some("process-name-fixture".to_string()),
            platform: if cfg!(target_os = "windows") {
                Some(Platform::Windows)
            } else {
                Some(Platform::Linux)
            },
            game_dir: root.path().to_path_buf(),
            target: if cfg!(target_os = "windows") {
                PathBuf::from("C:\\Windows\\System32\\cmd.exe")
            } else {
                PathBuf::from("/bin/sh")
            },
            working_dir: Some(PathBuf::from(".")),
            args: if cfg!(target_os = "windows") {
                vec![
                    "/c".to_string(),
                    format!("echo started>\"{}\"", marker.display()),
                ]
            } else {
                vec![
                    "-c".to_string(),
                    "printf started > \"$1\"".to_string(),
                    "steamwrapper-process-name-test".to_string(),
                    marker.to_string_lossy().to_string(),
                ]
            },
            wait_mode: WaitMode::ProcessName,
            process_name: Some("game.exe".to_string()),
        };

        let error = launch_profile(&profile).expect_err("process_name must fail explicitly");

        assert!(error
            .to_string()
            .contains("process_name wait mode is not implemented"));
        assert!(
            !marker.exists(),
            "unsupported mode still launched the target"
        );
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn job_mode_fails_before_launching_the_target_on_unsupported_platforms() {
        let root = TempDir::new("job-unsupported");
        let marker = root.path().join("target-started.txt");
        let profile = Profile {
            name: "job fixture".to_string(),
            app_id: Some("job-fixture".to_string()),
            platform: Some(Platform::Linux),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("/bin/sh"),
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "-c".to_string(),
                "printf started > \"$1\"".to_string(),
                "steamwrapper-job-test".to_string(),
                marker.to_string_lossy().to_string(),
            ],
            wait_mode: WaitMode::Job,
            process_name: None,
        };

        let error = launch_profile(&profile).expect_err("job mode must reject unsupported hosts");

        assert!(error
            .to_string()
            .contains("job wait mode is only supported on Windows"));
        assert!(
            !marker.exists(),
            "unsupported mode still launched the target"
        );
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn job_object_waits_for_descendants_after_launcher_exits() {
        let root = TempDir::new("job-object");
        let marker = root.path().join("descendant-finished.txt");
        let test_binary = std::env::current_exe().expect("resolve current test binary");
        let script = format!(
            "$env:STEAMWRAPPER_JOB_TEST_MARKER='{}'; Start-Process -WindowStyle Hidden -FilePath '{}' -ArgumentList @('--exact','platform::tests::job_object_descendant_fixture','--nocapture'); exit 7",
            marker.to_string_lossy().replace('\'', "''"),
            test_binary.to_string_lossy().replace('\'', "''")
        );
        let profile = Profile {
            name: "job object fixture".to_string(),
            app_id: Some("job-object-fixture".to_string()),
            platform: Some(Platform::Windows),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            working_dir: Some(PathBuf::from(".")),
            args: vec!["-NoProfile".to_string(), "-Command".to_string(), script],
            wait_mode: WaitMode::Job,
            process_name: None,
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch Job Object fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() >= Duration::from_millis(300),
            "runner returned before the descendant process exited"
        );
        assert_eq!(fs::read_to_string(marker).unwrap(), "done");
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn job_object_descendant_fixture() {
        let Some(marker) = std::env::var_os("STEAMWRAPPER_JOB_TEST_MARKER") else {
            return;
        };

        std::thread::sleep(Duration::from_millis(400));
        fs::write(marker, "done").expect("write Job Object descendant marker");
    }
}

#[cfg(target_os = "windows")]
mod windows;

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
mod unix;
