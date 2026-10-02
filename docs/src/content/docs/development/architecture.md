---
title: "SteamWrapper v2 architecture"
description: "WinUI Manager, C# application services, independent Rust Runner, and stable contracts."
---

<a id="steamwrapper-v2-architecture"></a>
<a id="steamwrapper-v2-架构设计"></a>
<a id="核心目标"></a>

## Core goal

**WinUI 3 is the only Manager implementation.** The Windows preview in `apps/manager-winui` uses C#/XAML and C# application services. Steam launches the independent Rust Runner through the existing TOML/CLI contracts. There is no Rust FFI, management helper, or background service. See the [Windows design](/SteamWrapper/project/design/windows-v2/).

Configure a game once, then click Play in Steam with Manager closed. Removing the old UI does not complete installation, update, or stable-release acceptance. Linux retains Rust Runner compatibility and process CI; there is no Linux GUI, and new SteamOS/Proton work is deferred.

<a id="运行流程"></a>

## Runtime flow

```text
Steam Play
→ stable Runner --appid <appid> -- %command%
→ read profiles.toml
→ launch the configured target and arguments
→ wait according to the profile
→ exit
```

Steam status, playtime, achievements, and cloud behavior need their own scoped acceptance.

```text
Open WinUI Manager
→ scan local Steam manifests and covers
→ show custom/local art, optional cached/CDN fallback, or a friendly placeholder
→ select the actual executable/launcher and preserve advanced settings
→ save the profile and install/check stable Runner
→ generate/copy Launch Options for manual application
```

Automatic Steam Launch Options application and restoration are not implemented.

<a id="launch-options-合约"></a>

## Launch Options contract

```text
"<stable-runner-path>" --appid "123456" -- %command%
```

`--appid` selects the profile. The original Steam command remains after `--`; options reference stable Runner, never Manager or temporary/versioned package paths. Runner receives and logs `steam_command`, but executes the profile's target/args without executing or appending that original command. Preserving `%command%` is a compatibility boundary, not completed Proton wrapping.

<a id="分层"></a>

## Layers

```text
apps/manager-winui/SteamWrapper.Manager       # C#/XAML, UI state, pickers, clipboard
                 ↓ C# calls
apps/manager-winui/SteamWrapper.Application   # profiles, local Steam, logs, Runner installation
                 ↓ profiles.toml / stable Runner files
crates/runner                               # Steam-started CLI and process lifecycle
                 ↓ Rust calls
crates/core                                 # shared configuration/path contracts
```

`ProfileStore` uses Tomlyn syntax spans to edit only changed fields, preserving other text and unknown data. New Windows profiles explicitly use `job`; omitted legacy `wait_mode` remains `root`. Saves use a cooperative lock, byte-version conflict checks, a flushed same-directory temporary file, atomic replacement, and backup. Inline/dotted profiles are read-only. Non-cooperating editors can still race between the final check and replacement.

`SteamScanner` reads local metadata/covers. `CoverService` owns optional image requests and its bounded cache, while WinUI supplies image decoding and updates visible rows asynchronously. `RunnerInstaller` checks hash-bound version metadata and actual shared file locations before reporting ready; it uses stable paths and atomic replacement, preserving newer compatible versions and rejecting unknown replacements. GUI code never launches or waits for games. Cross-language tests and controlled process fixtures verify actual Rust consumption and are excluded from published output.

`ProfileSteamInstallation` associates a read-only Steam path by AppID for display. It is not serialized and never overwrites `game_dir`, the actual runtime folder, which may be outside Steam. See [translated-game directories](/SteamWrapper/guides/translated-games/).

### `crates/core`

Core is a GUI-independent Rust library. Runner uses its Profile/TOML and path semantics. Existing Steam metadata, cover URL, and Launch Options utilities do not provide WinUI services: C# implements the file contract directly. Core contains no platform process-waiting API.

### `crates/runner`

Runner owns CLI parsing, target launch, platform waiting, and runtime logs, without GUI, WebView, or .NET dependencies. Manager checks and installs its files without sharing its process lifetime.

<a id="cratesmanager-core"></a>
<a id="appsmanager-dioxus"></a>

### Archived management chain

Dioxus Manager, `crates/manager-core`, its E2E, and the old GUI release chain are removed from current development. Their [UI source](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus) and [service source](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core) at ca6a09e are historical references. The [2026-09-07 comparison](/SteamWrapper/project/decisions/manager-comparison/) preserves measurements and limitations, not a second supported Manager.

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

WinUI uses `ui-settings.json` beside `profiles.toml`. `language` is `en-US` or `zh-CN`; trimmed, case-insensitive `en` and `zh-Hans` aliases are accepted, with missing/unknown values defaulting to English. Saves preserve unknown JSON fields and refuse to overwrite invalid settings.

