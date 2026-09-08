# Contributing to SteamWrapper

English | [简体中文](CONTRIBUTING.zh-CN.md)

SteamWrapper v2 is a Windows-first configuration Manager and an independent Rust Runner. Read the [README](README.md), [architecture](https://yangyus8.top/SteamWrapper/development/architecture/), and [roadmap](https://yangyus8.top/SteamWrapper/project/roadmap/) before changing a product boundary. The WinUI Manager is a preview; Dioxus and its existing workflows remain the migration baseline until the Windows delivery gates pass.

## Issues and proposals

Search [existing issues](https://github.com/YangYuS8/SteamWrapper/issues) first. Use the bug, feature, or help template and identify the version or commit, branch, platform, and Manager implementation. Template files are maintained on `v2`; GitHub's live template chooser uses the default branch. English is the project's primary language; English and Simplified Chinese reports are welcome.

For a bug, explain what you expected, what happened, and the smallest reproducible steps. Include only relevant, redacted log excerpts. A fake Steam library and a small process fixture are preferable to uploading a game, Steam account data, or saved progress. Use [SECURITY.md](SECURITY.md) for suspected vulnerabilities and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Discuss changes to profile formats, Runner CLI behavior, supported platforms, packaging, or external services before a large implementation. A proposal is not a commitment to deliver or accept it.

## Branch and development setup

Target `v2` for v2 pull requests. The repository's GitHub default branch is currently `main`, so check the pull request base explicitly. Do not mix the legacy implementation on `main` into a v2 change.

Manage development tools through the checked-in `mise.toml` and `mise.lock`; keep the .NET pin aligned with `global.json`. Follow [Windows development](https://yangyus8.top/SteamWrapper/development/windows/) for the official MSVC/SDK prerequisites and mise commands. For WinUI changes, start with:

```powershell
mise run winui:test
mise run winui:contracts
```

Choose further checks from [testing](https://yangyus8.top/SteamWrapper/development/testing/). Documentation-only changes need translation and link review, not an artificial full build. Existing CI and release gates still apply; do not weaken a gate to hide a failure. Report passed, failed, blocked, and not-run checks accurately.

## Implementation boundaries

For documentation-site changes, run `mise run docs:check` and `mise run docs:build`. Review both languages in the production preview, including search and navigation. See the [documentation workflow](https://yangyus8.top/SteamWrapper/development/documentation/); application builds are not required for prose-only edits.

- Manager configures profiles; Steam starts the independent, headless Runner. A normal game launch must not show Manager.
- Preserve TOML compatibility, stable data paths, Runner CLI meaning, and `"<stable-runner-path>" --appid "<appid>" -- %command%`.
- Preserve unedited and unknown configuration fields. Do not replace syntax-preserving edits with whole-model serialization.
- Keep process lifecycle behavior and its real process tests in Runner/platform code.
- Keep English as the default UI/documentation language and maintain complete Simplified Chinese counterparts. Update both language resources and document pairs when meaning changes; identifiers, protocol fields, commands, and literal evidence remain exact.
- Keep the canonical SVG/PNG/ICO assets and their Dioxus copies consistent. After editing the source SVG, run `mise run brand:generate` and `mise run brand:check`. pnpm / `@resvg/resvg-js` are development asset tooling, not application runtime dependencies. Use original artwork and respect third-party trademarks.

## Protect player data

Automated tests must use disposable Steam and user-data fixtures. Do not run tests against another person's real library without their explicit authorization. Never patch, replace, verify through Steam, uninstall, or clear game files as a routine test step. Steam verification can replace third-party translations.

For an authorized live acceptance session, preserve the selected game's previous Launch Options, restore them afterward, and compare file inventories/hashes according to the [live validation procedure](https://yangyus8.top/SteamWrapper/project/validation/steam/). Stop on unresolved save or cloud conflicts. Do not upload credentials, account configuration, saves, game binaries, or unredacted personal paths. Keep generated user data and local evidence out of commits.

## Pull requests

Keep a pull request focused. Explain the user-visible problem, resulting behavior, relevant tests, and remaining limitations. Include screenshots for visible UI changes, with personal information removed. Update both language versions of affected documentation, and distinguish implementation from proposals and verified platform evidence.

Use the [pull request template](.github/PULL_REQUEST_TEMPLATE.md). Do not claim Steam playtime, achievements, Windows installation, or another platform's compatibility from unrelated tests. Include a focused regression for a behavioral fix when appropriate; avoid tests that merely repeat implementation strings.

## License

This `v2` branch uses the existing [Apache-2.0 license](LICENSE). Contributions to this branch are submitted under that license. This guide does not change the license of the legacy `main` branch, add a contributor license agreement, or require a new sign-off process.
