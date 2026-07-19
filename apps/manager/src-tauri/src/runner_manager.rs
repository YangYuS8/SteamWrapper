use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

static TEMP_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone)]
pub struct RunnerPaths {
    bundled: PathBuf,
    stable: PathBuf,
}

impl RunnerPaths {
    pub fn new(bundled: impl Into<PathBuf>, stable: impl Into<PathBuf>) -> Self {
        Self {
            bundled: bundled.into(),
            stable: stable.into(),
        }
    }

    pub fn bundled(&self) -> &Path {
        &self.bundled
    }

    pub fn stable(&self) -> &Path {
        &self.stable
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct RunnerStatus {
    pub installed: bool,
    pub healthy: bool,
    pub path: String,
    pub bundled_version: Option<String>,
    pub installed_version: Option<String>,
    pub needs_install: bool,
    pub needs_update: bool,
    pub last_error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RunnerInstallOutcome {
    pub changed: bool,
    pub status: RunnerStatus,
}

pub fn inspect_runner(paths: &RunnerPaths) -> RunnerStatus {
    let path = paths.stable().to_string_lossy().to_string();
    let installed = paths.stable().is_file();

    let bundled_version = match sha256_file(paths.bundled()) {
        Ok(hash) => hash,
        Err(err) => {
            return RunnerStatus {
                installed,
                healthy: false,
                path,
                bundled_version: None,
                installed_version: installed
                    .then(|| sha256_file(paths.stable()).ok())
                    .flatten(),
                needs_install: !installed,
                needs_update: false,
                last_error: Some(format!("无法读取随包 Runner：{err}")),
            };
        }
    };

    if !installed {
        return RunnerStatus {
            installed: false,
            healthy: false,
            path,
            bundled_version: Some(bundled_version),
            installed_version: None,
            needs_install: true,
            needs_update: false,
            last_error: None,
        };
    }

    match sha256_file(paths.stable()) {
        Ok(installed_version) => {
            let healthy = bundled_version == installed_version;
            RunnerStatus {
                installed: true,
                healthy,
                path,
                bundled_version: Some(bundled_version),
                installed_version: Some(installed_version),
                needs_install: false,
                needs_update: !healthy,
                last_error: None,
            }
        }
        Err(err) => RunnerStatus {
            installed: true,
            healthy: false,
            path,
            bundled_version: Some(bundled_version),
            installed_version: None,
            needs_install: false,
            needs_update: true,
            last_error: Some(format!("无法检查已安装 Runner：{err}")),
        },
    }
}

pub fn install_or_repair(paths: &RunnerPaths) -> Result<RunnerInstallOutcome, String> {
    install_or_repair_with_replace(paths, replace_file)
}

fn install_or_repair_with_replace<F>(
    paths: &RunnerPaths,
    replace: F,
) -> Result<RunnerInstallOutcome, String>
where
    F: FnOnce(&Path, &Path) -> io::Result<()>,
{
    let status = inspect_runner(paths);
    if status.healthy {
        return Ok(RunnerInstallOutcome {
            changed: false,
            status,
        });
    }

    let expected_hash = status.bundled_version.clone().ok_or_else(|| {
        status
            .last_error
            .clone()
            .unwrap_or_else(|| "随包 Runner 不可用".to_string())
    })?;

    copy_runner_atomically(paths.bundled(), paths.stable(), &expected_hash, replace).map_err(
        |err| {
            format!(
                "无法安装或修复 Runner 到 {}：{err}",
                paths.stable().display()
            )
        },
    )?;

    let status = inspect_runner(paths);
    if !status.healthy {
        return Err(status
            .last_error
            .unwrap_or_else(|| "Runner 写入后校验失败".to_string()));
    }

    Ok(RunnerInstallOutcome {
        changed: true,
        status,
    })
}

fn sha256_file(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];

    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

fn copy_runner_atomically(
    source: &Path,
    destination: &Path,
    expected_hash: &str,
    replace: impl FnOnce(&Path, &Path) -> io::Result<()>,
) -> io::Result<()> {
    let parent = destination.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "Runner stable path has no parent: {}",
                destination.display()
            ),
        )
    })?;
    fs::create_dir_all(parent)?;

    let temporary = unique_temporary_path(parent, destination.file_name().unwrap_or_default())?;
    let result = (|| {
        let mut source_file = File::open(source)?;
        let mut temporary_file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        io::copy(&mut source_file, &mut temporary_file)?;
        temporary_file.flush()?;
        temporary_file.sync_all()?;
        drop(temporary_file);

        #[cfg(unix)]
        fs::set_permissions(&temporary, fs::metadata(source)?.permissions())?;

        let temporary_hash = sha256_file(&temporary)?;
        if temporary_hash != expected_hash {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "temporary Runner hash does not match the bundled resource",
            ));
        }

        replace(&temporary, destination)
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn unique_temporary_path(parent: &Path, file_name: &std::ffi::OsStr) -> io::Result<PathBuf> {
    for _ in 0..16 {
        let sequence = TEMP_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
        let candidate = parent.join(format!(
            ".{}.tmp-{}-{}",
            file_name.to_string_lossy(),
            std::process::id(),
            sequence
        ));
        if !candidate.exists() {
            return Ok(candidate);
        }
    }

    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not allocate a temporary Runner path",
    ))
}

#[cfg(not(target_os = "windows"))]
fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(temporary, destination)
}

