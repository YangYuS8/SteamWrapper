# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper icon" width="128" height="128" />
</p>

English | [简体中文](README.zh-CN.md)

**Configure a game once in Manager, then launch it normally from Steam.** SteamWrapper helps Windows players launch translated games or custom launchers while keeping Steam status and playtime aligned with the actual game lifecycle.

The [Windows v2 design](docs/windows-v2-design.md) uses a **WinUI 3/C# Manager, C# configuration services, and an independent Rust Runner**, connected by existing TOML/CLI contracts. The native configuration preview is implemented in `apps/manager-winui`. Dioxus and its release workflows remain the migration baseline; the default delivery chain has not switched.

For daily play, Steam Launch Options calls the headless Runner. It reads a profile from the stable data directory, starts the chosen exe/launcher, and waits according to the configured mode. Manager can remain closed. Process tests alone do not establish every game's Steam status or playtime compatibility.

Keep an official installation for Steam updates/verification and a complete translated copy outside the Steam library. WinUI displays the Steam installation separately from the actual runtime folder. See [directory separation, saves, and achievements](docs/translated-games.md). SteamWrapper does not supply missing achievement logic.

## Product goals

- Players should not need manual runtime preparation. A self-contained C# Manager can bundle .NET; Runner remains native Rust.
- No default SteamEdit requirement, Steam client modification, or complete wrapper copied into each game directory.
- Manager configures; normal play uses the independent, headless Runner.
- Windows first. Existing Linux code/contracts remain; Linux / SteamOS expansion and release commitments are deferred.
- First WinUI covers use local Steam metadata/cache and friendly placeholders. The retained Dioxus implementation still has a public Steam CDN fallback.
- Configuration, installation, updates, and recovery should be understandable to ordinary players.
- English is the primary project language, with complete Simplified Chinese UI resources and documentation.

## Product layout

```text
SteamWrapper.Manager.exe       # native WinUI Windows configuration preview
SteamWrapperManager(.exe)       # retained Dioxus Desktop configuration app
SteamWrapperRunner(.exe)        # headless Runner called by Steam Launch Options
profiles.toml                   # shared game profiles
ui-settings.json                # Manager display-language preference
logs/                           # runtime logs
backups/                        # configuration backups; future Steam apply backups
cache/                          # local metadata/cache
```

## Windows player flow

```text
Install SteamWrapper
→ open SteamWrapper Manager
→ scan local Steam games
→ select the game whose launch behavior needs changing
→ select the real target exe / launcher and runtime folder
→ save without losing advanced settings or working directory
→ copy the generated Launch Options
→ preserve the previous options, then paste the new value in Steam Properties
→ close Manager and launch directly from Steam
```

The generated Launch Options retain this compatibility format:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

Keep `%command%` after `--`. Current Runner receives/logs the original Steam command but executes the profile's target/args; it does not automatically execute or forward the original command. Options always reference stable Runner, not a package, temporary extraction directory, or Manager.

The Windows plan completes configuration fidelity, the launch flow, and installation/update/uninstall before cross-platform expansion. The first preview uses manual copying; backed-up one-click apply/restore follows next. Copying is not applying to Steam. See the [roadmap](docs/roadmap.md) and [technical assessment](docs/winui3-assessment.md).

## Current implementation

WinUI's `SteamWrapper.Manager` (native UI, pickers, clipboard) calls `SteamWrapper.Application` (syntax-preserving TOML edits, local Steam discovery, stable Runner installation). Cross-language contracts verify actual Rust consumption without FFI or a background service. See [Windows development](docs/windows-development.md).

Retained Dioxus chain:

```text
apps/manager-dioxus (Dioxus Desktop + CSS)
                ↓ direct typed Rust calls
crates/manager-core (paths, profiles, scanning, logs, Runner installation/repair)
                ↓
crates/core (GUI-neutral TOML, Steam, covers, Launch Options)

crates/runner (independent, headless, called by Steam)
```

- `crates/core` has no Dioxus, desktop framework, or platform process API dependency.
- `crates/runner` has no GUI, WebView, or frontend-resource dependency.
- `crates/manager-core` orchestrates Manager services without Dioxus dependencies, preserving UI replacement boundaries.
- `apps/manager-dioxus` uses Dioxus 0.7.10, RSX, and local CSS with direct typed service calls, not emulated Tauri IPC.

## Language

Manager offers English and Simplified Chinese. WinUI's language selector is in the sidebar. The Managers share `ui-settings.json` beside `profiles.toml`, using `language: "en-US"` or `"zh-CN"`; missing/unknown values fall back to English. A successful change updates application-owned text and persists for the next launch. User-entered names, paths, launch commands, and log contents stay unchanged.

A language change does not reinterpret TOML fields, AppIDs, arguments, or wait modes. An invalid existing settings file is not silently overwritten. English documents use `.md`; their complete Simplified Chinese counterparts use `.zh-CN.md` and link back to English.

## Stable Runner installation

When saving a profile, WinUI checks bundled Runner and installs it atomically to the stable directory. Hash failures, busy files, or unknown relative versions preserve the existing file while still allowing profile saves. Newer compatible Runner versions are not downgraded. Dioxus retains its first-startup/Settings installation behavior.

