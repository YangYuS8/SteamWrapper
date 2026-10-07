---
title: "Windows v2 product and architecture redesign"
description: "Windows product requirements, configuration fidelity, architecture, and implementation stages."
---

<a id="windows-v2-product-and-architecture-redesign"></a>

<a id="windows-v2-产品与架构重设计"></a>



Date: 2026-09-08. Status: following implementation authorization, the WinUI configuration preview, safe C# configuration services, and cross-language/real Runner contracts are implemented. The implementation baseline passed remote WinUI CI. [Real galgame testing](/SteamWrapper/project/validation/steam/) completed the Steam → Runner → game flow for one Unity game and five independent translated 9-nine packages outside the Steam library, including ordinary exit and Steam status/playtime updates. All five had their Chinese openings verified. After Episode 1's CHS entry was restored, the local launcher-exits-first/game-and-Runner-keep-waiting scenario also passed; the original entry's earlier product-ID-check failure remains in the record.

The earlier OS Error 3 was traced to the development host's AppData redirection, and actual file-location checks were added. Broader launcher compatibility, the installer, and clean-system acceptance are unfinished. This is the main Windows implementation plan, replacing the earlier default `manager-ffi` approach.

**2026-10-02 implementation update:** WinUI is now the only Manager. At the user's request, the Dioxus application, Rust `manager-core`, Dioxus Native E2E and old UI release chain have been removed. Their historical source remains available at `ca6a09e`. This supersedes the original staged-retirement decision; it does not change the September measurements or complete the remaining Windows acceptance gates. Mainline integration still delivers a preview, not a stable release. Current priorities are in the [roadmap](/SteamWrapper/project/roadmap/).

<a id="current-acceptance-2026-10-06"></a>

## Current acceptance (2026-10-07)