#[cfg(target_os = "windows")]
fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
    };

    let temporary_wide: Vec<u16> = temporary
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let destination_wide: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let result = unsafe {
        MoveFileExW(
            temporary_wide.as_ptr(),
            destination_wide.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };

    if result == 0 {
        return Err(io::Error::new(
            io::Error::last_os_error().kind(),
            format!(
                "Windows refused to replace the existing Runner (it may still be in use): {}",
                io::Error::last_os_error()
            ),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{inspect_runner, install_or_repair, install_or_repair_with_replace, RunnerPaths};
    use std::{
        fs,
        path::{Path, PathBuf},
        time::{SystemTime, UNIX_EPOCH},
    };

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

    fn write(path: &Path, contents: &[u8]) {
        fs::create_dir_all(path.parent().expect("test path has parent"))
            .expect("create parent directory");
        fs::write(path, contents).expect("write fixture file");
    }

    #[test]
    fn installs_missing_runner_without_touching_user_data() {
        let root = TempDir::new("runner-install");
        let bundled = root.path().join("bundle/SteamWrapperRunner.exe");
        let app_data = root.path().join("SteamWrapper");
        let stable = app_data.join("bin/SteamWrapperRunner.exe");
        write(&bundled, b"runner-v1");
        write(&app_data.join("profiles.toml"), b"[profiles]\n");
        write(&app_data.join("logs/keep.log"), b"keep logs");
        write(&app_data.join("backups/keep.toml"), b"keep backups");
        write(&app_data.join("cache/keep.txt"), b"keep cache");

        let paths = RunnerPaths::new(&bundled, &stable);
        assert!(inspect_runner(&paths).needs_install);

        let outcome = install_or_repair(&paths).expect("install missing runner");
        assert!(outcome.changed);
        assert_eq!(fs::read(&stable).expect("installed runner"), b"runner-v1");
        assert!(inspect_runner(&paths).healthy);
        assert_eq!(
            fs::read(app_data.join("profiles.toml")).unwrap(),
            b"[profiles]\n"
        );
        assert_eq!(
            fs::read(app_data.join("logs/keep.log")).unwrap(),
            b"keep logs"
        );
        assert_eq!(
            fs::read(app_data.join("backups/keep.toml")).unwrap(),
            b"keep backups"
        );
        assert_eq!(
            fs::read(app_data.join("cache/keep.txt")).unwrap(),
            b"keep cache"
        );
    }

    #[test]
    fn leaves_a_matching_runner_in_place() {
        let root = TempDir::new("runner-unchanged");
        let bundled = root.path().join("bundle/SteamWrapperRunner.exe");
        let stable = root.path().join("SteamWrapper/bin/SteamWrapperRunner.exe");
        write(&bundled, b"runner-v1");
        write(&stable, b"runner-v1");

        let paths = RunnerPaths::new(&bundled, &stable);
        let outcome = install_or_repair(&paths).expect("check matching runner");

        assert!(!outcome.changed);
        assert!(outcome.status.healthy);
        assert_eq!(fs::read(stable).unwrap(), b"runner-v1");
    }

    #[test]
    fn repairs_a_corrupted_runner_with_no_temporary_file_left_behind() {
        let root = TempDir::new("runner-repair");
        let bundled = root.path().join("bundle/SteamWrapperRunner.exe");
        let stable = root.path().join("SteamWrapper/bin/SteamWrapperRunner.exe");
        write(&bundled, b"runner-v2");
        write(&stable, b"corrupted");

        let paths = RunnerPaths::new(&bundled, &stable);
        let before = inspect_runner(&paths);
        assert!(before.needs_update);
        assert!(!before.healthy);

        let outcome = install_or_repair(&paths).expect("repair corrupted runner");
        assert!(outcome.changed);
        assert!(outcome.status.healthy);
        assert_eq!(fs::read(&stable).unwrap(), b"runner-v2");

        let leftovers: Vec<_> = fs::read_dir(stable.parent().unwrap())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.contains(".tmp-"))
            .collect();
        assert!(
            leftovers.is_empty(),
            "temporary runner files remain: {leftovers:?}"
        );
    }

    #[test]
    fn reports_windows_replacement_failure_without_destroying_the_existing_runner() {
        let root = TempDir::new("runner-locked");
        let bundled = root.path().join("bundle/SteamWrapperRunner.exe");
        let stable = root.path().join("SteamWrapper/bin/SteamWrapperRunner.exe");
        write(&bundled, b"runner-v2");
        write(&stable, b"runner-v1");

        let paths = RunnerPaths::new(&bundled, &stable);
        let result = install_or_repair_with_replace(&paths, |_temporary, _destination| {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "Runner is in use",
            ))
        });

        assert!(result.is_err());
        assert_eq!(fs::read(&stable).unwrap(), b"runner-v1");
        let leftovers: Vec<_> = fs::read_dir(stable.parent().unwrap())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.contains(".tmp-"))
            .collect();
        assert!(leftovers.is_empty());
    }

    #[test]
    fn reports_a_missing_bundled_runner_without_creating_a_stable_runner() {
        let root = TempDir::new("runner-missing-resource");
        let bundled = root.path().join("bundle/SteamWrapperRunner.exe");
        let stable = root.path().join("SteamWrapper/bin/SteamWrapperRunner.exe");
        let paths = RunnerPaths::new(&bundled, &stable);

        let status = inspect_runner(&paths);
        assert!(!status.healthy);
        assert!(status.last_error.is_some());
        assert!(install_or_repair(&paths).is_err());
        assert!(!stable.exists());
    }
}
