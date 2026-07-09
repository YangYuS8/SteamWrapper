use std::path::Path;

pub fn build_launch_option(runner_path: impl AsRef<Path>, appid: &str) -> String {
    let runner = quote_path(runner_path.as_ref());
    format!("{runner} --appid {} -- %command%", quote_arg(appid))
}

fn quote_path(path: &Path) -> String {
    quote_arg(&path.to_string_lossy())
}

fn quote_arg(value: &str) -> String {
    let escaped = value.replace('"', "\\\"");
    format!("\"{escaped}\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_steam_launch_option() {
        let launch_option = build_launch_option(r"C:\Tools\SteamWrapperRunner.exe", "123456");
        assert_eq!(
            launch_option,
            r#""C:\Tools\SteamWrapperRunner.exe" --appid "123456" -- %command%"#
        );
    }
}
