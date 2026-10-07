---
title: "SteamWrapper v2 architecture"
description: "WinUI Manager, C# configuration and Steam setting services, independent Rust Runner, and stable contracts."
---

<a id="steamwrapper-v2-architecture"></a>
<a id="steamwrapper-v2-架构设计"></a>
<a id="核心目标"></a>

## Core goal

**WinUI 3 is the only Manager implementation.** The Windows Manager in `apps/manager-winui` uses C#/XAML and C# application services. Steam launches the independent Rust Runner through the existing TOML/CLI contracts. There is no Rust FFI, management helper, or background service. See the [Windows design](/SteamWrapper/project/design/windows-v2/).

Configure a game once, then click Play in Steam with Manager closed. The public [v0.2.8 stable release](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8) provides Setup and a portable ZIP. The current `v0.2.9` candidate adds explicit application of Launch Options to one local Steam account and restoration of its recorded original setting; actual Steam-client acceptance and publication remain separate gates. Linux retains Rust Runner compatibility and process CI; there is no Linux GUI, and new SteamOS/Proton work is deferred.

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
→ choose/confirm a local Steam account and review current/proposed Launch Options
→ after Steam exits normally, back up, apply and read back the selected setting
→ retain manual copying as an alternative
```

In the candidate, **Save and apply to Steam** saves configuration and prepares Runner before requesting confirmation of one account, AppID, and old/new setting. Multiple accounts require an explicit choice; no readable account leaves the manual-copy alternative. Steam must exit normally, and a retry inspects the setting again. A verified disk write is reported separately from configuration saving and does not prove that the Steam client retained the value. Manager can explicitly open Steam without launching a game.

**Restore previous Launch Options** uses the original setting recorded by a successful application, including whether the key was absent or empty. It restores only while the selected account/AppID still holds the recorded applied command, preserving later changes to other games. A manually pasted recognized command without a recovery record has an unknown original; the separately labeled **Restore normal Steam launch** action clears only that exact command and does not reconstruct earlier arguments. Revert retains its unsaved-edit role. Removing one editable profile requires a complete account/reference scan and no blocking recovery records, while preserving unrelated TOML, backups and games. See the [implementation plan](/SteamWrapper/project/design/steam-launch-options/) and scoped evidence in [Testing](/SteamWrapper/development/testing/).

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

WinUI Manager / uninstall Host
                 ↓ C# calls
apps/deployment-windows/SteamWrapper.Deployment # guarded Steam settings and recovery; deployment
```

`ProfileStore` uses Tomlyn syntax spans to edit only changed fields, preserving other text and unknown data. New Windows profiles explicitly use `job`; omitted legacy `wait_mode` remains `root`. Saves and deletion of one supported explicit Windows profile table use a cooperative lock, byte-version conflict checks, a flushed same-directory temporary file, atomic replacement, and backup. Deletion preserves all unrelated TOML and rechecks Steam references under the profile lock before replacement. Inline/dotted or otherwise unsupported layouts remain read-only. Non-cooperating editors can still race between the final check and replacement.

`SteamScanner` reads local metadata/covers. `CoverService` owns optional image requests and its bounded cache, while WinUI supplies image decoding and updates visible rows asynchronously. `RunnerInstaller` checks hash-bound version metadata and actual shared file locations before reporting ready; it uses stable paths and atomic replacement, preserving newer compatible versions and rejecting unknown replacements. GUI code never launches or waits for games. Cross-language tests and controlled process fixtures verify actual Rust consumption and are excluded from published output.

Steam titles are read from the local `appcache/appinfo.vdf` through a bounded, read-only parser and displayed in the current supported UI language. Missing, unreadable or unsupported metadata falls back to local base/manifest names without network requests. A saved name matching a known Steam default may be localized for display; custom names and saved TOML remain unchanged. Language changes retain the selected profile and unsaved editor input, and picker search accepts the local title variants and AppID.

`ProfileSteamInstallation` associates a read-only Steam path by AppID for display. It is not serialized and never overwrites `game_dir`, the actual runtime folder, which may be outside Steam. See [translated-game directories](/SteamWrapper/guides/translated-games/).

`SteamAccountScanner` discovers at most 128 canonical positive numeric `userdata` accounts with existing readable `config/localconfig.vdf` files. It reads bounded, optional `config/loginusers.vdf` metadata only for `PersonaName`, validating the public individual SteamID64/account-directory mapping and falling back to numeric account labels. It does not choose a user from recent-login flags, expose login fields, create settings files or query an account service. Reparse paths and scans outside an active fixture scope are rejected; an oversized inventory returns no partial choice. `SteamIntegrationReadiness` binds the saved profile revision and verified shared Runner bytes to one unambiguous AppID/local installation before offering automatic application.

`SteamLaunchIntegration` in Deployment owns selected-setting inspection, byte-preserving VDF editing, application and recorded-original restoration. It changes only `UserLocalConfigStore/Software/Valve/Steam/apps/<appid>/LaunchOptions`, inserting a missing game or key only inside an existing supported `apps` hierarchy. Comments, encoding/BOM, whitespace, unknown fields and unrelated bytes remain intact. Ambiguous structure, unsafe paths, read-only/locked targets, changed previews and unsupported recovery data stop writes.

