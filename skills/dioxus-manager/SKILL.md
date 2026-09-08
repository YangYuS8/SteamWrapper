---
name: dioxus-manager
description: Edit SteamWrapper's Dioxus UI, Native E2E, or bundles. Not for WinUI research or Runner lifecycle work.
license: Apache-2.0
metadata:
  version: "0.2.0"
  author: YangYuS8, Hermes Agent
  platforms: [linux, macos, windows]
  hermes:
    tags: [Dioxus, Rust, SteamWrapper, desktop, E2E]
    related_skills: []
---

# SteamWrapper Dioxus Manager

Maintain the checked-in Manager at `apps/manager-dioxus`. The [Windows design](../../docs/src/content/docs/project/design/windows-v2.md) selects a WinUI 3/C# Manager and independent Rust Runner; this skill describes the existing implementation and does not govern that migration. The repository [AGENTS.md](../../AGENTS.md) holds shared compatibility, safety, and verification rules.

## UI and service work

Read the affected component and its service call path. Dioxus 0.7.10 RSX uses `src/services.rs` to call `crates/manager-core`; domain rules remain in `crates/core`, and game execution remains in Runner. Check official pinned-version documentation/source when an API is uncertain.

Use [architecture](../../docs/src/content/docs/development/architecture.md) for boundary changes. Use English by default with complete Simplified Chinese resources and a persisted language selector. Localize visible text and accessibility labels while preserving user-entered values and protocol identifiers. Keep native file selection, friendly missing-cover states, and the canonical brand asset. Covers use the existing local-first/AppID CDN fallback; the network boundary is defined in AGENTS.md.

## Validation

Choose checks from [testing](../../docs/src/content/docs/development/testing.md). UI/service acceptance uses the real Desktop binary and isolated Native E2E fixtures. Source-text `ui_contract` checks cannot prove rendering or native interaction. Use observable behavior tests for new UI behavior rather than freezing incidental CSS/RSX strings.

Native E2E uses `@wdio/dioxus-service` embedded mode. Only the Cargo `e2e` feature may include `wdio-dioxus-embedded-driver`; the normal release graph must exclude it. The fixture setup and four required environment variables are documented in the testing guide. Browser Mode does not exercise the direct desktop Rust-service path.

For automated previews, use disposable data. `just dev` and `just run` access real local data; `just dev-sandbox` is the fixture alternative in a Bash-capable environment.

## Dioxus packaging

Read [distribution](../../docs/src/content/docs/development/distribution.md) when staging, installing, or bundling Runner. Dioxus `asset_dir` does not bundle executables: `[bundle].resources` lists the two Runner file paths, staging supplies the non-empty current-platform file and the other platform's placeholder. Generated resources stay untracked.

Verify resource lookup against the actual NSIS/AppImage layout; debug builds can find source resources and therefore do not prove packaging. Windows needs a non-empty `SteamWrapperRunner.exe`; Linux needs a non-empty `SteamWrapperManager/steamwrapper-runner` inside the extracted AppImage. Report only the platform and artifact actually verified.
