---
title: "SteamWrapper v2 technology stack"
description: "Current frameworks, development tools, and the Windows-first technology direction."
---

<a id="steamwrapper-v2-technology-stack"></a>

<a id="steamwrapper-v2-技术栈"></a>



<a id="目标方案"></a>

## Target design

Use a **C#/XAML WinUI 3 Manager, C# application services, and an independent Rust Runner**, with Windows first. See the [product and architecture redesign](/SteamWrapper/project/design/windows-v2/) and [WinUI assessment](/SteamWrapper/project/decisions/winui3/). The WinUI configuration preview is implemented and can be built as self-contained output. Dioxus 0.7.10 and its release chain remain because the complete Windows replacement gate has not passed.

| Area | Target choice | Rationale and constraints |
| --- | --- | --- |
| Manager UI | WinUI 3, C#, XAML | Native Windows windows, input, file selection, and accessibility; English default with complete Simplified Chinese localization |
| Manager services | Small, independently testable C# application services | Configuration, Steam discovery, Runner installation, and logs; no Rust FFI or background helper |
| Daily runtime | Independent Rust Runner | Preserve CLI and process-control boundaries; Manager does not participate in ordinary game launches |
| Persistent configuration | Existing profiles.toml v2 | C# implements the same protocol; reading/editing/writing, unknown-data protection, and actual Rust consumption must be verified |
| Covers | Local cache only in the first WinUI version | Use placeholders when absent; configuration/launch does not depend on network access |
| Delivery | Unpackaged self-contained directory plus per-user installer | Bundle .NET/Windows App SDK; players do not prepare runtimes; install Runner at its stable user path |
| Platform | Validate supported Windows 11 x64 first | Assess Windows 10, ARM64, and new Linux/SteamOS features separately; no advance support promise |

Existing Rust management services do not require the new UI to introduce an ABI. C# TOML uses pinned Tomlyn 2.10.1 to read syntax trees and edit field spans while preserving other source text. It generates only a Rust-readable TOML 1.0 string subset, without TOML 1.1 whole-model serialization. Fields, defaults, legacy alias keys, paths, and arguments are constrained by the passing cross-language/real Runner contracts. [Tomlyn package](https://www.nuget.org/packages/Tomlyn/2.10.1), [low-level syntax API](https://github.com/xoofx/Tomlyn/blob/2.10.1/site/docs/low-level.md)

Do not rewrite Runner merely to use one language. C# NativeAOT remains an alternative; any future evaluation should first establish complete CLI/TOML and Windows process compatibility, then compare actual package size, performance, and maintenance cost. [Official NativeAOT documentation](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

<a id="当前仓库布局"></a>

## Current repository layout

```text
crates/core                 # Rust TOML, Steam, covers, Launch Options
crates/manager-core         # Manager services used by the existing Dioxus app
crates/runner               # native headless runtime called by Steam
apps/manager-dioxus         # Dioxus 0.7.10 Desktop Manager
apps/manager-dioxus/e2e     # WDIO Native E2E, test tooling only
apps/manager-winui         # WinUI UI, C# Application, and MSTest tests
tests/contracts           # shared C# / Rust contracts and test driver
tests/fixtures            # controlled processes consumed by real Runner, tests only
```

Retain existing code and CI during migration. Switch the default Manager after WinUI meets configuration, runtime, and delivery gates, then remove the old management layers according to actual dependencies.

<a id="rust-核心与服务"></a>

### Rust core and services

`steamwrapper-core` defines the existing Profile/TOML, Steam scanning, cover URLs, and Launch Options. It depends on neither UI nor platform process APIs. Runner continues to use core's configuration and path semantics.

`steamwrapper-manager-core` combines stable paths, saving/listing, Steam scanning, logs, and Runner installation/repair into the Rust API called directly by Dioxus. It introduces neither a second Rust Profile type nor an IPC server. Its all-Rust service boundary does not constrain the new C# implementation.

The current profile save reconstructs advanced fields and core writes configuration directly. These behaviors must not become requirements for the new Manager. Compatibility preserves the meaning of player configuration, not defects that overwrite data.

### Runner

`steamwrapper-runner` uses `clap`, `anyhow`, `tracing`, and `steamwrapper-core`. It independently launches the profile's target/args and waits according to the selected mode. It has no GUI, WebView, or .NET dependency and does not run as a persistent background service.

