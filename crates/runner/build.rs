use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-env-changed=WindowsSdkDir");
    println!("cargo:rerun-if-env-changed=ProgramFiles(x86)");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    if env::var("CARGO_CFG_TARGET_ENV").as_deref() != Ok("msvc") {
        println!("cargo:warning=Runner PE signing metadata currently requires the supported Windows MSVC toolchain; the existing non-MSVC build remains unchanged.");
        return;
    }

    let version = env::var("CARGO_PKG_VERSION").expect("Cargo provides the Runner version");
    let parts: Vec<u16> = version
        .split('.')
        .map(|value| {
            value
                .parse::<u16>()
                .expect("Runner requires a numeric Windows version")
        })
        .collect();
    assert_eq!(
        parts.len(),
        3,
        "Runner requires a three-part product version"
    );
    let numeric = format!("{},{},{},0", parts[0], parts[1], parts[2]);
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo provides OUT_DIR"));
    let resource = output.join("SteamWrapperRunner.rc");
    let compiled = output.join("SteamWrapperRunner.res");
    let content = format!(
        r#"1 VERSIONINFO
FILEVERSION {numeric}
PRODUCTVERSION {numeric}
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS 0x40004L
FILETYPE 0x1L
FILESUBTYPE 0x0L
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904b0"
        BEGIN
            VALUE "FileDescription", "SteamWrapper headless Steam game runner\0"
            VALUE "FileVersion", "{version}\0"
            VALUE "InternalName", "SteamWrapperRunner\0"
            VALUE "LegalCopyright", "SteamWrapper contributors; Apache-2.0\0"
            VALUE "OriginalFilename", "SteamWrapperRunner.exe\0"
            VALUE "ProductName", "SteamWrapper\0"
            VALUE "ProductVersion", "{version}\0"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x0409, 1200
    END
END
"#
    );
    fs::write(&resource, content).expect("write the Runner version resource");
    let compiler = windows_resource_compiler();
    let status = Command::new(&compiler)
        .arg("/nologo")
        .arg("/fo")
        .arg(&compiled)
        .arg(&resource)
        .status()
        .unwrap_or_else(|error| {
            panic!("start official Windows SDK resource compiler {compiler:?}: {error}")
        });
    assert!(status.success(), "Windows SDK resource compiler failed");
    println!(
        "cargo:rustc-link-arg-bin=steamwrapper-runner={}",
        compiled.display()
    );
}

fn windows_resource_compiler() -> PathBuf {
    // Use the Windows SDK selected by .vsconfig. RC is build-time tooling only;
    // no resource/build helper is shipped with the headless Runner.
    let host = env::var("HOST").expect("Cargo provides HOST");
    let architecture = if host.starts_with("aarch64") {
        "arm64"
    } else {
        "x64"
    };
    let mut roots = Vec::new();
    if let Some(root) = env::var_os("WindowsSdkDir") {
        roots.push(PathBuf::from(root));
    }
    if let Some(root) = env::var_os("ProgramFiles(x86)") {
        roots.push(Path::new(&root).join("Windows Kits/10"));
    }
    for root in roots {
        let compiler = root
            .join("bin/10.0.26100.0")
            .join(architecture)
            .join("rc.exe");
        if compiler.is_file() {
            return compiler;
        }
    }
    panic!("Windows SDK 10.0.26100.0 rc.exe is required for Runner PE metadata. Install the .vsconfig SDK components with the official Build Tools installer.");
}
