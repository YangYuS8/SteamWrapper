<a id="windows-v2-产品与架构重设计"></a>

# Windows v2 product and architecture redesign

English | [简体中文](windows-v2-design.zh-CN.md)

Date: 2026-09-08. Status: following implementation authorization, the WinUI configuration preview, safe C# configuration services, and cross-language/real Runner contracts are implemented. The implementation baseline passed remote WinUI CI. [Real galgame testing](real-steam-validation.md) completed the Steam → Runner → game flow for one Unity game and five independent translated 9-nine packages outside the Steam library, including ordinary exit and Steam status/playtime updates. All five had their Chinese openings verified. After Episode 1's CHS entry was restored, the local launcher-exits-first/game-and-Runner-keep-waiting scenario also passed; the original entry's earlier product-ID-check failure remains in the record.

The earlier OS Error 3 was traced to the development host's AppData redirection, and actual file-location checks were added. Broader launcher compatibility, the installer, and clean-system acceptance are unfinished. This is the main Windows implementation plan, replacing the earlier default `manager-ffi` approach. Dioxus code and CI remain the migration baseline.

<a id="1-回到最初要解决的问题"></a>

## 1. Return to the original problem

**Let Windows players launch translated games or custom launchers through Steam, keeping Steam play status and playtime aligned with the actual game lifecycle as far as possible. Configure once; normally just click Play in Steam.**

The requirements below come from repository history, not speculation about unavailable earlier conversations:

| Repository material | Confirmed requirement |
| --- | --- |
| `f95770b:README.md` (legacy main) | A Windows utility for Steam playtime with translated/custom-launcher galgames |
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
3. Show the read-only Steam installation path separately from the selected runtime folder and translated exe/launcher. The runtime folder may be outside the Steam library and must not be overwritten by scanning. Arguments, working directory, and wait mode belong in advanced settings, with existing values fully preserved. See [directory separation](translated-games.md) for official installations, translated copies, saves, and achievements.
4. Save configuration and generate exact Launch Options after confirming stable Runner is available, then paste them into Steam Properties. Tell players to preserve the old options first and explain restoration. Successful copying means copied only.
5. Close Manager, launch and exit the game from Steam, and return to that game's error/log location if something goes wrong.

Distinguish configuration saved, Launch Options copied, applied to Steam (only after future writes and verification), and manually validated launch. Button clicks, TOML saves, or Runner exit codes do not establish correct Steam playtime.

The first version reads local covers only, with friendly placeholders that do not affect saving or launch. Existing Dioxus Steam CDN fallback code remains; the first WinUI version does not inherit that request. English default and complete Simplified Chinese support, keyboard use, native file selection, scaling, and recoverable errors are basic experience requirements.

Account login, online game metadata, general mod management, multiple-target switching, persistent tray operation, background update services, a new Linux/SteamOS GUI, Proton, and store distribution are out of scope for now. Steam Overlay, achievements, and every third-party launcher's compatibility are not default promises.

<a id="3-技术决定"></a>

## 3. Technical decisions

Use a **C#/XAML WinUI 3 Manager + independent Rust Runner**. Implement Manager's Windows configuration services in C#, using existing files to work with Runner:

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

During migration, `crates/core` continues providing existing Runner/Dioxus functionality; `crates/manager-core` serves only the retained Dioxus chain. New WinUI functionality is implemented once in C#. Retire Dioxus, old management layers, and build infrastructure according to actual dependencies only after WinUI passes replacement gates, not by deleting them during design.

<a id="4-配置保真是第一个门槛"></a>

## 4. Configuration fidelity is the first gate

