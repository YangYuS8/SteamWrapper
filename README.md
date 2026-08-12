# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper icon" width="128" height="128" />
</p>

[中文 README](README.zh-CN.md) | [Agent Guidelines](AGENTS.md)

SteamWrapper v2 is the Rust-native rewrite of SteamWrapper.

> Configure once in SteamWrapper Manager, then launch the game normally from Steam.

The Manager is visible only during configuration. For daily play, Steam calls the headless `SteamWrapperRunner` through Launch Options; the Runner loads the selected profile, launches the real executable or launcher, and waits for the game to exit.

## Goals

- No .NET Runtime or Electron requirement.
- No SteamEdit requirement in the default workflow.
- No full wrapper copied into every game directory.
- A Dioxus Desktop Manager for configuration and an independent native Runner for play.
- v2 LTS scope: Windows, Linux, SteamOS / Steam Deck desktop mode.
- Local Steam metadata and covers only in the first stage; no online cover service is required.

## Product shape

```text
SteamWrapperManager(.exe)  # Dioxus Desktop configuration app
SteamWrapperRunner(.exe)   # native headless runner called by Steam Launch Options
profiles.toml              # shared game profiles
logs/                      # runtime logs
backups/                   # future Steam config backups
cache/                     # local metadata/cache
```

Typical flow:

```text
Install SteamWrapper
→ open SteamWrapper Manager once
→ scan local Steam games
→ select a Steam game profile
→ select the real target exe / launcher
→ copy the generated Steam Launch Options
→ from then on, launch directly from Steam
```

Launch Options compatibility contract:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

The stable Runner path and `%command%` portion are deliberately preserved.

## Architecture

```text
apps/manager-dioxus  # Dioxus 0.7.10 Desktop + CSS UI
        ↓ direct typed Rust calls
crates/manager-core  # framework-neutral Manager services
        ↓
crates/core          # TOML, Steam metadata/covers, Launch Options

crates/runner        # independent native headless runtime
```

The Manager does not emulate Tauri IPC: it directly consumes the Rust service layer. `core` stays GUI-neutral; `runner` stays independent from WebView/UI lifecycle.

## Development

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

See `docs/architecture.md`, `docs/tech-stack.md`, `docs/distribution.md`, `docs/testing.md`, and `docs/roadmap.md` for constraints and platform coverage.

## Brand asset

The canonical project mark is `assets/brand/steamwrapper.svg`. It is an original Rust-inspired gear and launch-graph mark for SteamWrapper, not the official Steam logo.

## License

Apache-2.0

## Status

The `v2` branch remains early-stage. The original C# implementation on `main` is still the legacy stable version.
