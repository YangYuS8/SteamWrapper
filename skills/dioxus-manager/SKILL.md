---
name: dioxus-manager
description: Build and verify SteamWrapper's Dioxus Manager safely.
version: 0.1.0
author: YangYuS8, Hermes Agent
license: Apache-2.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Dioxus, Rust, SteamWrapper, desktop, E2E]
    related_skills: []
---

# SteamWrapper Dioxus Manager

Maintain the v2 Manager at `apps/manager-dioxus` without weakening the data, Runner, or distribution contracts. The Manager is a configuration UI only; daily game launch remains the independent `steamwrapper-runner` binary.

## When to Use

- Editing the Dioxus Manager UI, Dioxus bundle metadata, native E2E, or Manager Runner staging.
- Changing Manager-facing profile, Steam scan, local cover, log, path, or Runner repair behavior.
- Updating CI/release steps that build `SteamWrapperManager`.

Do not use this skill for Runner process lifecycle work; use the Runner's Rust tests and platform modules directly.

## Architecture Rules

```text
apps/manager-dioxus → crates/manager-core → crates/core
crates/runner        → crates/core
```

- `crates/core` remains GUI- and platform-process-neutral.
- `crates/manager-core` is a typed Rust service layer, not a fake IPC API. It cannot depend on Dioxus, Tauri, React, Node, or WebView crates.
- Dioxus RSX calls `manager-core` directly through `apps/manager-dioxus/src/services.rs`.
- `crates/runner` remains headless and independent of the Manager lifecycle.
- Preserve `profiles.toml`, `--appid <id> -- %command%`, and stable Runner paths exactly.

## Development Procedure

1. Read `AGENTS.md`, the affected source, neighbouring tests, `docs/architecture.md`, and `docs/testing.md` before editing. Completion: the boundary and existing behavior are known from source, not inferred.
2. Prefer the root `justfile` for repeatable local work: `just dev` uses real local Steam/user data; `just dev-sandbox` uses disposable fixture directories; `just verify` runs Rust, Dioxus, and Native E2E gates; `just bundle-linux` stages the Runner before building an AppImage.
3. For behavior changes, add one focused Rust or Native E2E test first and run it to confirm a meaningful failure. Completion: RED is caused by the missing behavior, not test syntax.
4. Keep UI behavior in `src/app.rs`; put framework-neutral profile/Runner/path logic in `crates/manager-core`. Completion: no new Dioxus dependency in either `core` or `manager-core`.
5. Use Dioxus 0.7.10 APIs documented in the pinned project metadata or official source. Completion: avoid speculative API substitutions.
6. Stage the current-platform Runner before any bundle command:

   ```bash
   STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
   ```

   The staging directory is generated and ignored. Linux stages `steamwrapper-runner`; Windows stages `SteamWrapperRunner.exe`.
7. Keep `Dioxus.toml` `[bundle].resources` pointed at `resources/runner`. Completion: a real platform bundle contains a non-empty Runner resource.

## Validation

Run the narrow validation first, then all required commands:

```bash
cargo test -p steamwrapper-manager-core
cargo test -p steamwrapper-manager-dioxus --test ui_contract
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e exec tsc --noEmit
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native

cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace
cd apps/manager-dioxus && dx check && dx build --release
```

For Linux bundles:

```bash
cd apps/manager-dioxus
dx bundle --release --package-types appimage --out-dir ../../release-artifacts
```

Extract the AppImage and prove a non-empty `SteamWrapperManager/steamwrapper-runner` exists. Windows NSIS must be built and inspected on Windows; do not claim Linux evidence proves that package.

## Native E2E Rules

- Native E2E lives in `apps/manager-dioxus/e2e` and uses `@wdio/dioxus-service` embedded mode.
- The Rust `e2e` feature alone may include `wdio-dioxus-embedded-driver`; a normal dependency graph must not.
- The E2E runner must use temporary `STEAM_DIR`, `STEAMWRAPPER_E2E_ROOT`, `XDG_DATA_HOME`, and `LOCALAPPDATA` fixture directories. Never point an automated test at a real Steam library or user data directory.
- Artifacts and staged Runner resources are ignored; never commit binaries, fixture profiles, browser data, or logs.

## Pitfalls

- `asset_dir` does not distribute Runner resources. Use `[bundle].resources`.
- A local Linux debug binary resolves source resources, but an AppImage/NSIS package must resolve its bundled resource layout. Verify the actual package.
- The release binary must not use the `e2e` feature. Check with `cargo tree -p steamwrapper-manager-dioxus -e normal`.
- Dioxus Browser Mode is not appropriate for the direct Rust-service design; Native E2E is the authoritative UI/service acceptance test.
- Do not alter `%command%`, user data locations, or profile serialization merely to make UI state simpler.

## Delivery

Report only verified results: commands and outcomes, actual package path/content when produced, and platform coverage that remains pending. Do not call Windows/SteamOS packaging complete without evidence from those platforms.