Recovery records and verified snapshots stay in `backups/steam-launch-options/<operation-id>/`. The record retains account/AppID/data-root identity, original key/value/token, saved profile/Runner hashes and operation phase. Reapplication preserves the first active original; an identical manually pasted command does not gain invented provenance. Pending work is inspected without Steam mutation, and further changes in the same account file stop until unresolved recovery is addressed. Explicit recovery uses exact before/after snapshots and actual replaced-file evidence; inconsistent bytes remain a conflict for review.

Application and restoration hold `profiles.toml.lock`; application also holds the Runner installation lock in data-then-Runner order and rechecks readiness immediately before replacement. Confirmation and normal-exit waiting hold no mutation lock. Opened handles must resolve to the expected physical paths, including under development-host AppData redirection. Flushed temporary and adjacent replacement-backup files share Steam's volume; verified archival copies can live in LocalAppData on another volume. The service verifies both actual replaced bytes and the written target before committing the record, and retains recovery copies after uncertain replacement. These checks narrow concurrent rename/Steam-start races; ordinary `File.Replace` is not conditional compare-and-swap or a guarantee against power loss.

### Manager deployment

`apps/deployment-windows` contains a GUI-independent C# deployment library and NativeAOT `SteamWrapper.exe` launcher/helper. Manager acquires a shared installation lease before initialization and keeps it until process exit; its health acknowledgment binds the current transaction. Inno and explicit repair/rollback/uninstall use the same exclusive lease and manifest/journal engine. First installation may choose a validated empty directory on a fixed local drive; updates and repairs use the registered root. The stable data directory stays separate.

The helper launches Manager or a confirmed SteamWrapper installer and never launches games. Manager and the explicit uninstall restoration choice share Deployment's recorded-original restoration rules, with legacy exact-command clearing retained for commands without known originals. Uninstall holds its installation lease and a continuous data lock across restoration, final reference checks and selected profile/Runner cleanup; it rechecks references before deleting each protected file. Steam must be stopped, blocking/unknown recovery material is retained, and Runner bytes must match supported metadata. Default uninstall preserves data, and every path preserves games, saves, Steam restoration backups, update trust state and unknown files. See [installer ownership and recovery](/SteamWrapper/guides/installer-preview/) and the scoped acceptance in [Testing](/SteamWrapper/development/testing/).

`OfficialUpdateService` verifies project-signed release metadata with an embedded public key, checks freshness and rollback state, then downloads a bounded, digest-verified installer into SteamWrapper's update cache. WinUI supplies manual checking, opt-in startup checks, progress/cancellation and installation confirmation; a portable copy links to release downloads. The existing NativeAOT helper waits for Manager to exit normally, rechecks the downloaded file and opens the same Inno installer, then reopens Manager after success. It does not terminate games or replace the stable Runner.

The public `v0.2.8` release has three anonymously downloaded and verified assets on both GitHub and CNB. Both sources' stable and preview feeds passed real project-key signature, freshness and exact installer-binding checks, with identical bytes between sources for each channel. CNB release metadata was read through the existing authenticated CLI; asset and feed requests used no credentials. GitHub is the primary source and verified CNB is available as a fallback; automatic checks are off by default. Project-owned PE files and Setup remain Authenticode-unsigned; Windows code signing is optional. These publication checks did not execute the public `v0.2.8` installer; the actual public-network installation flow tested earlier was CNB `0.2.5` → `0.2.6`. See [Testing](/SteamWrapper/development/testing/) for each payload and result.

Released `0.2.8` packaging uses internal schema 3: it still validates all seven package files, but publishes only Setup, portable ZIP and `SHA256SUMS` as version assets. Historical seven-asset releases remain immutable. The independently renewed, project-signed update feed is still necessary and keeps client payload schema 2, existing trust keys and exact installer binding. Release titles contain only the tag; the verified GitHub body is English and CNB body is Simplified Chinese.

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

WinUI uses `ui-settings.json` beside `profiles.toml`. An absent `language` key follows the supported system UI culture; `zh-CN`, `zh-SG` and explicitly `zh-Hans` cultures select Simplified Chinese, otherwise English. Explicit saved choices take priority; invalid explicit values and unreadable settings fall back to English. Canonical values are `en-US` and `zh-CN`; trimmed, case-insensitive `en`, `zh-SG` and `zh-Hans` aliases are accepted. Reads and cover-only writes do not persist a detected language. Saves preserve unknown JSON fields and refuse to overwrite invalid settings. Service diagnostics remain invariant English.

`steamCdnCovers` is a separate boolean in the same file, defaulting to `false` when missing. Preference writes preserve each other's value and unknown fields; a successful persisted change enables downloads. A failed write leaves the prior preference in effect.

The sidebar selector refreshes application-owned text after successful persistence; failure retains the previous language and reports an error. Unsaved input, user names, paths, arguments, protocol identifiers, and logs remain unchanged. Language does not alter Runner/TOML behavior.

