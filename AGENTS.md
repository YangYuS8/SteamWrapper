# AGENTS.md

This file defines development rules for AI agents working on SteamWrapper v2.

## Project direction

SteamWrapper v2 is not a simple per-game executable wrapper anymore.

The product goal is:

> Configure once in SteamWrapper Manager, then launch the game normally from Steam.

Daily gameplay must be invisible to the user:

- Users configure games in `SteamWrapperManager`.
- Steam calls `SteamWrapperRunner` through Launch Options.
- Runner starts the configured target executable or launcher.
- Runner waits for the game to exit so Steam can count play time.

## Architecture

Current v2 layout:

```text
crates/
  core/      # shared config, profile, Steam library and launch option logic
  runner/    # native headless runtime called by Steam

apps/
  manager/   # Tauri v2 + React + shadcn/ui configuration app
```

Keep this separation strict.

### `crates/core`

Allowed:

- Shared profile data structures.
- TOML config loading/saving.
- Steam Launch Options generation.
- Steam library/appmanifest parsing.
- Local Steam cover cache discovery.
- Platform-neutral business logic.

Not allowed:

- Tauri-specific APIs.
- React/frontend code.
- Windows-only process APIs.
- Linux-only process APIs.

### `crates/runner`

Allowed:

- Headless runtime entrypoint.
- CLI parsing such as `--appid <id> -- %command%`.
- Target process launch.
- Platform-specific process waiting.
- Runtime logging and error handling.

Rules:

- Runner must remain native and headless.
- Runner must not depend on Tauri, WebView, React, or frontend assets.
- Runner must start quickly because Steam launches it during normal gameplay.
- Runner must not show UI during normal successful launches.

### `apps/manager`

Allowed:

- Tauri v2 app shell.
- React + TypeScript frontend.
- Tailwind CSS + shadcn/ui components.
- Chinese-first user interface.
- Local Steam game library display.
- Local Steam cover cache display.
- Profile editing.
- Launch Options generation and future apply/restore workflow.

Rules:

- Manager is for configuration only.
- Do not put gameplay runtime logic in Manager.
- Keep UI text clear for non-technical Windows players.
- Prefer friendly Chinese copy over developer jargon.

## Technology choices

Use:

- Rust for `core` and `runner`.
- Tauri v2 for `manager`.
- React + TypeScript + Vite for the frontend.
- Tailwind CSS + shadcn/ui for UI.
- TOML for user profiles.
- pnpm for frontend package management.

Do not introduce without discussion:

- Electron.
- C#/.NET for v2 runtime code.
- Python runtime components.
- Online cover APIs.
- Background services or daemons.
- DLL injection or Steam client modification.

## Brand assets

The unified project icon is:

```text
assets/brand/steamwrapper.svg
```

Manager frontend copy for direct import is:

```text
apps/manager/src/assets/steamwrapper.svg
```

Rules:

- Treat this SVG as the canonical v2 project mark.
- It is an original Rust-inspired gear and Steam-like launch graph mark.
- It is not the official Steam logo and must not be described as such.
- Do not replace it with official Steam, Rust, or third-party trademarked logos.
- Use the root `assets/brand/steamwrapper.svg` in README, docs and release materials.
- Use the frontend copy inside `apps/manager/src/assets/` for Manager UI imports.

## Licensing

SteamWrapper v2 uses Apache-2.0.

When adding Rust crates or package metadata, use:

```toml
license = "Apache-2.0"
```

When adding npm package metadata, use:

```json
"license": "Apache-2.0"
```

Do not reintroduce MIT metadata in v2 files unless the project owner explicitly changes the license again.

## Windows distribution rules

Primary Windows distribution:

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

Secondary distribution:

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

Manager install path target:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

Stable user data path:

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Steam Launch Options should reference the stable Runner path, not a temporary portable extraction path:

```text
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

## Steam integration rules

Default workflow:

- Do not require SteamEdit.
- Do not copy the full wrapper into every game directory.
- Generate Launch Options using Runner.
- Preserve `%command%` after `--` for future compatibility.

Launch Options format:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Future one-click apply behavior must:

- Detect whether Steam is running.
- Avoid blindly writing Steam config while Steam may overwrite it.
- Backup config before editing.
- Preserve and restore previous Launch Options.
- Support multiple Steam users when possible.

## Local Steam library and cover rules

First version must be offline-friendly.

Allowed cover sources:

```text
<Steam install dir>\appcache\librarycache\
<Steam install dir>\userdata\<steamid>\config\grid\
```

Rules:

- Do not fetch online cover images by default.
- Do not require SteamGridDB or other third-party APIs for v2.0/v2.1.
- Missing cover image is not an error.
- Show a friendly placeholder if no local cover is found.

## UI rules

The Manager targets normal Windows players, not only developers.

UI language:

- Chinese-first for now.
- Avoid exposing raw technical details unless needed.
- Prefer words like “应用到 Steam”, “恢复原设置”, “测试启动”, “选择真正启动的程序”.

Visual direction:

- Use card-based game list.
- Show local Steam cover images when available.
- Use the SteamWrapper SVG project icon in the sidebar, hero area and future About page.
- Keep the primary flow obvious.
- Avoid terminal-like workflows for normal users.

## Safety boundaries

SteamWrapper must not:

- Inject DLLs.
- Patch Steam.
- Patch game binaries.
- Bypass DRM.
- Hide background services.
- Upload user data.
- Contact online services for cover images in the first version.

SteamWrapper may:

- Read local Steam library metadata.
- Read local Steam cover cache.
- Generate Steam Launch Options.
- Backup and restore local Steam configuration in future versions.
- Launch a user-selected local executable.

## Validation commands

Before considering a change ready, run or rely on Actions for:

```bash
pnpm install --no-frozen-lockfile
pnpm --filter steamwrapper-manager lint
pnpm --filter steamwrapper-manager build
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace
```

If a command fails, fix the root cause instead of weakening CI.

## Commit style

Prefer Conventional Commit prefixes:

- `feat:` for new functionality.
- `fix:` for bug fixes.
- `docs:` for documentation.
- `build:` for build/dependency changes.
- `ci:` for workflow changes.
- `refactor:` for structure changes without behavior changes.
- `chore:` for maintenance.

## Current priority

The current v2 priority order is:

1. Keep CI green.
2. Make Manager boot reliably.
3. Implement local Steam library scanning.
4. Implement local cover cache lookup.
5. Make Runner launch configured targets robustly.
6. Add Windows setup.exe and portable zip release workflow.
7. Add Steam Launch Options apply/restore flow.
