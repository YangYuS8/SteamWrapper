# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper icon" width="128" height="128" />
</p>

[中文 README](README.zh-CN.md) | [Agent Guidelines](AGENTS.md)

SteamWrapper helps Windows players launch translated games or custom launchers through Steam while keeping play status aligned with the game. The [new v2 design](docs/windows-v2-design.md) uses a **WinUI 3/C# Manager with C# configuration services and an independent Rust Runner**, using the existing TOML/CLI contracts. The first native configuration preview is implemented in `apps/manager-winui`. Dioxus and its release workflows remain available until the Windows delivery gates pass.

> Configure once in SteamWrapper Manager, then launch the game normally from Steam.

The Manager is visible only during configuration. For daily play, Steam calls the headless `SteamWrapperRunner` through Launch Options; the Runner loads the selected profile, launches the real executable or launcher, and waits for the game to exit.

The WinUI preview distinguishes Steam's installation location from the actual runtime folder. Keep a translated copy outside the Steam library while preserving the official installation for updates and verification; see [directory separation, saves and achievement compatibility](docs/translated-games.md). SteamWrapper does not supply missing achievement logic.

## Goals

- Aim for a Windows install that requires no manual runtime setup; a C# Manager may bundle .NET. Runner remains a native Rust executable.
- No SteamEdit requirement in the default workflow.
- No full wrapper copied into every game directory.
- A native Windows configuration experience and an independent headless Runner for play; Dioxus remains the current implementation during migration.
- Windows first. Existing Linux support is retained; Linux / SteamOS expansion and release commitments are deferred.
- The WinUI preview uses local Steam metadata/covers and friendly placeholders. The current Dioxus implementation still has its public Steam CDN fallback.

## Product shape

```text
SteamWrapper.Manager.exe  # native WinUI Windows configuration preview
SteamWrapperManager(.exe)  # retained Dioxus Desktop configuration app
SteamWrapperRunner(.exe)   # native headless runner called by Steam Launch Options
profiles.toml              # shared game profiles
logs/                      # runtime logs
backups/                   # future Steam config backups
cache/                     # local metadata/cache
```

Target Windows flow:

```text
Install SteamWrapper
→ open SteamWrapper Manager once
→ scan local Steam games
→ select a Steam game profile
→ select the real target exe / launcher
→ save the profile without losing existing advanced settings
→ copy the generated Steam Launch Options
→ preserve the previous options, then paste the new value in Steam
→ from then on, launch directly from Steam
```

Launch Options compatibility contract:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

The stable Runner path and `%command%` portion are deliberately preserved. The current Runner receives and logs the original Steam command, but launches the profile's target/args; it does not automatically execute or forward that command. Steam status and playtime require separate validation in the client.

The Windows plan prioritizes safe configuration, a complete launch flow, and installation/update/uninstall before cross-platform expansion. Manual copying is sufficient for the first preview; backed-up Steam apply/restore follows next. See the [roadmap](docs/roadmap.md) and [technical assessment](docs/winui3-assessment.md).

## Current implementation

The Windows preview separates `SteamWrapper.Manager` (native UI, pickers, clipboard) from `SteamWrapper.Application` (safe TOML edits, local Steam discovery, stable Runner installation). Cross-language tests verify compatibility with the actual Rust Runner. The retained Dioxus chain is shown below.

```text
apps/manager-dioxus  # Dioxus 0.7.10 Desktop + CSS UI
        ↓ direct typed Rust calls
crates/manager-core  # framework-neutral Manager services
        ↓
crates/core          # TOML, Steam metadata/covers, Launch Options

crates/runner        # independent native headless runtime
```

The Manager does not emulate Tauri IPC: it directly consumes the Rust service layer. `core` stays GUI-neutral; `runner` stays independent from WebView/UI lifecycle.

## WinUI preview development

After the [mise environment setup](docs/windows-development.md):

```powershell
mise run winui:test
mise run winui:contracts
mise run winui:publish    # self-contained directory: target/winui/publish
mise run winui:sandbox    # native preview with disposable Steam/user-data fixtures
```

The preview supports local game discovery/search, manual AppID entry, native target selection, safe configuration edits, advanced arguments and copying Launch Options. Preserve the previous Steam options before pasting; restore that saved value to undo. Real Steam timing, a clean Windows VM and the installer still require validation. Keep the entire published directory together.

## Current Dioxus development

On Windows, use the [mise development setup](docs/windows-development.md): `mise install`, then `mise run windows:setup` and `mise run windows:doctor`. The project also provides `windows:verify` for the current application and `windows:winui-smoke` for an isolated WinUI build.

`just` is the local entrypoint:

```bash
just dev          # start the Desktop Manager with hot reload and real local data
just dev-sandbox  # start it with disposable Steam and user-data directories
just verify       # run Rust, Dioxus, and Native E2E gates
just bundle-linux # stage the Runner and create release-artifacts/*.AppImage
```

Run `just --list` for every recipe. The equivalent lower-level validation commands remain available:

```bash
pnpm install --frozen-lockfile
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
```

Native E2E uses an isolated local Steam and user-data fixture. It does not touch the real Steam library or user profile:

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Choose local checks by the [change being made](docs/testing.md#按改动选择验证); full CI/release gates remain in place. See [architecture](docs/architecture.md), [technology choices](docs/tech-stack.md), [distribution](docs/distribution.md), and [roadmap](docs/roadmap.md) for implementation and deferred scope.

## Brand asset

The canonical project mark is `assets/brand/steamwrapper.svg`. It is an original Rust-inspired gear and launch-graph mark for SteamWrapper, not the official Steam logo.

## License

Apache-2.0

## Status

The `v2` branch remains early-stage. The original C# implementation on `main` is still the legacy stable version.