Windows:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # intended Manager installation directory
%LOCALAPPDATA%\SteamWrapper\bin\           # stable Runner
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # user configuration
%LOCALAPPDATA%\SteamWrapper\ui-settings.json # display language
%LOCALAPPDATA%\SteamWrapper\logs\          # logs
%LOCALAPPDATA%\SteamWrapper\backups\       # backups
```

Linux / SteamOS:

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  ui-settings.json
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

When `XDG_DATA_HOME` is unset, use `~/.local/share/SteamWrapper/`.

## Current Dioxus cover policy

Prefer local Steam caches:

```text
<Steam installation>/appcache/librarycache/
<Steam installation>/userdata/<steamid>/config/grid/
```

If a cover is missing, Manager requests public Steam CDN `library_600x900.jpg` using only an AppID already present in a local manifest. It does not query player profiles, upload a library, or require an API key. Normal HTTP caching can reuse responses. Offline operation, rate limits, or absent resources show a friendly cover-unavailable placeholder without blocking scanning/configuration.

## WinUI preview development

After [mise environment setup](docs/windows-development.md):

```powershell
mise run winui:test       # C# service regressions
mise run winui:contracts  # C# edit → Rust read and real Runner process verification
mise run winui:publish    # self-contained target/winui/publish directory
mise run winui:sandbox    # native preview with disposable Steam/user-data fixtures
```

The preview supports local scanning/search, manual additions, native executable selection, syntax-preserving saves, advanced arguments, and Launch Options copying. Preserve old Steam options before pasting; paste them back to undo. Keep the entire published directory together, not just the EXE.

Real Steam acceptance has passed locally for one Unity galgame and five separate translated 9-nine packages, with the exact titles/scenarios, Chinese openings, status/playtime, and limitations in [live validation](docs/real-steam-validation.md). These are not all-game or achievement guarantees. Clean Windows 11 VM acceptance and the WinUI installer remain unfinished.

## Dioxus Manager development

On Windows, follow [mise development setup](docs/windows-development.md): `mise install`, `mise run windows:setup`, and `mise run windows:doctor`. `windows:verify` checks the Dioxus baseline; `windows:winui-smoke` remains an isolated template-environment diagnostic.

Prerequisites include stable Rust, Dioxus CLI `0.7.10`, and WebKitGTK desktop dependencies on Linux. pnpm is used for Native E2E and development asset tooling, not a product UI runtime. The root `justfile` provides local entry points:

```bash
just dev          # hot reload with real local Steam/user data
just dev-sandbox  # disposable Steam/user-data sandbox
just verify       # Rust, Dioxus, and Native E2E gates
just bundle-linux # stage Runner and produce release-artifacts/*.AppImage
```

Use `just --list` for all recipes. Choose local checks by [change scope](docs/testing.md#按改动选择验证); full CI/release gates remain. Lower-level commands:

```bash
pnpm install --frozen-lockfile
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
```

Native E2E creates isolated Steam Library, XDG/LocalAppData, and profile fixtures; it does not read/write real Steam configuration:

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Dioxus Native E2E uses the `@wdio/dioxus-service` embedded provider. Its Rust bridge is built only with the `e2e` Cargo feature; formal bundles contain no test WebDriver.

## Distribution

Candidate artifacts in the retained Dioxus distribution plan, not a claim that all are delivered:

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
SteamWrapper-v2.x.x-win-x64-portable.zip
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

Existing Dioxus Windows configuration uses a CurrentUser NSIS installer. WinUI deployment needs separate acceptance. Later Linux / SteamOS delivery is deferred; GitHub/CNB dual-channel delivery remains a target requiring acceptance. See [distribution](docs/distribution.md).

## Safety boundaries

SteamWrapper v2 does not perform DLL injection, Steam/game binary patching, DRM bypass, hidden background services, user-data uploads, third-party online cover-service integration, or player-library uploads. System security changes and third-party file recovery are not application features.

Use disposable fixtures for automated tests. Real-library tests require the owner's authorization, preserved Launch Options, and file/saved-progress safeguards. Do not run Steam verification over a modified translation without understanding that it can replace files. See [security reporting](SECURITY.md) for suspected vulnerabilities.

## Brand assets

The canonical original project mark is `assets/brand/steamwrapper.svg`, with generated `.png`/`.ico` files and matching Dioxus copies. Its Rust-inspired gear and Steam-inspired launch linkage identify SteamWrapper; the project is not affiliated with or endorsed by Valve or the Rust project.

```powershell
mise run brand:generate
mise run brand:check
```

Generation uses development-only pnpm / `@resvg/resvg-js`, not an application runtime. See [contributing](CONTRIBUTING.md) before changing the source mark or packaged copies.

## Documentation and community

- [Documentation index](docs/README.md): architecture, setup, testing, migration, distribution, and dated evidence.
- [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), [security policy](SECURITY.md), and [support](SUPPORT.md).
- [Issues](https://github.com/YangYuS8/SteamWrapper/issues) accept English and Simplified Chinese reports. Matching template files are included on `v2`; the live template chooser follows the default branch.
- [Agent guide](AGENTS.md) contains repository automation instructions.

## License and status

This `v2` branch retains [Apache-2.0](LICENSE). The legacy C# implementation on `main` has its own branch contents/license; this work does not change them.

`v2` remains in development. GitHub's default branch is currently `main`, so its displayed community profile and templates may differ from this branch. Contributions for this implementation should target `v2`; no default-branch or remote settings are changed by these files.
