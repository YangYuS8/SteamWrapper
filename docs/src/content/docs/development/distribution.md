---
title: "v2 distribution and installation"
description: "The WinUI preview directory, stable Runner installation, and remaining Windows delivery work."
---

<a id="v2-distribution-and-installation"></a>
<a id="v2-分发与安装方案"></a>
<a id="原则"></a>

## Principles

WinUI is the only current Manager. The implemented delivery is a **self-contained Windows 11 24H2 x64 preview directory**, generated locally and by Windows CI. A WinUI per-user installer, tag-release pipeline, application updater, and automatic Steam Launch Options application/restoration remain unimplemented. Removing Dioxus does not mark those gates complete. See [installation](/SteamWrapper/guides/installation/) and the [roadmap](/SteamWrapper/project/roadmap/).

Future installation should require no developer tools or routine administrator rights. Updates must preserve user data and compatible stable Runner versions. Uninstall should remove Manager while retaining Runner and user data by default, because Steam may still reference them. Full removal needs an explicit choice and handling of known references; manually pasted or unenumerable options cannot be assumed restored. These are acceptance requirements, not existing installer behavior.

GitHub/CNB binary releases require inspection of actual downloadable artifacts. Source synchronization or release notes alone do not establish a binary release. Clean-system installation, update, recovery and uninstall need separate Windows evidence.

<a id="winui-本地预览目录"></a>

## Local WinUI preview directory

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

The result in `target/winui/publish` contains Manager, .NET, Windows App SDK, native/localized resources, brand assets, and `Runner/`. The Windows preview workflow uploads the complete directory as **SteamWrapper-WinUI-preview-windows-x64**. Extract every file and launch Manager from ordinary File Explorer. No single-EXE or setup-wizard delivery is claimed.

`pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox` uses disposable isolated data; an ordinary launch uses real `%LOCALAPPDATA%`. A development host can redirect AppData, so path existence alone does not prove Steam sees the same files. Manager checks final shared file locations and reports not ready on redirection. See [Windows development](/SteamWrapper/development/windows/).

Publishing builds Rust Runner and generates `runner-manifest.json` with schemaVersion 1, contractVersion 2, Cargo version and actual SHA-256. The C# `RunnerInstaller` service checks resource bytes/metadata and installs atomically to stable `bin/`; it is not a Windows setup installer. It preserves newer compatible versions and refuses unknown or same-version/different-hash replacements. Hash-bound `runner-releases/` metadata supports recognition after an interrupted binary/sidecar commit. Hashes establish consistency, not publisher authentication.

An identical existing Runner can be recognized and adopted. An unknown different binary is preserved with a matching-package instruction. Busy-file failures preserve the old Runner/configuration. Missing Runner resources do not prevent editing profiles, but Launch Options are not presented as ready.

Canonical assets are `assets/brand/steamwrapper.svg`, `.png` and `.ico`; the WinUI project includes the applicable icon/resources. Use `pnpm brand:generate` after editing the original SVG and `pnpm brand:check` to verify derivatives. pnpm and `@resvg/resvg-js` are development tools, not runtime requirements.

<a id="dioxus-desktop-bundle"></a>

## Archived Dioxus package inspection — 2026-09-08

The Dioxus Manager, NSIS/AppImage chain and Native E2E are removed from current development. The [old packaging configuration at ca6a09e](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/apps/manager-dioxus/Dioxus.toml) is an archive, not current distribution instructions.

On 2026-09-08, the final local Dioxus NSIS build produced `SteamWrapperManager_0.2.0_x64-setup.exe` at **5,167,920 bytes**, with English and Simplified Chinese (`English`, `SimpChinese`) installer resources. The installer and the actual packaged Manager PE each contained all 10 canonical icon sizes (16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixels), with every frame's SHA-256 matching the canonical ICO. Inspection confirmed the WebView2 download bootstrapper, no offline runtime installer, and `silent = true` in the WebView installation configuration. Bundled Runner was **1,180,160 bytes**, with its SHA-256 matching the release Runner. The local records are `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` and `bundle.log` in the same ignored directory. This was a build and package-content check: the installer was not run, and installation, runtime download, updates/uninstall, clean-system behavior, and WinUI delivery were not validated by it.

## Windows