The September status above is historical. The first stable Windows release is now **[v0.2.7](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.7)** with matching [CNB assets](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.7), within the bounded **Windows 11 24H2 x64, current Windows/Steam account** core scope. [Run 37500459000](https://github.com/YangYuS8/SteamWrapper/actions/runs/37500459000) passed all nine jobs and published tag commit `0987802b86460eff711c6cf694015cdbf086bbb2`. All seven assets from each source passed independent anonymous length/hash, tag-commit and schema-2 inventory checks. Both sources' stable and preview feeds passed project-signature, validity and exact-installer checks, with identical bytes within each channel. This public inspection did not execute Setup; future releases still require exact-tag CI and actual delivery verification.

Before publication, the recorded source passed 178 Application, 37 Windows and 160 Deployment tests with one conditional cross-volume skip, plus Runner contracts. Genuine isolated 0.2.6 → 0.2.7 installation/rollback/re-upgrade passed 13 outcomes. The private portable candidate passed ten SDK-free build-26100 steps, including Chinese-folder configuration, Manager relocation and headless Runner use. Five actual NativeAOT Host language cases passed separately. Recorded bilingual native 16-case, physical Pinyin and active-display DPI slices establish the core UI scope, while their actual payloads and separate fixture/guest boundaries remain recorded. The private SDK-free lifecycle payloads predate the final Runner process-name fix and are not the later public v0.2.7 bytes. These checks do not establish every account/hardware combination.

The actual CNB public 0.2.5 → 0.2.6 manual update passed all 12 native/installer steps: signed feed, exact network download without a mapped target Setup, normal old Manager exit, actual Setup, automatic healthy restart, byte-identical profile/preferences/trust state, explicit profile Save to install the corrected Runner, headless launch and default uninstall preservation. The older Runner was preserved during Manager replacement and was not executed. The separate explicitly selected GitHub download timed out under the unchanged product policy; no target installer ran and the old installation/data remained unchanged. Its failure record remains a failure. Neither result covers enabled startup checks or every network.

The actual production-family private 0.2.7 Setup (SHA-256 `5c9ab6482f67711bc61813563e687cf13c2f10b79f47a1930127502e3b4a6b5f`) passed all **14 product lifecycle steps** in a fresh offline build-26100 guest without an SDK or prepared runtime. A new Users/Medium primary token for the current primary SID had no Administrator SID or enabled critical administrative privileges. Manager loaded its own .NET/XAML modules, saved configuration and installed Runner; repair, default uninstall, Chinese-directory reinstall and standalone Runner after uninstall/relocation passed. Two Manager and three Runner exits were actually observed as 0. Temporary WinSta0/Default security descriptors and original 544/545/555 group membership restored exactly. This is actual ordinary-permission product execution, with `freshStandardAccount=false`, `primaryStandardSignInTested=false` and `twoUserGuiTested=false`, rather than a controller-only pass.

The earlier fresh SwAcc cross-user secondary-logon trial installed Setup but failed at WinUI `Application.Start` with `0x8000FFFF`; the empty same-SDK control failed before its callback too. The cause is not precisely identified, and those failures remain recorded. Cross-user RunAs in another account's existing desktop is outside the first release's current-account flow. The passing same-SID lane does not prove its root cause, a new primary standard-account sign-in or two-user GUI use.

Actual NativeAOT 0.2.5 → 0.2.7 copying/recovery passed on an owned 512 MiB guest VHD using locally rebuilt manifests, with `actualInno=false`. The helper wrote a journal and a 26,424-byte partial payload, then exited 11 with 4,096 bytes free; the old installation and data stayed unchanged. After removing only its own filler, repair exited 0 and the VHD detached normally. Earlier test-tool failures remain recorded. This establishes that mid-copy disk-full/recovery lane, not an Inno fault, system-disk exhaustion or power-loss recovery.

Earlier Microsoft Pinyin composition/commit/cancel and byte-preserving Save passed; the corrected candidate window was observed at 96/144/192 DPI on the active display, with host scale restored to 125% and 28 placement regressions passing. These observations do not establish multi-monitor hardware or every dialog/language/scale combination against later payloads. [Testing](/SteamWrapper/development/testing/#current-acceptance-2026-10-06) records exact artifacts and preserved failures; [the roadmap](/SteamWrapper/project/roadmap/) separates core acceptance, verified publication and later expansion.

<a id="1-回到最初要解决的问题"></a>

## 1. Return to the original problem

**Let Windows players launch translated games or custom launchers through Steam, keeping Steam play status and playtime aligned with the actual game lifecycle as far as possible. Configure once; normally just click Play in Steam.**

The requirements below come from repository history, not speculation about unavailable earlier conversations:

| Repository material | Confirmed requirement |
| --- | --- |
| `f95770b:README.md` (historical v1 baseline) | A Windows utility for Steam playtime with translated/custom-launcher galgames |
| `6cb8835:README.md` (first v2 design) | Configure once; separate Manager/Runner; Windows first; no player-installed .NET Runtime, no default SteamEdit requirement, and no full wrapper copied into every game |
| `e244269:docs/architecture.md` | Steam Launch Options calls an independent Runner; read configuration by AppID; no injection, client modification, DRM bypass, or persistent service |
| `c871c21:docs/roadmap.md` | Basic Windows flow → safe Windows one-click apply → Windows compatibility, with Linux/SteamOS in later major versions |
| `bf8929a:docs/distribution.md` | Per-user installer for ordinary players; stable user-directory Runner; portable as an alternative |

The later `d0ae626:docs/roadmap.md` moved Linux/SteamOS/Proton earlier and one-click apply/Windows distribution later. That was a change in delivery order, not evidence that cross-platform support was always a prerequisite for the first Windows release. C#, Rust, egui, Tauri, and Dioxus appeared at different points in the technical history; using one language was not an original product requirement.

Here, "no .NET Runtime installation" means **players need no manual runtime preparation**. A self-contained C# installer can meet that experience goal, but it must be verified on a clean system, not inferred from project properties. Initially target supported Windows 11 x64; do not yet promise Windows 10 or ARM64. This is an implementation choice, not a claim that the original requirements prohibited other systems.

<a id="2-产品范围与玩家流程"></a>

## 2. Product scope and player flow

Manager is a configuration tool. Its home page centers on configured games and adding a game; a complete library browser or cross-platform distribution platform must not drive the first version's scope.

1. Install and open Manager; check configuration and bundled Runner. If Runner is unavailable, configuration remains viewable/editable and the relevant error is shown near the action.
2. Add a game: discover local Steam and installed games, with search. Allow manual selection of custom Steam installations and preserve other results if part of a library is unreadable. A manually created Steam profile requires an explicit AppID.
3. Show the read-only Steam installation path separately from the selected runtime folder and translated exe/launcher. The runtime folder may be outside the Steam library and must not be overwritten by scanning. Arguments, working directory, and wait mode belong in advanced settings, with existing values fully preserved. See [directory separation](/SteamWrapper/guides/translated-games/) for official installations, translated copies, saves, and achievements.
4. Save the configuration and verify stable Runner, then preview an explicit single-account application with original-value backups. Steam must exit normally. Save-only and manual copying remain available; manual pasting requires preserving old options separately. See the [apply/restore design](/SteamWrapper/project/design/steam-launch-options/) for acceptance status.
5. Close Manager, launch and exit the game from Steam, and return to that game's error/log location if something goes wrong.

Distinguish configuration saved, Launch Options copied, written and verified on disk, and validated in the Steam client. Button clicks, TOML saves, or Runner exit codes do not establish correct Steam playtime.

WinUI covers are local-first and offline by default: custom Steam art takes priority over local library-cache images, including hashed filenames and nested hash directories. An explicit, reversible preference enables official Steam CDN fallback for missing art on locally discovered AppIDs, with bounded requests and a small SteamWrapper cache. Missing, unreadable or unavailable images leave friendly placeholders and never affect saving or launch. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings) and the remaining [P0 acceptance gates](/SteamWrapper/project/roadmap/). Supported system language by default with English fallback and complete Simplified Chinese support, keyboard use, native file selection, scaling, and recoverable errors remain basic experience requirements.

The initial Manager window uses 1160 × 900 effective pixels, converted using the actual XAML scale and bounded to the current display's work area. Both size and screen position are bounded; the display-relative work-area offset is converted to screen coordinates before placement. This applies once on initial loading and does not override later user resizing. [Microsoft's work-area definition](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.displayarea.workarea) and [window placement coordinates](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindow.moveandresize) describe the native boundary; actual scale observations are recorded in [testing](/SteamWrapper/development/testing/).

