# SteamWrapper v2 — Agent Guide

## First read

Before changing anything, read the relevant source and tests, then check the live worktree:

```bash
git status --short --branch
cargo test --workspace
```

Current implementation facts come from Rust source, manifests, scripts and CI. Product intent comes from the documents under `docs/`. Do not treat old commits, issue descriptions, or a roadmap checkbox as proof that behavior exists.

## Product boundary

> Configure a game once in SteamWrapper Manager, then launch it normally from Steam.

- `SteamWrapperManager` is configuration UI only.
- Steam invokes the headless `SteamWrapperRunner` through Launch Options.
- Runner starts the selected target and waits according to the saved profile.
- Normal successful game launch must not show Manager UI.

The compatibility contracts are non-negotiable:

```text
profiles.toml
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Do not alter TOML serialization, stable user-data locations, Runner CLI meaning, or the preserved `%command%` position merely to simplify UI work.

## Current layout

```text
crates/
  core/          # framework-neutral profile, TOML, Steam, cover, Launch Options logic
  manager-core/  # framework-neutral Manager service orchestration
  runner/        # native headless Steam runtime

apps/
  manager-dioxus/      # Dioxus 0.7.10 Desktop Manager
    e2e/               # WDIO Dioxus Native E2E, test-only Node tooling
```

The retired Tauri / React Manager is deliberately absent. Do not reintroduce Tauri, React, Vite, Tailwind, shadcn, Electron, or a fake IPC layer without explicit user approval.

## Layer rules

### `crates/core`

Allowed:

- Profile data structures and TOML read/write.
- Steam Launch Options generation.
- Steam library / appmanifest parsing and local cover cache discovery.
- Platform-neutral business rules.

Forbidden:

- Dioxus / desktop framework dependencies.
- UI models or UI event logic.
- Windows-only or Linux-only process APIs.

### `crates/manager-core`

Allowed:

- Stable Manager paths and directories.
- Profile list/save, game scanning, logs, Launch Options.
- Bundled Runner inspection, atomic install, and repair.
- Typed Rust service APIs consumed directly by the Manager.

Forbidden:

- Dioxus, WebView, Node, WDIO, or frontend dependencies.
- Runner process launching / waiting semantics.
- A second Profile or Steam DTO hierarchy.

### `crates/runner`

Allowed:

- Headless CLI parsing such as `--appid <id> -- %command%`.
- Target process launch, platform waiting, runtime logging and errors.

Rules:

- Remain native, headless and independent of GUI / WebView assets.
- Start quickly; do not add background services.
- Do not claim Job Object, process-group, `process_name`, Proton, or windowless guarantees unless source and platform tests prove them.
- Fix lifecycle semantics in Runner / platform modules with real process tests, never in Manager.

### `apps/manager-dioxus`

Allowed:

- Dioxus 0.7.10 Desktop app shell, RSX, local CSS, and Dioxus-supported file selection.
- Chinese-first player UI: game library, local covers, profile editing, Launch Options, logs, paths, Runner install / repair.

Rules:

- Call `steamwrapper-manager-core` through `src/services.rs`; no Tauri-command-shaped wrappers or fake IPC.
- Keep gameplay/runtime process behavior out of Manager.
- Use card-based, non-terminal-like UI; missing cover is a friendly placeholder, not an error.
- Keep `apps/manager-dioxus/assets/steamwrapper.svg` byte-identical to `assets/brand/steamwrapper.svg`.

## Technical choices

- Rust: `core`, `manager-core`, `runner`, Dioxus Manager.
- Dioxus Desktop: pinned to `0.7.10`; research official docs/source before changing versions or APIs.
- CSS: native local assets; do not add a Node frontend runtime for UI styling.
- TOML: persisted profile format.
- pnpm: only for `apps/manager-dioxus/e2e` Native E2E tooling.

Do not add Electron, Python runtime components, online cover APIs, daemons, DLL injection, Steam client modification, DRM bypasses, or third-party logos without explicit discussion.

## Runner resources and distribution

Canonical brand asset:

```text
assets/brand/steamwrapper.svg
```

Bundle the platform Runner using the Dioxus resource entries in `apps/manager-dioxus/Dioxus.toml`. Stage it before bundle commands:

```bash
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
```

- Linux resource: `steamwrapper-runner`.
- Windows resource: `SteamWrapperRunner.exe`.
- Generated `resources/runner/` content is ignored; never commit staged binaries.
- Manager copies the read-only bundle resource to a stable user-data `bin` path. Launch Options must never reference an AppImage, NSIS extraction, or portable temporary path.

Windows stable data:

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Linux / SteamOS stable data:

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

Use `~/.local/share/SteamWrapper/` when `XDG_DATA_HOME` is unset.

## Safety boundaries

SteamWrapper may read local Steam metadata/covers, generate Launch Options, install its own stable Runner, and later apply/restore local Steam configuration with backup.

SteamWrapper must not inject DLLs, patch Steam or game binaries, bypass DRM, hide a service, upload user data, or contact online cover services in the first version.

Future one-click Steam integration must detect Steam running, support multi-user data where possible, back up before mutation, preserve previous Launch Options, and restore them safely.

## Tests and validation

For behavior changes, add a focused test first and observe it fail for the intended missing behavior. Then make the minimal implementation pass. Do not use a passing test added after the fact as evidence.

Run the narrow gate first, then the full gate:

```bash
pnpm install --frozen-lockfile
pnpm --filter steamwrapper-manager-dioxus-e2e exec tsc --noEmit

