<a id="steamwrapper-v2-架构设计"></a>

# SteamWrapper v2 architecture

English | [简体中文](architecture.zh-CN.md)

<a id="核心目标"></a>

## Core goal

Windows is the current priority for v2. The new [product and architecture design](windows-v2-design.md) uses a WinUI 3/C# Manager, its own C# configuration services, and an independent Rust Runner connected through the existing TOML/CLI contracts. `apps/manager-winui` implements the configuration preview; the Dioxus/Rust management chain remains the migration baseline. Existing Linux contracts are retained, while Linux / SteamOS / Proton expansion is deferred.

Players configure a game once in SteamWrapper Manager, then always click Play in Steam. Manager does not participate in daily launches.

```text
SteamWrapperManager: visible during configuration, WinUI preview / Dioxus baseline GUI
SteamWrapperRunner: unobtrusive during play, native headless Rust executable
```

<a id="运行流程"></a>

## Runtime flow

```text
Steam starts the game
↓
Steam Launch Options calls SteamWrapperRunner
↓
Runner reads profiles.toml
↓
Runner finds the profile by --appid
↓
Runner starts the actual exe / launcher
↓
Runner waits for the game to exit
↓
Runner exits; Steam status and playtime still require acceptance in the client
```

Manager's configuration flow (the cover fallback below is Dioxus-only; WinUI uses local covers or placeholders):

```text
The user opens SteamWrapper Manager
↓
Scan the local Steam Library and appmanifest_<appid>.acf
↓
Find cached covers; when absent, associate a public Steam CDN URL with the known AppID
↓
Choose the game and the actual exe / launcher
↓
Save the profile and generate Steam Launch Options (applying them to Steam is not implemented)
↓
Continue launching the game from Steam
```

<a id="launch-options-合约"></a>

## Launch Options contract

```text
"<stable-runner-path>" --appid "123456" -- %command%
```

- `--appid` identifies the profile consistently.
- The original Steam command remains after `--`.
- `%command%` is retained for future Steam / Proton wrapping.
- Launch Options must point to the stable Runner, never a temporary installation or extraction directory.

The v2 `profiles.toml` format, Runner CLI, and Launch Options above are compatibility boundaries. A GUI migration must not change them.

The current Runner receives and logs `steam_command`; it runs the profile's target/args without executing or automatically appending the original command. A UI migration must preserve this meaning.

<a id="分层"></a>

## Layers

WinUI preview:

```text
apps/manager-winui/SteamWrapper.Manager       # XAML, window state, native picker, clipboard
                 ↓ C# calls
apps/manager-winui/SteamWrapper.Application   # configuration, local Steam, Runner installation
                 ↓ profiles.toml / stable Runner files
crates/runner                               # started independently by Steam
```

`ProfileStore` uses Tomlyn syntax spans to change only edited fields, preserving other text and unknown data. New profiles explicitly default to job; a legacy omitted root default is not filled in as job. Saving uses a cooperative write lock, byte-version conflict checks, a flushed temporary file in the same directory, and atomic replacement with backup. Inline/dotted profiles are readable but cannot be modified. Non-cooperating editors can still race between the final check and replacement.

`SteamScanner` reads only local VDF and covers. `RunnerInstaller` uses a hash-bound version manifest, stable paths, and atomic replacement; it rejects overwrites when relative versions cannot be established. The UI does not control game processes. `tests/contracts` and test-only process fixtures verify C# editing and actual Rust consumption; they are not included in the Manager package.

`ProfileSteamInstallation` associates a read-only Steam installation path by AppID for display in Manager. It is not written to TOML, and discovery does not overwrite `game_dir`. The latter still means the actual runtime folder, which may be outside the Steam library; Runner target and working-directory resolution stay unchanged. See [separate translated-game directories](translated-games.md) for the purposes of both paths, migration, and achievement boundaries.

The retained Dioxus management chain below uses its own older save implementation:

```text
apps/manager-dioxus
  Dioxus Desktop, RSX, local CSS, player-facing UI
                ↓ direct Rust calls
crates/manager-core
  ManagerServices, stable paths, profiles, scanning, logs, Runner installation/repair
                ↓
crates/core
  Profile / TOML, Steam Library, cover cache, Launch Options, cross-platform rules

crates/runner
  independent CLI, target launch, platform waiting, runtime logs
```

### `crates/core`

In the existing Rust management chain, `core` provides Profile/TOML, Steam directory and appmanifest parsing, local-first cover discovery with AppID-based Steam CDN fallback URLs, and Launch Options. It must not depend on Dioxus, Tauri, React, WebView, or platform process-waiting APIs. The C# Manager implements configuration services against the same protocol, with cross-language roundtrips and actual Runner consumption constraining compatibility. It does not reuse the management chain through FFI.

### `crates/manager-core`

`manager-core` is the UI-framework-neutral Manager service layer, not an RPC layer. It composes `core` directly and provides:

- Stable data paths and directory creation for the current platform.
- Profile reading/saving and Launch Options generation.
- Local Steam game scanning and log listing.
- Runner hash checks, atomic installation, and repair.