New Windows profiles default to a Job Object; new Linux profiles default to a POSIX process group. Omitted legacy wait_mode means root. `%command%` is currently received and logged, not automatically executed/forwarded. Proton wrapping is unfinished. Runner lifecycle tests and real Steam status/playtime acceptance are different evidence.

<a id="当前-dioxus-manager"></a>

### Current Dioxus Manager

- Dioxus `0.7.10` with the desktop feature, RSX, and local CSS; verify official documentation before version/API changes.
- UI calls manager-core directly through `src/services.rs`, without artificial Tauri IPC.
- Current covers are local-first with an AppID Steam CDN fallback; the new WinUI local-cover goal does not mean the existing network code changed.
- `Dioxus.toml` controls icons, metadata, and Runner resources. Stage the current platform's Runner before building.
- `@wdio/dioxus-service` 1.0.0 embedded provider and `wdio-dioxus-embedded-driver` 1.0.0 are used only with the e2e feature; releases contain no test bridge.
- pnpm is for Native E2E, development asset tooling, and static documentation development/builds, not a UI product runtime. `mise run brand:generate` / `brand:check` generate and verify the canonical SVG/PNG/ICO and Dioxus copies using development-only `@resvg/resvg-js`. The independent `docs/` workspace package uses Astro 7.3.1 and Starlight 0.42.0; see [documentation maintenance](/SteamWrapper/development/documentation/) for its mise tasks and bilingual content workflow.

See the [Dioxus skill](https://github.com/YangYuS8/SteamWrapper/blob/v2/skills/dioxus-manager/SKILL.md) for that workflow. New WinUI work does not use its DOM/RSX or bundle steps.

<a id="工具链与交付"></a>

## Toolchain and delivery

mise manages project tools: .NET SDK 10.0.400 and Rust 1.98.1. Local MSVC/SDK components were checked again after reboot. Manager uses the component set corresponding to Windows App SDK 2.4.0, directly pinning `Microsoft.WindowsAppSDK.WinUI` 2.3.6, `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6, and SDK.BuildTools 10.0.26100.7705. Component package versions do not equal the framework name "WinUI 3". Pinning InteractiveExperiences explicitly prevents a fallback to the WinUI package's minimum 2.1.3 dependency. Retained dependency versions and hashes match the original 2.4.0 umbrella-package lockfile.

Selective component references are an officially supported Windows App SDK self-contained deployment method. Manager does not reference unused AI, ML, Search, Widgets, or DWrite components, and it does not shrink output by manually deleting published DLLs. The trimmed component selection produces a directory of about 171 MiB (457 files, uncompressed). See [preview validation](/SteamWrapper/project/validation/winui/) for the latest artifact byte count. Startup/memory measurements from the original 226.23 MiB build remain historical; those metrics have not been rerun for the smaller output. [Official component-package explanation](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003), [local comparison and publish validation](/SteamWrapper/project/decisions/manager-comparison/)

The target remains Windows 11 24H2 (26100) x64, self-contained with trimming disabled. Services use net10.0; tests use MSTest 4.4.0 / Test SDK 18.9.0; every project has a NuGet lockfile. Manager's project is maintained directly without alpha templates or a WinApp MSIX debug identity package. Publishing first builds and checks a new directory, then replaces old output to prevent stale dependencies. Commands, five publish regressions, and outstanding native/clean-system acceptance are in [Windows development](/SteamWrapper/development/windows/).

Existing Dioxus builds use `dx check`, `dx build --release`, and NSIS/AppImage bundles. Runner is named `SteamWrapperRunner.exe` on Windows and `steamwrapper-runner` on Linux. These commands apply only to the retained implementation and do not validate a WinUI installer. [Testing](/SteamWrapper/development/testing/) and [distribution](/SteamWrapper/development/distribution/) separately record current commands and target acceptance.

<a id="不选的方向"></a>

## Rejected directions

This iteration does not restore the removed Tauri/React implementation or introduce Electron, a Node UI runtime, or Python product components. It also does not expand the first Windows configuration-tool release merely to achieve all-Rust code, general cross-platform support, or a single EXE.

A C ABI, management helper, all-C# Runner, and MSIX each have conditions in which they may be useful; these remain in the assessment. The current choice addresses the actual UI, configuration safety, and independent game-lifecycle boundaries.