cargo test -p steamwrapper-manager-core
cargo test -p steamwrapper-manager-dioxus --test ui_contract
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native

cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace
cd apps/manager-dioxus && dx check && dx build --release
```

For Linux AppImage:

```bash
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
cd apps/manager-dioxus
dx bundle --release --package-types appimage --out-dir ../../release-artifacts
```

Extract the actual AppImage and prove it contains non-empty `SteamWrapperManager/steamwrapper-runner`. Windows NSIS must be built and inspected on Windows. Linux success is not Windows or Steam Deck evidence.

Native E2E requirements:

- Uses `@wdio/dioxus-service` embedded provider.
- Cargo `e2e` feature may include `wdio-dioxus-embedded-driver`; normal release graph must not.
- Always use isolated temporary `STEAM_DIR`, `STEAMWRAPPER_E2E_ROOT`, `XDG_DATA_HOME`, and `LOCALAPPDATA` values.
- Never drive a real Steam library or user data directory.
- Never commit test artifacts, browser data, logs, or staged Runner binaries.

## Documentation and CI

When behavior, architecture, packaging, test commands or delivery boundaries change, update the relevant current docs in the same task:

- `README.md` / `README.zh-CN.md`
- `docs/architecture.md`
- `docs/tech-stack.md`
- `docs/distribution.md`
- `docs/testing.md`
- `docs/roadmap.md`
- `skills/dioxus-manager/SKILL.md`

Keep these documents honest about platform evidence. A passing Linux build does not justify checking off Windows, SteamOS, Proton, one-click Steam integration, portable zip, tar.gz, or release-channel delivery.

CI / release workflows must stage the current-platform Runner, run Dioxus gates, and inspect actual bundle contents. Do not weaken gates or fabricate release / test results.

## Git discipline

- Work on `v2`, never modify `main`.
- Re-check `git status` before edits and before delivery.
- Keep changes within the requested scope; no drive-by refactors.
- Do not commit, push, or rewrite history unless asked.
- Prefer Conventional Commit prefixes: `feat:`, `fix:`, `docs:`, `build:`, `ci:`, `refactor:`, `chore:`.
- Never print, commit, or copy credentials, tokens, `.env` contents, or generated user data.

## Current priority

1. Keep CI green.
2. Make Manager boot reliably.
3. Validate local Steam library and cover scanning.
4. Make Runner launch / wait semantics robust with real process evidence.
5. Bring Linux / SteamOS support into v2 LTS with honest platform verification.
6. Add safe Steam Launch Options apply / restore.
7. Add player-friendly installation, update, uninstall, portable, and GitHub/CNB delivery paths.