<a id="等待模式"></a>

## Wait modes

| Mode | Purpose |
| --- | --- |
| `root` | Wait for the directly launched target |
| `job` | New Windows profile default; wait for Job members that do not break away |
| `process_name` | Observe new matching processes while the launcher runs; after launcher exit, wait until those matching processes finish |
| `process_group` | Retained Linux mode for descendants in the same POSIX process group |
| `none` | Exit immediately after launch |

Missing legacy `wait_mode` always parses as `root`. No Linux Manager currently creates profiles. `process_name` excludes preexisting same-name `(PID, start_time)` pairs, but a name cannot establish ownership. Windows `job` returns launcher status after waiting, not necessarily the game's exit code. Use platform process tests and scoped live evidence for lifecycle claims.

<a id="分发与稳定安装"></a>

## Distribution and stable installation

Windows uses a complete self-contained layout, a per-user Inno installer and a portable ZIP. Version tags publish releases; manual workflow runs produce development previews. Daily CI tests and compiles without packaging the application. Relevant-path filters skip unrelated checks, dependency caches avoid repeated setup and one captured Runner suite supplies the required process evidence; full version-tag gates remain required. Cold/warm CI observations are recorded in [Testing](/SteamWrapper/development/testing/#public-028-and-ci-observations-2026-10-07), without a speed guarantee. The supported release scope is Windows 11 24H2 x64, using the same Windows account as Steam with ordinary permissions. Open Manager from ordinary File Explorer or its installed shortcut. The `v0.2.9` candidate's account-specific apply/restore implementation does not establish Steam Properties persistence, live game behavior, exact-tag delivery or verified public downloads; each needs its own evidence. See [installation](/SteamWrapper/guides/installation/) for current downloads and [distribution](/SteamWrapper/development/distribution/) for the exact triggers.

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

`%LOCALAPPDATA%\Programs\SteamWrapper` is the default Manager installation location; first installation may choose another validated empty directory on a fixed local drive. Runner installation preserves profiles and other user data.

Existing Linux Runner uses `$XDG_DATA_HOME/SteamWrapper/`, falling back to `~/.local/share/SteamWrapper/`, and `bin/steamwrapper-runner`. Preserve existing data there; no Linux GUI or automatic installer is provided.

<a id="封面与安全边界"></a>

## Covers and safety boundaries

WinUI prefers per-user custom Steam `config/grid/` images, then local `appcache/librarycache/` art, including hashed filenames and nested hash directories. It never writes to either directory. Friendly placeholders cover missing or unreadable images without blocking editing, saving or Runner.

Official Steam CDN fallback is an explicit preference, disabled by default and limited to locally discovered AppIDs. Requests contain the individual AppID and normal HTTPS connection information; there are no account lookups, library uploads, cookies, authentication or third-party metadata services. Only `shared.steamstatic.com` and `shared.fastly.steamstatic.com` over HTTPS are allowed, with the same checks before each manually followed redirect. The fixed portrait endpoint is best effort: newer assets may need a different path, and a 404 retains the placeholder rather than querying another service. Valve documents the [library capsule and its half-size variant](https://partner.steamgames.com/doc/store/assets/libraryassets?l=english); the filename does not guarantee a 600×900 decoded image.

`CoverService` limits downloads to two concurrent operations, ten seconds per operation including response reads and redirects, at most two redirects, and 4 MiB encoded image data. Image validation also has a two-operation limit. WinUI decodes static JPEG, PNG or WebP using available Windows codecs and rejects malformed content or images above 4096 pixels on either edge or eight million pixels in total. A failed request has a five-minute cooldown instead of automatic retries. Disabling fallback cancels the active dialog's in-flight requests and prevents new ones there.

Only downloaded covers are managed under `%LOCALAPPDATA%\SteamWrapper\cache\covers\`: a 32 MiB/64-file quota, thirty-day expiry, eviction and a clear action. Cache changes use an exclusive cross-process file lease; an in-use cache leaves a placeholder or a recoverable clear error. Cleanup does not touch custom art, Steam cache files, games, profiles, Runner or other SteamWrapper data. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings) and scoped [native acceptance](/SteamWrapper/development/testing/).

Steam setting writes are limited to the confirmed Launch Options operations above. SteamWrapper does not inject DLLs, patch Steam/game binaries, bypass DRM, or upload user data. Unresolved save/cloud conflicts stop live acceptance.

<a id="manager-技术边界"></a>

## Manager technology boundaries

WinUI/C# Application and Rust Runner are the sole current product path. Dioxus and Tauri/React are historical implementations. Node/pnpm serve development assets and static documentation, not desktop runtime.

Acceptance records retain their exact package and environment scope. Ordinary-permission evidence in the existing Steam user's SID does not establish a fresh primary standard-account sign-in, separate-user desktop, two-user session or multi-monitor acceptance. Linux Runner CI does not establish a Linux GUI, Steam Deck support, or Proton integration. See [Testing](/SteamWrapper/development/testing/) and the [roadmap](/SteamWrapper/project/roadmap/).