These contracts remain unchanged: v2 `profiles.toml` format, fields, and enum meanings; Windows `%LOCALAPPDATA%\SteamWrapper\`; Runner `bin\SteamWrapperRunner.exe`; and the CLI:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Current source exposes two behaviors to fix rather than directly port:

- [Manager saving](../crates/manager-core/src/lib.rs) reconstructs Profile, resetting `args`, `working_dir`, `wait_mode`, and `process_name`. Changing a target path must not discard those settings.
- [Configuration saving](../crates/core/src/config.rs) calls `fs::write` directly, without atomic replacement or editing-conflict checks. Atomic Runner installation does not make profile saving safe.

The new configuration service must satisfy:

| Area | Required preserved or verified meaning |
| --- | --- |
| Read/edit/write | Change edited fields only; retain other profiles, non-Windows entries, and unknown keys. Block and explain writes when the library cannot preserve them safely. Do not downgrade unknown format versions |
| Defaults | Omitted legacy `wait_mode` currently means `root`; only new Windows profiles explicitly write `job`. Interpret omitted `args`, `working_dir`, and other fields as the current Rust parser does |
| Identity | Profile table key and `app_id` are different fields. Preserve legacy alias keys. New Steam profiles use an explicit AppID; do not guess associations or renumber ambiguous entries |
| Paths/arguments | Chinese, spaces, quotes, backslashes, argument arrays, and relative paths. Resolve target/working_dir against game_dir; do not turn an argument array into a new command-line format |
| Write safety | Same-directory temporary files, flushing, backup, and atomic replacement; preserve old files on failure. Prevent cooperating app writers and report external changes after reading, without claiming all external editors can be locked |
| Real consumption | C# TOML is checked for complete semantics by the existing Rust parser, then drives a controlled Runner to verify argv/cwd/waiting. Editing one field of a historical Rust fixture in C# must preserve unedited meaning |

Choose the TOML library using this roundtrip experiment, not by first pinning an unverified package. Cover omitted values, all existing wait modes, alias keys, unknown fields/versions, interrupted writes, and competing writers. Comparing a few text files or showing that both sides parse is insufficient.

<a id="5-runner-与-steam-验收"></a>

## 5. Runner and Steam acceptance

[Current Runner](../crates/runner/src/main.rs) launches the profile's `target` and `args`. It receives/logs `steam_command`, without executing or automatically appending it. Keeping `%command%` is a compatibility contract, **not implemented original-command forwarding**. Migration must not also launch the original executable, automatically fall back to the official game, or change argument semantics.

New Windows profiles default to `job`. Real tests must cover launcher-first exit, later child exit, launch failure, Chinese/spaced paths, argv/cwd, Runner error exit, and logs. `root` waits only for the direct child. `process_name` is an explicit compatibility choice, not proof that a same-name process belongs to the game.

The local Episode 1 CHS launcher-first scenario passed: after the launcher exited at 14:15:55, the actual game and Runner continued for about 2 minutes 21 seconds until ordinary exit at 14:18:15; Steam playtime changed from 36 to 38 minutes. UI confirmed `job`, independent process observations had no sampling or metadata failures, and no processes remained. This does not directly establish Job membership or guarantee arbitrary launchers. The current [Windows implementation](../crates/runner/src/platform/windows.rs) returns the launcher's status after Job completion; CHS/Runner exit 0 in this log is not the actual game's exit 0.

Job Objects do not cover arbitrary escape behavior. Child membership depends on creation, breakaway, and parent-job conditions. General completion-port notifications cannot be treated as universally guaranteed delivery. Query and verify actual process state for exceptional cases rather than declaring correctness from API use alone. [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)

Routine automation uses isolated Steam/user directories and controlled processes. Release acceptance separately records real Windows Steam launches with Manager closed, Steam showing running during play and ending afterward, client playtime updates, and game/launcher/system versions. Agent operation on a real library requires explicit user authorization; this session's user authorized real galgame tests on condition that game files remain undamaged. Record old Launch Options and check files before testing, restore options and recheck afterward, and do not resolve ambiguous save/cloud conflicts. Without real evidence, report only the lifecycle behavior established by fixtures.

<a id="6-安全一键应用与恢复"></a>

## 6. Safe one-click apply and restore

The first Windows preview may use manually copied Launch Options; **one-click apply/restore follows next, before cross-platform expansion**. Establish reliable preview behavior before making it the formal release's default flow.

Do not treat Steam's private local files as a stable public write API. Recheck actual structures before implementation and verify parsing/unrelated-data preservation using redacted fixtures. The flow must:

- Identify the game and Steam user. Let the player choose among multiple users rather than writing every account.
- Detect running Steam and ask the player to exit it; check again before writing without automatically terminating Steam.
- Preview old/new values; back up options, relevant files, and recovery identifiers; check for changes immediately before writing.
- Edit only the target value, write atomically, read back, and record completed/interrupted state. Leave the original untouched on parse, backup, or conflict failure.
- Automatically restore only when the current value still matches this tool's written value. Preserve and explain later external changes. Never overwrite later changes to other games using a whole old backup.

The manual-copy stage must not claim automatic old-value backup or one-click restore. Existing launch parameters may matter to the game; do not silently discard them or append them to the new profile. Preview and migration guidance should let the player handle them explicitly.

<a id="7-安装更新卸载"></a>

## 7. Installation, updates, and uninstall

The first target is an **unpackaged self-contained directory + per-user installer**, bundling both .NET and Windows App SDK. Ordinary players should not install development tools or runtimes. Runner remains an independent Rust EXE. Portable delivery can later reuse the directory layout; no single-file EXE is promised. [Official self-contained deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

Install app files under `%LOCALAPPDATA%\Programs\SteamWrapper\`; verify bundled Runner before installing it to stable `bin`. Ensure installation succeeds during first configuration, while keeping ordinary UI access usable on installation failure. If Runner is busy, preserve the old file, configuration, and valid options, allowing a retry after play. Updates must not let an old Manager arbitrarily downgrade installed Runner. Define release metadata and compatibility handling; a different hash alone is not proof that an upgrade is valid.

Manager uninstall preserves profiles, logs, backups, and stable Runner by default so remaining Launch Options still work. Fully removing Runner first requires handling managed Steam options. If manually pasted or unenumerable references cannot be confirmed removed, retain Runner and provide cleanup guidance. Preserving configuration does not make deleting Runner safe.

Every candidate installer needs clean Windows 11 x64 VM tests for installation, configuration, launch after closing Manager, in-place update, and uninstall. Record package size, cold startup, and idle memory before optimizing. Assess MSIX, automatic updates, ARM64, and Windows 10 separately.

<a id="8-实施顺序与停止条件"></a>

## 8. Implementation order and stop conditions

| Stage | Completion condition |
| --- | --- |
| A. Toolchain/contracts | Pin .NET / Windows App SDK / Windows SDK / Rust MSVC; runnable Windows Runner baseline; passing C#↔Rust fidelity and controlled-process checks; viable lossless writes |
| B. WinUI configuration slice | Select fixture games/targets in a native window, preserve configuration, install stable Runner, and copy exact options; recover from cancellation/missing directories/unwritable or busy files; usable keyboard/Chinese input/scaling |
| C. Usable Windows preview | Real Windows/Steam launch records; clean-VM self-contained installation, updates, Manager relocation, and uninstall preservation; documentation of manual restore and known compatibility |
| D. Safe apply/stabilization | Pass multiple-user, Steam-running, backup, conflict, interruption, and single-game restore checks; expand real launcher testing; then consider default one-click apply |
| E. Cleanup/later work | Switch default Manager and replace CI only after C passes, then retire the Dioxus chain by dependency; consider cross-platform/new scope after D stabilizes |

The first implementation task focuses on a complete A→B configuration/controlled-launch slice, adding Windows build/contract CI incrementally while preserving existing workflows. Switch the default release chain after C. A polished UI is not migration-complete evidence when tooling is missing, roundtrips lose data, or Runner lifecycle regressions remain. mise toolchain setup is underway; see [Windows development](windows-development.md) for the latest installation and validation record.
