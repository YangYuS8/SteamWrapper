---
title: "WinUI 3 migration assessment"
description: "Dated WinUI migration assessment, alternatives, dependencies, and deployment constraints."
---

<a id="winui-3-migration-assessment"></a>

<a id="winui-3-迁移技术评估"></a>



Verified on 2026-09-07. This document records the pre-implementation technical basis, alternatives, and environment limitations. The first configuration preview was subsequently implemented according to the [Windows v2 product and architecture design](/SteamWrapper/project/design/windows-v2/). See [preview validation](/SteamWrapper/project/validation/winui/) for the latest implementation/verification status; the new installer is unfinished.

Post-implementation same-input service comparisons, functional gates, and resource measurements are in the [Windows Manager comparison](/SteamWrapper/project/decisions/manager-comparison/). Framework decisions should consider these actual results and their measurement boundaries.

<a id="建议与取舍"></a>

## Recommendation and trade-offs

Use a **C# + XAML WinUI 3 Manager, C# application services, and an independent Rust Runner**, connected by existing TOML, stable paths, and CLI. The initial default recommendation to retain manager-core and add manager-ffi was withdrawn: this Windows configuration tool has no requirement to share an in-process Rust management layer, and ABI reuse does not justify the additional boundary.

WinUI 3 is Microsoft's native Windows UI framework, officially supporting C# and C++, with framework support from Windows 10 1809/build 17763. This project first validates supported Windows 11 x64. The framework minimum is not a product support promise. [WinUI 3 overview](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/), [platform language support](https://learn.microsoft.com/en-us/windows/apps/develop/platform/)

| Option | Decision and cost for this project |
| --- | --- |
| C# WinUI + C# configuration services + Rust Runner | Adopted; Windows configuration and game lifecycle remain independent. The cost is implementing one TOML protocol in two languages, controlled by real read/edit/write and Runner-consumption tests |
| C# WinUI + Rust manager-core / C ABI | Not adopted now; saves some porting but adds encoding, buffer ownership, error/panic handling, DLL architecture, and release compatibility. Reassess if two GUIs soon need to share mature management logic |
| All C#, NativeAOT Runner | Technically viable and may unify tooling, but requires rebuilding Windows process control and compatibility verification; not tied to this UI migration |
| C# WinUI + Rust management helper CLI | Isolates process failures but adds a third executable, protocol, cancellation/timeouts, and version coordination; insufficient benefit for current file-management needs |
| C++/WinRT or WinUI directly in Rust | C++ is officially supported, but this repository has no reusable C++ GUI. Rust would require more language-projection/toolchain work and is not selected for the first version |