Dioxus calls it directly; do not copy old Tauri command shapes or introduce artificial IPC.

The current save service reconstructs profiles and overwrites advanced fields; core saves through direct file writes. These are known migration risks, not configuration semantics endorsed by the new design. WinUI must preserve unedited fields, protect unknown data, write atomically, and handle conflicts. See the [configuration fidelity gate](windows-v2-design.md#4-配置保真是第一个门槛).

### `apps/manager-dioxus`

The Dioxus Desktop 0.7.10 configurator provides local game scanning, cover cards, manual additions, target selection, profile editing, Launch Options, configured games, logs, and settings. CSS is a local native resource. The brand SVG must remain consistent with `assets/brand/steamwrapper.svg`.

`Dioxus.toml` explicitly declares `resources/runner`. Build steps stage the platform's Runner; Manager copies the read-only bundled resource into the stable user-data location only on first startup or repair from Settings.

### `crates/runner`

Runner is always independent, native, and headless, with no dependency on Dioxus or GUI lifecycle. Manager installs and checks its distribution resources only. Launching, waiting, and platform process control must never move into the GUI.

<a id="profile-示例"></a>

## Profile example

```toml
version = 2

[profiles.123456]
name = "Example Game"
app_id = "123456"
platform = "windows"
game_dir = "D:/SteamLibrary/steamapps/common/Example Game"
target = "ExampleGame_CHS.exe"
working_dir = "."
args = []
wait_mode = "job"
```

<a id="界面语言设置"></a>

## Display language settings

Manager display language is separate from the Runner/TOML contract. Both Managers use `ui-settings.json` in the stable data root, beside `profiles.toml`. The `language` value is `en-US` or `zh-CN`; trimmed, case-insensitive `en` and `zh-Hans` aliases are accepted, and missing/unknown values default to English. Preserve unknown JSON fields when saving and refuse to overwrite an invalid existing file. A language change must preserve current form input and protocol values; user names, paths, commands, and log contents remain literal.

WinUI's sidebar selector refreshes application-owned text after a successful save; a failed save retains the previous language and reports the error. This UI preference does not change Runner arguments, wait modes, game paths, or the original Steam command.

<a id="等待模式"></a>

## Wait modes

| Mode | Purpose |
| --- | --- |
| `root` | Wait only for the directly launched target process |
| `job` | Windows default; a Job Object waits for launcher descendants that do not explicitly break away |
| `process_name` | After the launcher exits, wait for the specified process name appearing during this launch |
| `process_group` | Linux / SteamOS default; wait for descendants in the same POSIX process group |
| `none` | Exit immediately after launch |

New Manager profiles currently default to `job` on Windows and `process_group` on Linux. The Rust parser defaults to `root` when legacy TOML omits `wait_mode`; migration must not reinterpret this. `process_name` excludes same-name `(PID, start_time)` pairs that existed before launch, but a name cannot identify application ownership. It is an explicit compatibility option for complex launchers. Proton wrapping awaits a complete platform-specific strategy.

<a id="分发与稳定安装"></a>

## Distribution and stable installation

Windows:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager installation directory
%LOCALAPPDATA%\SteamWrapper\bin\           # stable Runner path
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # configuration
%LOCALAPPDATA%\SteamWrapper\ui-settings.json # display language
%LOCALAPPDATA%\SteamWrapper\logs\          # logs
%LOCALAPPDATA%\SteamWrapper\backups\       # backups
```

Linux / SteamOS:

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  ui-settings.json
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

When `XDG_DATA_HOME` is unset, use `~/.local/share/SteamWrapper/`. After resource verification, Runner is written atomically to its stable path. Updates touch Runner only, preserving profiles, logs, backups, and cache.

<a id="封面与安全边界"></a>

## Covers and safety boundaries

Manager prefers local Steam caches:

```text
<Steam installation>/appcache/librarycache/
<Steam installation>/userdata/<steamid>/config/grid/
```

When a local cover is missing, `core` builds a public Steam CDN `library_600x900.jpg` URL from an AppID already read from a local manifest. Dioxus passes only this URL to its image control. The request includes no Steam username, library list, profile, or API key. It adds neither a third-party cover service nor new image files in user data. Offline operation, rate limits, missing resources, and image-load errors produce a friendly cover-unavailable placeholder without blocking scanning or configuration.

SteamWrapper does not inject DLLs, patch Steam/games, bypass DRM, remain running as a background service, or upload user data.

<a id="manager-技术边界"></a>

## Manager technology boundaries

The old Tauri/React Manager and its E2E were removed. `apps/manager-winui` now provides the Windows configuration preview, while `apps/manager-dioxus` remains the migration baseline. WinUI implements Windows configuration services in C# without a C ABI or background helper. Runner remains an independent Rust executable. The [Windows design](windows-v2-design.md) defines WinUI's local-cover policy, retirement conditions for the old management chain, and acceptance order.

Windows NSIS, Linux AppImage, and physical SteamOS devices still need validation in their respective CI/platform environments. Passing local Linux checks is not Windows or physical Steam Deck evidence.