Account login, online game metadata, general mod management, multiple-target switching, persistent tray operation, background update services, a new Linux/SteamOS GUI, Proton, and store distribution are out of scope for now. Steam Overlay, achievements, and every third-party launcher's compatibility are not default promises.

<a id="3-技术决定"></a>

## 3. Technical decisions

Use a **C#/XAML WinUI 3 Manager + independent Rust Runner**. WinUI is the sole Manager implementation. Implement its Windows configuration services in C#, using existing files to work with Runner:

```text
WinUI 3 Manager
  Views / ViewModels
          ↓
  C# application services: configuration read/edit/write, Steam discovery,
  Launch Options, Runner installation, logs
          ↓
  %LOCALAPPDATA%\SteamWrapper\profiles.toml
  %LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe

Steam → existing Launch Options → Rust Runner → read profile → launch/wait for target
```

Manager need not call Runner's internal functions. TOML, CLI, and stable paths already form a persistent boundary. Adding a C ABI would introduce DLL architecture, string/buffer ownership, error/panic propagation, and release synchronization. There is no current requirement for a second new GUI, so `manager-ffi` is not selected. Implementing configuration in two languages still costs maintenance; the compatibility checks below are a prerequisite. [Microsoft native interop guidance](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)

An all-C# Runner with NativeAOT is also viable and need not depend on preinstalled .NET, but it would simultaneously require reimplementing Job Objects, suspended launch, and process regressions. Retain Rust Runner first rather than coupling UI migration with a lifecycle rewrite. Do not infer startup speed, memory, or package size from language without measurements. [Official NativeAOT documentation](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

Established directories:

```text
apps/manager-winui/
  SteamWrapper.Manager/           # WinUI window, ViewModel, platform wiring
  SteamWrapper.Application/       # independently testable configuration/file services
  SteamWrapper.Application.Tests/
tests/contracts/                 # redacted shared C#/Rust config and process fixtures
```