`steamCdnCovers` is a separate boolean in the same file, defaulting to `false` when missing. Preference writes preserve each other's value and unknown fields; a successful persisted change enables downloads. A failed write leaves the prior preference in effect.

The sidebar selector refreshes application-owned text after successful persistence; failure retains the previous language and reports an error. Unsaved input, user names, paths, arguments, protocol identifiers, and logs remain unchanged. Language does not alter Runner/TOML behavior.

<a id="等待模式"></a>

## Wait modes

| Mode | Purpose |
| --- | --- |
| `root` | Wait for the directly launched target |
| `job` | New Windows profile default; wait for Job members that do not break away |
| `process_name` | After launcher exit, wait for the specified name observed during this launch |
| `process_group` | Retained Linux mode for descendants in the same POSIX process group |
| `none` | Exit immediately after launch |

Missing legacy `wait_mode` always parses as `root`. No Linux Manager currently creates profiles. `process_name` excludes preexisting same-name `(PID, start_time)` pairs, but a name cannot establish ownership. Windows `job` returns launcher status after waiting, not necessarily the game's exit code. Use platform process tests and scoped live evidence for lifecycle claims.

<a id="分发与稳定安装"></a>

## Distribution and stable installation

Windows uses a complete self-contained preview layout through local builds and the version-tag/manual release workflow. Daily CI tests and compiles without packaging the application. Extract the complete package and open Manager from ordinary File Explorer. A per-user installer, application updater, and automatic Steam writes remain unimplemented; tagged packages are unsigned prereleases pending delivery acceptance. See [distribution](/SteamWrapper/development/distribution/) for the exact triggers.

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

`%LOCALAPPDATA%\Programs\SteamWrapper` is a proposed future Manager installation location. Runner installation preserves profiles and other user data.

Existing Linux Runner uses `$XDG_DATA_HOME/SteamWrapper/`, falling back to `~/.local/share/SteamWrapper/`, and `bin/steamwrapper-runner`. Preserve existing data there; no Linux GUI or automatic installer is provided.

<a id="封面与安全边界"></a>

## Covers and safety boundaries

WinUI prefers per-user custom Steam `config/grid/` images, then local `appcache/librarycache/` art, including hashed filenames and nested hash directories. It never writes to either directory. Friendly placeholders cover missing or unreadable images without blocking editing, saving or Runner.

Official Steam CDN fallback is an explicit preference, disabled by default and limited to locally discovered AppIDs. Requests contain the individual AppID and normal HTTPS connection information; there are no account lookups, library uploads, cookies, authentication or third-party metadata services. Only `shared.steamstatic.com` and `shared.fastly.steamstatic.com` over HTTPS are allowed, with the same checks before each manually followed redirect. The fixed portrait endpoint is best effort: newer assets may need a different path, and a 404 retains the placeholder rather than querying another service. Valve documents the [library capsule and its half-size variant](https://partner.steamgames.com/doc/store/assets/libraryassets?l=english); the filename does not guarantee a 600×900 decoded image.

`CoverService` limits downloads to two concurrent operations, ten seconds per operation including response reads and redirects, at most two redirects, and 4 MiB encoded image data. Image validation also has a two-operation limit. WinUI decodes static JPEG, PNG or WebP using available Windows codecs and rejects malformed content or images above 4096 pixels on either edge or eight million pixels in total. A failed request has a five-minute cooldown instead of automatic retries. Disabling fallback cancels the active dialog's in-flight requests and prevents new ones there.

Only downloaded covers are managed under `%LOCALAPPDATA%\SteamWrapper\cache\covers\`: a 32 MiB/64-file quota, thirty-day expiry, eviction and a clear action. Cache changes use an exclusive cross-process file lease; an in-use cache leaves a placeholder or a recoverable clear error. Cleanup does not touch custom art, Steam cache files, games, profiles, Runner or other SteamWrapper data. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings) and remaining [P0 native acceptance](/SteamWrapper/project/roadmap/).

SteamWrapper does not inject DLLs, patch Steam/game files, bypass DRM, or upload user data. Unresolved save/cloud conflicts stop live acceptance.

<a id="manager-技术边界"></a>

## Manager technology boundaries

WinUI/C# Application and Rust Runner are the sole current product path. Dioxus and Tauri/React are historical implementations. Node/pnpm serve development assets and static documentation, not desktop runtime.

Windows preview evidence does not establish installer/update/uninstall or clean-system acceptance. Linux Runner CI does not establish a Linux GUI, Steam Deck support, or Proton integration. See [distribution](/SteamWrapper/development/distribution/) and the [roadmap](/SteamWrapper/project/roadmap/).