ABI costs follow [Microsoft's native interop guidance](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices). [NativeAOT](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/) can produce native programs without preinstalled .NET, but requires handling trimming, dependency compatibility, and platform build tools. It cannot be dismissed on the claim that C# always requires players to install a runtime. These architecture choices are project-specific engineering judgments, not a framework performance ranking.

<a id="当前代码与迁移风险"></a>

## Existing code and migration risks

| Existing component | Migration treatment |
| --- | --- |
| [Profile/TOML](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/config.rs), [fields and defaults](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/profile.rs) | Define the compatibility protocol; validate C# with cross-language roundtrips and actual Runner parsing |
| [ManagerService](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/manager-core/src/lib.rs) | Maintain only for the existing Dioxus chain; the C# app need not call it |
| [Runner installation](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/manager-core/src/runner.rs) | Hashing, temporary files, flushing, atomic replacement, and failure preservation are behavior references; validate the C# implementation separately on Windows |
| [Steam scanning](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/steam.rs) | Current Windows discovery mainly checks environment variables and Program Files; the new implementation must handle custom locations and partial library-read failures. Existing VDF parsing is not a validated writer |
| [Windows Runner](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/runner/src/platform/windows.rs) | Retain suspended launch, Job Object, and waiting code, constrained by real processes and Steam acceptance; do not move it into GUI |
| [UI contract](https://github.com/YangYuS8/SteamWrapper/blob/v2/apps/manager-dioxus/tests/ui_contract.rs) | String assertions cannot become evidence of native WinUI interaction, layout, or accessibility |

The current `save_profile` resets advanced fields and `config.save` writes directly. FFI reuse therefore does not automatically provide lossless saving. The new design requires editing only changed fields, protecting unknown fields/versions, atomic writes, and conflict detection; see the [configuration gate](/SteamWrapper/project/design/windows-v2/#4-配置保真是第一个门槛). Missing legacy `wait_mode` means `root`; only new Windows profiles explicitly default to `job`.

Initial source comparison found that [manager_service.rs](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/manager-core/tests/manager_service.rs) hardcoded `process_group` in its save test while Windows selects `job`. After toolchain installation, the failure was reproduced and fixed with an independent platform-specific expected value, retaining other format assertions. Product defaults did not change. The existing Manager also lacks one-click Steam Launch Options apply/restore.

<a id="部署与稳定路径"></a>

## Deployment and stable paths

The first target is an **unpackaged directory + .NET self-contained + Windows App SDK self-contained**, wrapped by a per-user installer. Both self-contained settings need separate configuration and clean-system testing. Dependencies still contribute to package size and need version maintenance. [Official self-contained deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager, bundled dependencies, Runner resources
%LOCALAPPDATA%\SteamWrapper\profiles.toml
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
"<stable-runner-path>" --appid "<appid>" -- %command%
```

There is no Rust bridge DLL. Manager safely installs Runner resources at the stable path. Updating, moving, or uninstalling Manager must not break existing Launch Options. Remove references before deleting Runner; preserve it by default when references cannot be established. See [installation and uninstall](/SteamWrapper/project/design/windows-v2/#7-安装更新卸载).

MSIX remains a later assessment of package identity, manifest execution model, and path access. Do not simply switch to `ApplicationData.LocalFolder`; prove that Steam, Runner, and Manager read the same stable data. AppData virtualization depends on the execution model; not every MSIX redirects it. [MSIX execution models](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)

The first version does not promise a single-file EXE. The [deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview) and self-contained guidance do not describe single-file support identically; use the pinned build and clean-system runtime results as evidence.

<a id="工具链与当前机器"></a>

## Toolchain and the current machine

On the verification date, Microsoft's stable page listed Windows App SDK **2.4.0, released 2026-08-13**. Pin a validated stable package for implementation rather than copying versions from old tutorials. [Release channels and support lifecycle](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)

The then-current official quickstart offered Visual Studio 2026 with the WinUI application development workload, plus a .NET 10 SDK CLI-template route. A matching Windows SDK is required; Rust's MSVC target additionally needs the C++ toolchain. [WinUI quickstart](https://learn.microsoft.com/en-us/windows/apps/get-started/start-here)

Initial local inspection results (installation later progressed, as described below):

- `dotnet --info`: Host 10.0.11 x64 with .NET/WindowsDesktop runtimes, but **No SDKs were found**.
- Standard locations had no `vswhere` / Windows Kits Include, and `msbuild` was not on PATH. This did not establish that no installation existed elsewhere on the machine.
- The preceding attempt at `cargo test --workspace`, required by the original AGENTS, exited during dependency compilation with `link.exe not found`; tests did not execute. This documentation-only redesign did not repeat the known blocked command.

Later the same day, after the user authorized mise environment setup, project .NET SDK, Rust/PowerShell, and official MSVC/Windows SDK components were installed, and isolated self-contained WinUI publishing passed. The installer returned 3010 without an automatic reboot; the components were detectable. Use the newer [Windows development record](/SteamWrapper/development/windows/), not the historical missing-SDK/linker finding, to describe the current environment.

<a id="验证路径"></a>

## Validation path

Complete toolchain and configuration contracts first, then the WinUI configuration slice, independent Runner launch, clean Windows installation/updates, and finally replace the default Manager/build chain. The [main design](/SteamWrapper/project/design/windows-v2/#8-实施顺序与停止条件) and [roadmap](/SteamWrapper/project/roadmap/) define stages and stop conditions.

Dioxus WDIO tests cannot cover new WinUI windows. Native UI automation must be established, with XAML/UI-thread tests arranged correctly. Automation uses isolated data; real Steam status/playtime requires separate manual acceptance. [WinUI testing guidance](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/testing/)
