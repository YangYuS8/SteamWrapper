---
title: "v2 distribution and installation"
description: "Package contents, stable Runner installation, and remaining delivery requirements."
---

<a id="v2-distribution-and-installation"></a>

<a id="v2-分发与安装方案"></a>



<a id="原则"></a>

## Principles

SteamWrapper v2 currently prioritizes Windows installation, updates, and uninstall. The WinUI preview supports local self-contained directory publishing; a per-user installer is not yet implemented. The Dioxus bundle commands below continue to describe the retained delivery chain. See the [deployment assessment](/SteamWrapper/project/decisions/winui3/#部署与稳定路径) and [Windows design](/SteamWrapper/project/design/windows-v2/#7-安装更新卸载). Later Linux / SteamOS delivery is deferred. Stable Runner paths and existing profiles must be preserved.

- Default installation should not require administrator rights or understanding Runner/TOML.
- Updates replace Manager program files while preserving stable user data.
- Uninstall removes the application by default; deleting user data must be an explicit choice.
- GitHub Release and CNB Release are intended delivery channels that still require acceptance.
- Back up before changing Steam Launch Options. Future one-click apply must not blindly write configuration while Steam is running.

The target WinUI installer bundles both .NET and Windows App SDK, installing the independent Rust Runner at its stable path without a Rust FFI bridge. The actual installer must be tested on Windows 11 x64 without a development environment. Project properties alone do not establish that players need no runtime preparation.

Default uninstall removes Manager only, retaining stable Runner, configuration, logs, and backups that Steam Launch Options may still reference. Remove references before fully removing Runner; manually pasted or unenumerable options cannot be assumed restored. An older Manager must not downgrade stable Runner merely because its hash differs. Version compatibility and handling of busy files must be explicit. These are new-installer acceptance requirements, not evidence that the current Dioxus implementation passed them.

<a id="winui-本地预览目录"></a>

## Local WinUI preview directory

`mise run winui:publish` generates the Windows 11 24H2 x64 preview in `target/winui/publish`. The complete directory includes Manager, .NET, Windows App SDK, brand resources, and `Runner/`. There is no single-EXE or installer promise. `winui:sandbox` launches the preview using disposable isolated directories; ordinarily running the EXE uses real `%LOCALAPPDATA%`.

The build generates `runner-manifest.json` (schemaVersion 1 / contractVersion 2) from Runner's Cargo version and actual binary SHA-256. The C# installer accepts only hash-matching resources and installs atomically to stable `bin/`. It preserves newer compatible versions and rejects unknown versions or same-version/different-hash replacements. Hash-bound `runner-releases/` metadata supports recognition after an interrupted binary/sidecar commit. Hashes check consistency; they are not publisher signatures and do not establish package authentication.

An existing Runner with identical bundled bytes can be recognized and adopted. An unknown, different Runner prompts the user to use a matching package rather than being deleted or forcibly replaced. A busy-file update failure preserves the old binary and user configuration. Manager can still edit/save configuration if Runner resources are missing, but does not present Launch Options as ready.

Switching the default release chain, installer signing/update/uninstall, a clean Windows VM, and the applicable real Steam acceptance gates belong to stage C. Recorded local game passes are listed separately in [live validation](/SteamWrapper/project/validation/steam/).

## Dioxus Desktop bundle

Dioxus `0.7.10` packages Manager using `apps/manager-dioxus/Dioxus.toml`:

- Windows: an NSIS CurrentUser installer; `[bundle.windows]` configures icons and WebView installation mode, with installer settings under `[bundle.windows.nsis]`.
- Linux: an AppImage preview containing WebKitGTK runtime dependencies and Dioxus Manager resources.
- Runner: `[bundle].resources` explicitly lists both platform names. A build machine fills only its own nonempty target. The other platform's empty placeholder satisfies the Dioxus manifest and must not become that platform's published Runner resource.

Dioxus `asset_dir` handles Manager CSS/SVG and other UI assets only. Runner must be included explicitly in `[bundle].resources`. The current bundler does not support directories as resource entries, so two file paths are listed.

Canonical brand assets are `assets/brand/steamwrapper.svg`, `.png`, and `.ico`, with matching Dioxus copies. After editing the original SVG, use `mise run brand:generate`; verify the checked-in outputs with `mise run brand:check`. pnpm and `@resvg/resvg-js` are development asset tooling, not application runtime dependencies. Preserve the asset checks during packaging.

On 2026-09-08, the final local Dioxus NSIS build produced `SteamWrapperManager_0.2.0_x64-setup.exe` at **5,167,920 bytes**, with English and Simplified Chinese (`English`, `SimpChinese`) installer resources. The installer and the actual packaged Manager PE each contained all 10 canonical icon sizes (16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixels), with every frame's SHA-256 matching the canonical ICO. Inspection confirmed the WebView2 download bootstrapper, no offline runtime installer, and `silent = true` in the WebView installation configuration. Bundled Runner was **1,180,160 bytes**, with its SHA-256 matching the release Runner. The local records are `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` and `bundle.log` in the same ignored directory. This was a build and package-content check: the installer was not run, and installation, runtime download, updates/uninstall, clean-system behavior, and WinUI delivery were not validated by it.

## Windows

The intended primary artifact for ordinary Windows players is:

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

Secondary artifact:

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

The NSIS installer uses Dioxus bundle's `CurrentUser` mode. Suggested installation path:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

Run a newer setup.exe to replace Manager when updating; stable user data is not removed with the installation directory. Portable ZIP is for advanced users. Even if Manager is moved or deleted, Steam Launch Options must continue to reference stable Runner only.

<a id="linux--steamos后续交付暂缓"></a>

## Linux / SteamOS (later delivery deferred)

Preview artifacts:

```text
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

- AppImage: replace the previous AppImage to update.
- tar.gz: extract over the application directory while preserving XDG data.
- Steam Deck: prioritize Desktop Mode without writing read-only system areas.
- Proton: retain Steam's expanded `%command%`; a dedicated wrapping strategy still requires real platform validation.

<a id="稳定用户数据"></a>

## Stable user data

Windows:

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
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

Use `~/.local/share/SteamWrapper/` when `$XDG_DATA_HOME` is unset.

Steam Launch Options may reference stable Runner only:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

<a id="runner-分发与安装"></a>

## Runner distribution and installation

Stage the current platform's release Runner before building:

```bash
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
```

The Linux resource is named `steamwrapper-runner`; the Windows resource is `SteamWrapperRunner.exe`. These are read-only bundle resources, not the targets of Steam Launch Options.

On first startup or Install / Repair Runner from Settings:

```text
Bundled Runner
→ temporary file
→ flush + SHA-256 verification
→ atomic replacement
→ bin/Runner in the stable user-data directory
```

- Do not copy again when hashes match.
- Install/repair when missing, damaged, or hash-mismatched.
- Touch only Runner in stable `bin`, not `profiles.toml`, `logs`, `backups`, or `cache`.
- On Windows, if Steam is using the old Runner, preserve it on replacement failure and ask the player to exit the game before retrying.

<a id="ci--release-验证"></a>

## CI / release validation

The release workflow should:

1. Stage the current platform's release Runner.
2. Run Rust, Dioxus, and E2E type/quality gates.
3. Generate the platform package with `dx bundle --release --package-types nsis|appimage`.
4. Extract Windows NSIS and verify a nonempty `SteamWrapperRunner.exe`.
5. Extract Linux AppImage and verify a nonempty `SteamWrapperManager/steamwrapper-runner`.
6. Establish that the release Rust dependency graph contains no WDIO / embedded WebDriver.
7. Upload consistently named bundles and SHA256SUMS.

Local Linux AppImage validation is not Windows NSIS or Steam Deck validation. Each requires evidence from its own CI or device.

<a id="当前-dioxus-封面策略"></a>

## Current Dioxus cover policy

Manager prefers local Steam caches:

```text
<Steam installation>/appcache/librarycache/
<Steam installation>/userdata/<steamid>/config/grid/
```

When a cover is missing, it uses only an AppID read from a local manifest to access the public Steam CDN:

```text
https://cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg
```

This request includes no Steam username, library list, profile, or API key. Public CDN responses may be reused according to HTTP caching policy. The application does not write new cover files. Offline operation, rate limits, 404s, and image-load failure leave a cover-unavailable placeholder and still permit configuration. Do not expand this limited fallback into third-party cover APIs or user-library uploads.

The first WinUI version reads local covers or shows placeholders only; the CDN description records the retained implementation.

<a id="发布渠道"></a>

## Release channels

```text
GitHub Release: international users, developers, and automated downloads
CNB Release: intended preferred README download entry for players in mainland China
```

Each formal release should include platform bundles, SHA256, English and complete Simplified Chinese release notes, and brief installation/update/uninstall instructions. Version names must match across GitHub and CNB to avoid confusing players.
