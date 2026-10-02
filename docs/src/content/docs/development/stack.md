---
title: "SteamWrapper v2 technology stack"
description: "The WinUI/C# Manager, independent Rust Runner, and Windows-first development tools."
---

<a id="steamwrapper-v2-technology-stack"></a>
<a id="steamwrapper-v2-技术栈"></a>
<a id="目标方案"></a>

## Target design

**C#/XAML WinUI 3 is the sole Manager**, backed by independently testable C# Application services and an independent Rust Runner. The Windows configuration preview and self-contained directory build are implemented. Dioxus, its Rust Manager service layer, Native E2E, and GUI release workflow are removed; their historical results do not define the current product. See the [Windows design](/SteamWrapper/project/design/windows-v2/) and [WinUI assessment](/SteamWrapper/project/decisions/winui3/).

| Area | Current choice | Boundary |
| --- | --- | --- |
| Manager UI | WinUI 3, C#, XAML | Native Windows controls, pickers and accessibility; English default and complete Simplified Chinese |
| Manager services | C# Application | Profiles, local Steam discovery, Runner installation, logs; no Rust FFI or helper |
| Daily runtime | Independent Rust Runner | Existing CLI and process lifecycle; Manager closed during play |
| Configuration | `profiles.toml` v2 | C# edits preserve unknown/unedited data; actual Rust consumption is tested |
| Covers | Custom/local Steam images, optional official Steam CDN fallback and placeholders | Offline by default; bounded requests and SteamWrapper cache |
| Delivery | Unpackaged self-contained Windows layout; version-tag portable ZIP or manual preview artifact | Unsigned prereleases; per-user installer, signing and updater remain unfinished |
| Platform | Windows 11 24H2 x64 preview | Existing Linux Runner compatibility/CI only; no Linux GUI |

C# uses Tomlyn 2.10.1 syntax trees and field spans rather than whole-model serialization. It generates a Rust-readable TOML 1.0 string subset and preserves other source text. Fields, defaults, legacy aliases, paths and arguments are constrained by cross-language and real Runner tests. [Tomlyn package](https://www.nuget.org/packages/Tomlyn/2.10.1), [syntax API](https://github.com/xoofx/Tomlyn/blob/2.10.1/site/docs/low-level.md)

Runner remains Rust. The earlier NativeAOT alternative is an archived assessment, not another implementation or a planned simultaneous rewrite. Any future reconsideration needs complete CLI/TOML and platform process evidence. [NativeAOT documentation](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

<a id="当前仓库布局"></a>

## Current repository layout

```text
apps/manager-winui/SteamWrapper.Manager             # WinUI UI
apps/manager-winui/SteamWrapper.Application         # C# configuration services
apps/manager-winui/SteamWrapper.Application.Tests   # MSTest
crates/core                                       # Rust configuration/path contracts
crates/runner                                     # headless runtime called by Steam
tests/contracts                                   # C# / Rust contracts and driver
tests/fixtures                                    # controlled test processes
docs                                              # Astro/Starlight static site
```

<a id="rust-核心与服务"></a>

### Rust core and services

`steamwrapper-core` defines Profile/TOML, path and Launch Options contracts, and existing metadata utilities. It depends on neither GUI nor platform process APIs. Runner uses its configuration semantics. WinUI calls C# Application directly; it does not call core through an ABI. No Rust Manager service crate remains.

### Runner

`steamwrapper-runner` uses `clap`, `anyhow`, `tracing` and `steamwrapper-core`. It starts the profile's target/args and waits according to the selected mode, without GUI, WebView, .NET, or a persistent service.

New Windows profiles explicitly use `job`; legacy omitted `wait_mode` means `root`. Linux retains `process_group` support, with no current Linux Manager. `%command%` is received/logged, not executed or forwarded automatically. Proton integration remains unfinished. Platform process tests and actual Steam acceptance establish different facts.

<a id="当前-dioxus-manager"></a>
<a id="current-dioxus-manager"></a>

### Archived Dioxus implementation

The removed Dioxus 0.7.10 Manager, WDIO Native E2E and Rust service layer are accessible only as [historical source at ca6a09e](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus). The [2026-09-07 comparison](/SteamWrapper/project/decisions/manager-comparison/) and [2026-09-08 package inspection](/SteamWrapper/development/distribution/#dioxus-desktop-bundle) retain their measurements and limitations. They do not provide current build commands, supported packages, or a fallback Manager.

<a id="工具链与交付"></a>

## Toolchain and delivery

mise is optional. `global.json` selects .NET SDK 10.0.400; Rust 1.98.1 is the local reference in the optional mise configuration. Manifests, lockfiles, `packageManager` and `.vsconfig` define applicable versions/components. Direct PowerShell/pnpm commands do not require mise.

Manager uses the Windows App SDK 2.4.0 component set, directly pinning `Microsoft.WindowsAppSDK.WinUI` 2.3.6, `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6 and SDK.BuildTools 10.0.26100.7705. Package versions are not the framework name “WinUI 3”. Explicit InteractiveExperiences avoids its older minimum dependency. Selected dependency versions/hashes match the original 2.4.0 umbrella-package lockfile.

Selective component references are an officially supported self-contained deployment method. Manager omits unused AI, ML, Search, Widgets and DWrite components through project references, never manual removal of published DLLs. The 2026-09-07 component-reduction record measured about **171 MiB, 457 files** uncompressed. Earlier **226.23 MiB** startup/memory results remain historical and were not rerun for that smaller output. Later artifacts have their own inventories; these numbers are not a promise about every current build. [Official component guidance](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003), [comparison record](/SteamWrapper/project/decisions/manager-comparison/), [preview record](/SteamWrapper/project/validation/winui/)

The preview targets Windows 11 24H2 (26100) x64, self-contained with trimming disabled. Services use net10.0; tests use MSTest 4.4.0 / Test SDK 18.9.0, with NuGet lockfiles. The Manager project is maintained directly, without alpha templates or a WinApp MSIX debug identity package. Publishing builds and validates a fresh directory before replacing old output. See [Windows development](/SteamWrapper/development/windows/) for commands and publish regressions.

Node/pnpm serve brand generation and the static docs site, not desktop runtime. `pnpm brand:generate` / `pnpm brand:check` use development-only `@resvg/resvg-js` for canonical SVG/PNG/ICO assets. The `docs/` workspace uses Astro 7.3.1 / Starlight 0.42.0; see [documentation maintenance](/SteamWrapper/development/documentation/).

Daily Windows CI tests/contracts and compiles the actual Manager without packaging it. The version-tag/manual release workflow produces the complete layout with `Runner/SteamWrapperRunner.exe` and version/hash metadata; tags add a portable ZIP, bilingual notes and checksums for an unsigned prerelease. Rust CI preserves Linux process compatibility. A WinUI installer, signing, updater and automatic Steam Launch Options writes remain [roadmap](/SteamWrapper/project/roadmap/) work; no Linux GUI package is advertised. See [distribution](/SteamWrapper/development/distribution/) for release preparation.

<a id="不选的方向"></a>

## Rejected directions

The current product does not retain Dioxus or restore Tauri/React, Electron, a Node UI runtime, or Python runtime components. It adds no C ABI, management helper, or all-C# Runner rewrite. Windows 10, ARM64, MSIX, Linux GUI and SteamOS/Proton expansion require separate decisions and evidence; Windows x64 preview results do not establish them.