The current downloadable preview is the CI directory archive described above. A complete portable ZIP and per-user WinUI installer are planned; names and signing policy must be established with the tag-release workflow. There is no current WinUI setup.exe to run.

A proposed future Manager location is `%LOCALAPPDATA%\Programs\SteamWrapper`. Wherever Manager is installed or extracted, Steam must reference only the stable Runner. Moving/deleting Manager must not silently remove that Runner or user data. Test in-place updates, busy files, interrupted replacement and recovery before describing them as supported delivery operations.

<a id="linux--steamos后续交付暂缓"></a>
<a id="linux--steamos-later-delivery-deferred"></a>

## Linux / SteamOS compatibility

Only existing Rust Runner/configuration compatibility and Linux process CI remain. There is **no current Linux Manager, AppImage, tar.gz GUI, or Steam Deck GUI delivery**. Preserve existing XDG data and stable Runner names. New Linux GUI/SteamOS support and Proton wrapping require separate requirements and actual platform evidence; Windows preview success does not establish them.

<a id="稳定用户数据"></a>

## Stable user data

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Existing Linux Runner uses `$XDG_DATA_HOME/SteamWrapper/`, falling back to `~/.local/share/SteamWrapper/`, with `profiles.toml`, `bin/steamwrapper-runner` and `logs/`. Preserve existing backups, caches and any legacy UI settings; retaining data does not imply a Linux UI exists.

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Launch Options never reference a versioned Manager directory or the bundled `Runner/` resource.

<a id="runner-分发与安装"></a>

## Runner distribution and installation

The WinUI publish script stages the Windows Runner and verified manifest automatically. `Runner/SteamWrapperRunner.exe` is a read-only package resource; the installed stable `bin/SteamWrapperRunner.exe` is Steam's target.

```text
Verify package Runner and version/hash metadata
→ verify existing shared location and version compatibility
→ write and flush a temporary file
→ verify bytes and replace atomically
→ check the installed stable Runner
```

Do not replace an identical or newer compatible Runner unnecessarily. Reject unknown/conflicting versions rather than overwriting them based on hash difference alone. Installation/repair changes only its own binary/metadata, preserving profiles, UI preferences, logs, backups and caches. On busy-file failure retain the working binary and let the user finish the game before retrying; do not terminate it.

<a id="ci--release-验证"></a>

## CI / release validation

Current Windows CI tests C# services, cross-language contracts, real Runner fixtures, self-contained publishing and safe output replacement, then uploads the full preview directory. Rust CI continues core/Runner checks and supported Windows/Linux process tests. There is no Dioxus bundle gate or current WinUI tag-release workflow.

Future WinUI releases must build the exact reviewed tag, inspect installer/portable contents, validate Runner metadata and localized resources, establish signing/trust, publish SHA-256 and complete bilingual notes, and verify matching downloads from GitHub/CNB. Clean-system installation, update, rollback and uninstall remain separate acceptance gates. A CI preview upload is not a stable release.

<a id="当前-dioxus-封面策略"></a>
<a id="current-dioxus-cover-policy"></a>

## Covers and network boundary

Current WinUI reads local Steam `appcache/librarycache/` and per-user `config/grid/` art and otherwise shows placeholders. It neither downloads nor persistently caches covers.

The planned official Steam CDN fallback is explicitly optional, local-first and offline by default. It may request missing covers for known local AppIDs only, using allowlisted HTTPS hosts/redirects, bounded transfers/image sizes and a quota-limited cache under SteamWrapper's own `cache/`. Preserve custom art and Steam/game files; disabling stops new requests, cleanup touches only downloaded SteamWrapper covers, and failure leaves configuration usable. No account queries, library uploads or third-party metadata providers are included. This is a future [roadmap](/SteamWrapper/project/roadmap/) feature, not a capability inherited from the removed Dioxus UI.

<a id="发布渠道"></a>

## Release channels

GitHub Releases and CNB Releases are intended WinUI release channels. Neither source synchronization nor a notes-only CNB release proves binary delivery. A formal release must provide matching binaries and SHA-256, exact version/commit/platform labels, signature information, complete English/Simplified Chinese notes, known limitations, and installation/update/removal instructions. Until that work is implemented and accepted, use the clearly labeled Windows CI preview.
