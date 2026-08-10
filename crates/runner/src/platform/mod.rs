use anyhow::{bail, Context};
use std::{
    collections::HashSet,
    ffi::OsStr,
    process::{Command, ExitStatus},
    thread,
    time::{Duration, Instant},
};
use steamwrapper_core::{Profile, WaitMode};
use sysinfo::{ProcessesToUpdate, System};

const PROCESS_NAME_POLL_INTERVAL: Duration = Duration::from_millis(100);
const PROCESS_NAME_DISCOVERY_TIMEOUT: Duration = Duration::from_secs(30);
const PROCESS_NAME_EXIT_GRACE: Duration = Duration::from_millis(500);
const PROCESS_NAME_MAX_WAIT: Duration = Duration::from_secs(24 * 60 * 60);

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
        WaitMode::ProcessName => launch_process_name(command, profile.process_name.as_deref())?,
    };

    Ok(normalize_exit_code(status.code()))
}

fn launch_process_name(
    mut command: Command,
    process_name: Option<&str>,
) -> anyhow::Result<ExitStatus> {
    let process_name = process_name
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .context("process_name wait mode requires a non-empty process_name")?;
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let baseline = matching_processes(&system, process_name);

    let mut child = command
        .spawn()
        .context("failed to start process-name launcher")?;
    let launcher_status = child
        .wait()
        .context("failed while waiting for process-name launcher")?;

    let discovery_started = Instant::now();
    loop {
        system.refresh_processes(ProcessesToUpdate::All, true);
        if matching_processes(&system, process_name)
            .iter()
            .any(|identity| !baseline.contains(identity))
        {
            break;
        }
        if discovery_started.elapsed() >= PROCESS_NAME_DISCOVERY_TIMEOUT {
            bail!(
                "process named {process_name:?} did not appear within {} seconds",
                PROCESS_NAME_DISCOVERY_TIMEOUT.as_secs()
            );
        }
        thread::sleep(PROCESS_NAME_POLL_INTERVAL);
    }

    let wait_started = Instant::now();
    let mut empty_since = None;
    loop {
        system.refresh_processes(ProcessesToUpdate::All, true);
        let has_matching_process = matching_processes(&system, process_name)
            .iter()
            .any(|identity| !baseline.contains(identity));
        if has_matching_process {
            empty_since = None;
        } else {
            let empty_started = empty_since.get_or_insert_with(Instant::now);
            if empty_started.elapsed() >= PROCESS_NAME_EXIT_GRACE {
                break;
            }
        }
        if wait_started.elapsed() >= PROCESS_NAME_MAX_WAIT {
            bail!(
                "process named {process_name:?} was still alive after {} seconds",
                PROCESS_NAME_MAX_WAIT.as_secs()
            );
        }
        thread::sleep(PROCESS_NAME_POLL_INTERVAL);
    }

    Ok(launcher_status)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct ProcessIdentity {
    pid: sysinfo::Pid,
    start_time: u64,
}

fn matching_processes(system: &System, process_name: &str) -> HashSet<ProcessIdentity> {
    system
        .processes_by_exact_name(OsStr::new(process_name))
        .map(|process| ProcessIdentity {
            pid: process.pid(),
            start_time: process.start_time(),
        })
        .collect()
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
    #[cfg(target_os = "linux")]
    fn process_name_waits_for_a_new_named_process_after_launcher_exits() {
        use std::os::unix::fs::symlink;

        let root = TempDir::new("process-name");
        let named_process = root.path().join("sw-game-test");
        symlink("/bin/sleep", &named_process).expect("create named process fixture");
        let profile = Profile {
            name: "process name fixture".to_string(),
            app_id: Some("process-name-fixture".to_string()),
            platform: Some(Platform::Linux),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("/bin/sh"),
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "-c".to_string(),
                "\"$1\" 0.4 & exit 7".to_string(),
                "steamwrapper-process-name-test".to_string(),
                named_process.to_string_lossy().to_string(),
            ],
            wait_mode: WaitMode::ProcessName,
            process_name: Some("sw-game-test".to_string()),
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch process-name fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() >= Duration::from_millis(300),
            "runner returned before the named process exited"
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn process_name_ignores_matching_processes_that_existed_before_launch() {
        use std::os::unix::fs::symlink;

        let root = TempDir::new("process-name-baseline");
        let named_process = root.path().join("sw-game-base");
        symlink("/bin/sleep", &named_process).expect("create baseline process fixture");
        let mut existing = Command::new(&named_process)
            .arg("2")
            .spawn()
            .expect("start baseline process");
        let profile = Profile {
            name: "process name baseline fixture".to_string(),
            app_id: Some("process-name-baseline-fixture".to_string()),
            platform: Some(Platform::Linux),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("/bin/sh"),
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "-c".to_string(),
                "\"$1\" 0.4 & exit 7".to_string(),
                "steamwrapper-process-name-baseline-test".to_string(),
                named_process.to_string_lossy().to_string(),
            ],
            wait_mode: WaitMode::ProcessName,
            process_name: Some("sw-game-base".to_string()),
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch baseline exclusion fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() < Duration::from_millis(1500),
            "runner waited for the pre-existing matching process"
        );
        assert_eq!(existing.try_wait().unwrap(), None);
        existing.kill().expect("stop baseline process");
        existing.wait().expect("reap baseline process");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn process_name_waits_across_named_process_replacement() {
        use std::os::unix::fs::symlink;

        let root = TempDir::new("process-name-replacement");
        let named_process = root.path().join("sw-game-repl");
        symlink("/bin/sleep", &named_process).expect("create replacement process fixture");
        let profile = Profile {
            name: "process replacement fixture".to_string(),
            app_id: Some("process-name-replacement-fixture".to_string()),
            platform: Some(Platform::Linux),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("/bin/sh"),
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "-c".to_string(),
                "(\"$1\" 0.2; sleep 0.15; \"$1\" 0.35) & exit 7".to_string(),
                "steamwrapper-process-name-replacement-test".to_string(),
                named_process.to_string_lossy().to_string(),
            ],
            wait_mode: WaitMode::ProcessName,
            process_name: Some("sw-game-repl".to_string()),
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch process replacement fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() >= Duration::from_millis(450),
            "runner returned before the replacement process exited"
        );
    }

    #[test]
    fn process_name_requires_a_non_empty_name_before_launching() {
        let root = TempDir::new("process-name-missing");
        let marker = root.path().join("target-started.txt");
        let target = if cfg!(target_os = "windows") {
            PathBuf::from("C:\\Windows\\System32\\cmd.exe")
        } else {
            PathBuf::from("/bin/sh")
        };
        let profile = Profile {
            name: "missing process name fixture".to_string(),
            app_id: Some("process-name-missing-fixture".to_string()),
            platform: if cfg!(target_os = "windows") {
                Some(Platform::Windows)
            } else {
                Some(Platform::Linux)
            },
            game_dir: root.path().to_path_buf(),
            target,
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
                    "steamwrapper-process-name-missing-test".to_string(),
                    marker.to_string_lossy().to_string(),
                ]
            },
            wait_mode: WaitMode::ProcessName,
            process_name: Some("   ".to_string()),
        };

        let error = launch_profile(&profile).expect_err("empty process name must fail");

        assert!(error
            .to_string()
            .contains("requires a non-empty process_name"));
        assert!(
            !marker.exists(),
            "invalid profile still launched the target"
        );
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn process_name_waits_for_a_new_named_process_after_launcher_exits_on_windows() {
        let root = TempDir::new("process-name-windows");
        let test_binary = std::env::current_exe().expect("resolve current test binary");
        let script = format!(
            "$env:STEAMWRAPPER_PROCESS_NAME_TEST='1'; Start-Process -WindowStyle Hidden -FilePath '{}' -ArgumentList @('--exact','platform::tests::process_name_windows_descendant_fixture','--nocapture'); exit 7",
            test_binary.to_string_lossy().replace('\'', "''")
        );
        let profile = Profile {
            name: "Windows process name fixture".to_string(),
            app_id: Some("process-name-windows-fixture".to_string()),
            platform: Some(Platform::Windows),
            game_dir: root.path().to_path_buf(),
            target: PathBuf::from("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            working_dir: Some(PathBuf::from(".")),
            args: vec!["-NoProfile".to_string(), "-Command".to_string(), script],
            wait_mode: WaitMode::ProcessName,
            process_name: Some(
                test_binary
                    .file_name()
                    .expect("test binary file name")
                    .to_string_lossy()
                    .to_string(),
            ),
        };

        let started = Instant::now();
        let exit_code = launch_profile(&profile).expect("launch Windows process-name fixture");

        assert_eq!(exit_code, 7);
        assert!(
            started.elapsed() >= Duration::from_millis(300),
            "runner returned before the named process exited"
        );
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn process_name_windows_descendant_fixture() {
        if std::env::var_os("STEAMWRAPPER_PROCESS_NAME_TEST").is_none() {
            return;
        }

        std::thread::sleep(Duration::from_millis(400));
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
        fs::write(root.path().join("job-object-fixture.enabled"), "enabled")
            .expect("enable Job Object fixture");
        let test_binary = std::env::current_exe().expect("resolve current test binary");
        let profile = Profile {
            name: "job object fixture".to_string(),
            app_id: Some("job-object-fixture".to_string()),
            platform: Some(Platform::Windows),
            game_dir: root.path().to_path_buf(),
            target: test_binary,
            working_dir: Some(PathBuf::from(".")),
            args: vec![
                "--exact".to_string(),
                "platform::tests::job_object_launcher_fixture".to_string(),
                "--nocapture".to_string(),
            ],
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
    fn job_object_launcher_fixture() {
        let working_dir = std::env::current_dir().expect("resolve fixture working directory");
        if !working_dir.join("job-object-fixture.enabled").exists() {
            return;
        }

        Command::new(std::env::current_exe().expect("resolve descendant test binary"))
            .args([
                "--exact",
                "platform::tests::job_object_descendant_fixture",
                "--nocapture",
            ])
            .spawn()
            .expect("start Job Object descendant fixture");

        std::process::exit(7);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn job_object_descendant_fixture() {
        let working_dir = std::env::current_dir().expect("resolve fixture working directory");
        if !working_dir.join("job-object-fixture.enabled").exists() {
            return;
        }

        std::thread::sleep(Duration::from_millis(400));
        fs::write(working_dir.join("descendant-finished.txt"), "done")
            .expect("write Job Object descendant marker");
    }
}

#[cfg(target_os = "windows")]
mod windows;

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
mod unix;