Services expose a small set of named operations; file and scan work is cancellable and does not block UI. Do not add generic RPC, background helpers, a DI plugin platform, or multiple transport-DTO layers. C# models implement the existing protocol rather than creating a second configuration format.

`crates/core` and the independent Rust Runner retain their protocol and process responsibilities; Windows configuration services live in C#. The former [Dioxus app](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus), [Rust management layer](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core) and [UI release workflow](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/.github/workflows/release.yml) are historical references. They were removed on 2026-10-02, rather than retained as a second Manager or future retirement task. The C#/Rust file-contract checks remain necessary.

<a id="4-配置保真是第一个门槛"></a>

## 4. Configuration fidelity is the first gate

These contracts remain unchanged: v2 `profiles.toml` format, fields, and enum meanings; Windows `%LOCALAPPDATA%\SteamWrapper\`; Runner `bin\SteamWrapperRunner.exe`; and the CLI:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Two behaviors in the historical management/configuration code at `ca6a09e` motivated the requirements below. They are not descriptions of the current C# configuration service:

- [Manager saving](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/crates/manager-core/src/lib.rs) reconstructed Profile, resetting `args`, `working_dir`, `wait_mode`, and `process_name`. Changing a target path must not discard those settings.
- [Configuration saving](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/crates/core/src/config.rs) called `fs::write` directly, without atomic replacement or editing-conflict checks. Atomic Runner installation does not make profile saving safe.

The C# configuration service must continue to satisfy:

| Area | Required preserved or verified meaning |
| --- | --- |
| Read/edit/write | Change edited fields only; retain other profiles, non-Windows entries, and unknown keys. Block and explain writes when the library cannot preserve them safely. Do not downgrade unknown format versions |
| Defaults | Omitted legacy `wait_mode` currently means `root`; only new Windows profiles explicitly write `job`. Interpret omitted `args`, `working_dir`, and other fields as the current Rust parser does |
| Identity | Profile table key and `app_id` are different fields. Preserve legacy alias keys. New Steam profiles use an explicit AppID; do not guess associations or renumber ambiguous entries |
| Paths/arguments | Chinese, spaces, quotes, backslashes, argument arrays, and relative paths. Resolve target/working_dir against game_dir; do not turn an argument array into a new command-line format |
| Write safety | Same-directory temporary files, flushing, backup, and atomic replacement; preserve old files on failure. Prevent cooperating app writers and report external changes after reading, without claiming all external editors can be locked |
| Real consumption | C# TOML is checked for complete semantics by the existing Rust parser, then drives a controlled Runner to verify argv/cwd/waiting. Editing one field of a historical Rust fixture in C# must preserve unedited meaning |

The original TOML-library selection criterion was this roundtrip experiment, rather than an unverified package choice. It remains a regression requirement: cover omitted values, all existing wait modes, alias keys, unknown fields/versions, interrupted writes, and competing writers. Comparing a few text files or showing that both sides parse is insufficient.

<a id="5-runner-与-steam-验收"></a>

## 5. Runner and Steam acceptance

[Current Runner](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/main.rs) launches the profile's `target` and `args`. It receives/logs `steam_command`, without executing or automatically appending it. Keeping `%command%` is a compatibility contract, **not implemented original-command forwarding**. Migration must not also launch the original executable, automatically fall back to the official game, or change argument semantics.

New Windows profiles default to `job`. Real tests must cover launcher-first exit, later child exit, launch failure, Chinese/spaced paths, argv/cwd, Runner error exit, and logs. `root` waits only for the direct child. `process_name` is an explicit compatibility choice, not proof that a same-name process belongs to the game.

The local Episode 1 CHS launcher-first scenario passed: after the launcher exited at 14:15:55, the actual game and Runner continued for about 2 minutes 21 seconds until ordinary exit at 14:18:15; Steam playtime changed from 36 to 38 minutes. UI confirmed `job`, independent process observations had no sampling or metadata failures, and no processes remained. This does not directly establish Job membership or guarantee arbitrary launchers. The current [Windows implementation](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/platform/windows.rs) returns the launcher's status after Job completion; CHS/Runner exit 0 in this log is not the actual game's exit 0.

Job Objects do not cover arbitrary escape behavior. Child membership depends on creation, breakaway, and parent-job conditions. General completion-port notifications cannot be treated as universally guaranteed delivery. Query and verify actual process state for exceptional cases rather than declaring correctness from API use alone. [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)

Routine automation uses isolated Steam/user directories and controlled processes. Release acceptance separately records real Windows Steam launches with Manager closed, Steam showing running during play and ending afterward, client playtime updates, and game/launcher/system versions. Agent operation on a real library requires explicit user authorization; this session's user authorized real galgame tests on condition that game files remain undamaged. Record old Launch Options and check files before testing, restore options and recheck afterward, and do not resolve ambiguous save/cloud conflicts. Without real evidence, report only the lifecycle behavior established by fixtures.

<a id="6-安全一键应用与恢复"></a>

## 6. Safe one-click apply and restore

Earlier `v0.2.8` supports manually copied Launch Options and clearing recognized generated commands. **Released `v0.2.9` adds explicit single-account application and recorded-original restoration.** Source/native fixtures, the scoped local Episode 1 client session, exact-tag public asset/feed checks and the exact public installer's 18-step clean upgrade passed within their recorded scopes. The [account-specific design](/SteamWrapper/project/design/steam-launch-options/) defines the player flow, backups, recovery and delivery gates. It does not depend on the optional P3 updater. Keep manual copying and the existing safety fallback available.

Do not treat Steam's private local files as a stable public write API. Recheck actual structures before implementation and verify parsing/unrelated-data preservation using redacted fixtures. The flow must:

- Identify the game and Steam user. Let the player choose among multiple users rather than writing every account.
- Detect running Steam and ask the player to exit it; check again before writing without automatically terminating Steam.
- Preview old/new values; back up options, relevant files, and recovery identifiers; check for changes immediately before writing.
- Edit only the target value, write atomically, read back, and record completed/interrupted state. Leave the original untouched on parse, backup, or conflict failure.
- Automatically restore only when the current value still matches this tool's written value. Preserve and explain later external changes. Never overwrite later changes to other games using a whole old backup.

The manual-copy stage must not claim automatic old-value backup or one-click restore. Existing launch parameters may matter to the game; do not silently discard them or append them to the new profile. Preview and migration guidance should let the player handle them explicitly.

<a id="7-安装更新卸载"></a>

## 7. Installation, updates, and uninstall

**Implementation baseline, 2026-10-05:** P1 provides an **unpackaged self-contained per-user Inno installer and portable ZIP** sharing one application layout and bundling .NET and Windows App SDK. Ordinary players need no development tools or manual runtime preparation. Runner remains an independent Rust EXE; no single-file EXE is promised. The installer exists and isolated installation/upgrade tests have passed, while clean-client and broader recovery acceptance remain open. This updates the September implementation status above. [Official self-contained deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

First installation defaults to `%LOCALAPPDATA%\Programs\SteamWrapper\` and can select a validated empty directory on a fixed local drive. Updates and repair stay at the registered location; relocation means Manager-only uninstall keeping data, then installation at the new location. Start menu shortcuts default on, desktop shortcuts default off, and setup offers opening Manager on completion. Manager separately verifies and prepares the stable Runner under `%LOCALAPPDATA%\SteamWrapper\bin`. A busy Runner preserves the old binary, configuration and valid options for a retry after play. Version/compatibility checks prevent arbitrary downgrades; a changed hash alone does not establish an upgrade.

Default uninstall removes only Manager, its shortcuts and registration. Seven independent opt-in choices remove recognized Steam Launch Options, downloaded cache, logs, preferences, profiles, profile backups or verified Runner files. With Steam closed, exact standard commands are backed up and cleared; custom commands and unknown historical values are not reconstructed. Profiles/Runner deletion requires a complete account scan without remaining Runner references or unresolved restoration backups. Unknown/busy files, games/saves, update trust state and Steam restoration backups remain protected. Nine isolated native selection scenarios passed for the frozen 0.2.6 shared cleanup logic: seven individual choices, restore/profiles/Runner together and all seven together. The production 0.2.7 ordinary-permission lane separately verified default preservation; not every language or production-0.2.7 selection was rerun. Earlier bilingual cancellation/cache/layout checks retain their own scope. See the [installer guide](/SteamWrapper/guides/installer-preview/) for the controls and safeguards.

Every changed installer or portable payload needs verification tied to its actual bytes; source tests alone are insufficient. The passed core includes SDK-free WDAG install/upgrade/portable, the 0.2.7 ordinary-permission product lifecycle, genuine isolated upgrade/rollback, default data preservation, scoped cleanup and registry/shortcut recovery portions, and bounded retention. The owned-VHD NativeAOT mid-copy repair uses local manifest fixtures and does not execute Inno. Preserve earlier overall failures even when a recorded portion passed. Full new-account sign-in, two-user GUI, additional hardware/build/language combinations and physical power loss remain separate assessments. Keep host-side fixtures, guest product execution and independent-ISO evidence distinct. Package/installed size and observed startup are recorded before optimization; MSIX, ARM64 and Windows 10 remain later scope.

P2 automates version-tag delivery of Setup and portable ZIP, checksums and complete English/Simplified Chinese notes; matching public `v0.2.6-preview.1` assets have been verified on GitHub and CNB. P3 has provided manual checks, opt-in startup checks, project-signed metadata, bounded verified downloads and confirmed handoff to the existing installer since `0.2.5`. Windows Authenticode is optional, independent of the required project-update signature. The earlier actual isolated `0.2.4` → `0.2.5` handoff remains historical evidence; CNB's public 0.2.5 → 0.2.6 native download-to-install lane now passed separately, while GitHub's real timeout failure and broader automatic-check/native/client/recovery gates remain recorded. Manager updates preserve existing stable Runner bytes. When an older known Runner needs correction, Manager explains the explicit profile Save that installs the bundled Runner; Manager replacement does not silently replace it or prove that the older binary works. See [distribution](/SteamWrapper/development/distribution/) and [testing](/SteamWrapper/development/testing/). Updates remain outside Runner's daily launch path and preserve user data.

<a id="8-实施顺序与停止条件"></a>

## 8. Implementation order and stop conditions

The following A–D stages preserve the original 2026-09-08 acceptance framework. They are requirements, not a claim that every stage has passed; the [roadmap](/SteamWrapper/project/roadmap/) separates completed evidence from remaining P0–P4 work. The original E retirement condition was superseded by the explicit 2026-10-02 removal decision.

| Stage | Completion condition |
| --- | --- |
| A. Toolchain/contracts | Pin .NET / Windows App SDK / Windows SDK / Rust MSVC; runnable Windows Runner baseline; passing C#↔Rust fidelity and controlled-process checks; viable lossless writes |
| B. WinUI configuration slice | Select fixture games/targets in a native window, preserve configuration, install stable Runner, and copy exact options; recover from cancellation/missing directories/unwritable or busy files; usable keyboard/Chinese input/scaling |
| C. Usable Windows preview | Real Windows/Steam launch records; clean-VM self-contained installation, updates, Manager relocation, and uninstall preservation; documentation of manual restore and known compatibility |
| D. Safe apply/stabilization | Pass multiple-user, Steam-running, backup, conflict, interruption, and single-game restore checks; expand real launcher testing; then consider default one-click apply |
| E. Original cleanup decision (superseded) | The original design deferred replacing the default Manager/CI and retiring Dioxus until C. The user directed removal on 2026-10-02; unfinished delivery gates remain open. Consider new platform scope only after Windows stabilization |

The original implementation order began with the A→B configuration/controlled-launch slice and incremental Windows build/contract CI. Its decision to retain the old UI workflows is now superseded. Current work proceeds through P0 native WinUI UI automation, broader player feedback and explicitly optional local-first covers; P1 installer/portable acceptance; P2 tagged releases; P3 optional updates; and P4 safe Steam writes. P0 feedback and P1 preparation can overlap, and P4 does not depend on P3. A polished UI or removal of an old implementation does not establish a stable release when configuration, lifecycle or delivery gates remain incomplete. mise is optional; see [Windows development](/SteamWrapper/development/windows/) for SDK requirements, direct commands and scoped validation records.
