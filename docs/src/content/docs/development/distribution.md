---
title: "v2 distribution and installation"
description: "The WinUI preview directory, stable Runner installation, and remaining Windows delivery work."
---

<a id="v2-distribution-and-installation"></a>
<a id="v2-分发与安装方案"></a>
<a id="原则"></a>

## Principles

WinUI is the only current Manager. Delivery includes a **self-contained Windows 11 24H2 x64 preview directory** and an unsigned [per-user installer preview](/SteamWrapper/guides/installer-preview/). Version tags still trigger portable ZIP prereleases; manual workflow runs also build and test setup without publishing a release. Ordinary pull requests and `main` run checks without packaging the application. An enabled updater and automatic Steam Launch Options application/restoration remain unimplemented.

The installer preview bundles runtime files, uses a fixed per-user root without routine elevation and retains the stable Runner/data tree on Manager-only uninstall. Busy Managers block mutation without forced exits. Unknown files are preserved; interrupted partial copies can be quarantined for manual diagnosis. Whole registry/shortcut/power-loss recovery, clean-client delivery and stable status remain separate gates.

The [approved Windows delivery plan](/SteamWrapper/project/design/windows-delivery/) distinguishes implemented deployment/signing safeguards from remaining Foundation approval, signed release and authenticated client-update stages. See the [code-signing policy](/SteamWrapper/project/design/code-signing/); no production certificate is available yet.

GitHub/CNB binary releases require inspection of actual downloadable artifacts. Source synchronization or release notes alone do not establish a binary release. Clean-system installation, update, recovery and uninstall need separate Windows evidence.

<a id="winui-本地预览目录"></a>

## Local WinUI preview directory

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

The result in `target/winui/publish` contains Manager, .NET, Windows App SDK, native/localized resources, brand assets, and `Runner/`. The release workflow packages this complete layout as a Windows x64 portable ZIP. Extract every file and launch Manager from ordinary File Explorer. The separate installer preview embeds the same complete layout; Manager itself is not a single-file application.

`pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox` uses disposable isolated data; an ordinary launch uses real `%LOCALAPPDATA%`. A development host can redirect AppData, so path existence alone does not prove Steam sees the same files. Manager checks final shared file locations and reports not ready on redirection. See [Windows development](/SteamWrapper/development/windows/).

Publishing builds Rust Runner and generates `runner-manifest.json` with schemaVersion 1, contractVersion 2, Cargo version and actual SHA-256. The C# `RunnerInstaller` service checks resource bytes/metadata and installs atomically to stable `bin/`; it is not a Windows setup installer. It preserves newer compatible versions and refuses unknown or same-version/different-hash replacements. Hash-bound `runner-releases/` metadata supports recognition after an interrupted binary/sidecar commit. Hashes establish consistency, not publisher authentication.

An identical existing Runner can be recognized and adopted. An unknown different binary is preserved with a matching-package instruction. Busy-file failures preserve the old Runner/configuration. Missing Runner resources do not prevent editing profiles, but Launch Options are not presented as ready.

Canonical assets are `assets/brand/steamwrapper.svg`, `.png` and `.ico`; the WinUI project includes the applicable icon/resources. Use `pnpm brand:generate` after editing the original SVG and `pnpm brand:check` to verify derivatives. pnpm and `@resvg/resvg-js` are development tools, not runtime requirements.

<a id="dioxus-desktop-bundle"></a>

## Archived Dioxus package inspection — 2026-09-08

The Dioxus Manager, NSIS/AppImage chain and Native E2E are removed from current development. The [old packaging configuration at ca6a09e](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/apps/manager-dioxus/Dioxus.toml) is an archive, not current distribution instructions.

On 2026-09-08, the final local Dioxus NSIS build produced `SteamWrapperManager_0.2.0_x64-setup.exe` at **5,167,920 bytes**, with English and Simplified Chinese (`English`, `SimpChinese`) installer resources. The installer and the actual packaged Manager PE each contained all 10 canonical icon sizes (16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixels), with every frame's SHA-256 matching the canonical ICO. Inspection confirmed the WebView2 download bootstrapper, no offline runtime installer, and `silent = true` in the WebView installation configuration. Bundled Runner was **1,180,160 bytes**, with its SHA-256 matching the release Runner. The local records are `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` and `bundle.log` in the same ignored directory. This was a build and package-content check: the installer was not run, and installation, runtime download, updates/uninstall, clean-system behavior, and WinUI delivery were not validated by it.

## Windows

Tagged previews remain complete portable ZIPs; an explicitly requested manual workflow also produces an unsigned setup preview. Packages remain unsigned and public releases remain prereleases. Installer acceptance is isolated; a clean Windows 11 client and production signing are still required before public installer/stable delivery.

The fixed installer root is `%LOCALAPPDATA%\Programs\SteamWrapper`. Steam references only the stable Runner in the separate data tree. Version directories, manifests, launcher and lease/journal recovery are owned by `apps/deployment-windows`; Inno owns its maintenance copy, uninstall registration and shortcuts. Repair/rollback limits are in the [installer guide](/SteamWrapper/guides/installer-preview/).

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

Daily Windows CI tests the C# Application services and Windows decoder, runs cross-language contracts and real Runner fixtures, and compiles the actual WinUI Manager. Rust CI retains format/check/test gates and supported Windows/Linux process tests. These runs retain test evidence but do not self-contained-publish or upload an application package. GitHub Pages keeps its independent `main` documentation deployment.

Release builds repeat the test and compile gates for the selected source, then run self-contained publication, all publication/recovery regressions and actual package inspection. The portable ZIP contains both language resources and the verified Runner. Its checksum and release metadata identify the exact version, commit and Windows x64 platform. Publishing a prerelease does not establish clean-system installation, update, rollback or uninstall acceptance. Signing and stable Windows delivery remain separate gates.

## Prepare and trigger a release

The [WinUI version release workflow](https://github.com/YangYuS8/SteamWrapper/blob/main/.github/workflows/winui-release.yml) separates application delivery from daily CI:

| Trigger | Result |
| --- | --- |
| Pull request or `main` push | Rust Windows/Linux checks, C# tests/contracts and actual WinUI compilation; no application archive |
| Push a version tag | Full gates, complete Windows x64 portable ZIP, checksum/metadata and bilingual notes; unsigned GitHub prerelease |
| **Run workflow** on a selected branch/ref | Full gates, complete `SteamWrapper-WinUI-preview-windows-x64` layout and tested unsigned `SteamWrapper-WinUI-installer-preview-windows-x64` artifact; no public release |
| Relevant documentation changes on `main` | Independent documentation checks and GitHub Pages deployment |

Release tags use `vMAJOR.MINOR.PATCH` with an optional SemVer prerelease suffix, such as `v0.2.1-preview.1`. The three-number base must match `<Version>` in `SteamWrapper.Manager.csproj` and the package versions in both `crates/core/Cargo.toml` and `crates/runner/Cargo.toml`. The commit must be reachable from `main`, and `releases/<tag>.en.md` plus `releases/<tag>.zh-CN.md` must be present in that revision. Invalid tags, mismatched versions or missing notes fail before delivery. A tag without a prerelease suffix still publishes as a GitHub prerelease while WinUI's delivery gates remain open.

The current source version is `0.2.1`, advanced because the new Runner PE resources change its bytes. Existing tags and historical releases must not be overwritten. Future versions must coordinate Rust, Manager, Application and deployment product versions and lockfiles, with complete bilingual notes. Confirm the intended main revision passed CI before tagging it. Merging this work does not create a public version.

For example, after a reviewed change has set all coordinated product/source versions to `0.2.1` and added both `v0.2.1-preview.1` notes:

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git tag -a v0.2.1-preview.1 -m "WinUI Windows preview 0.2.1-preview.1"
git push origin v0.2.1-preview.1
```

These commands are an example release operation, not a request to create that tag now. Check the selected commit before running them. The workflow checks out the exact tag and reruns its gates rather than borrowing a prior branch build. It creates a draft, uploads and verifies all assets, then publishes the prerelease without marking it as the latest stable release. Attached assets are `SteamWrapper-<tag>-win-x64.zip`, `<tag>.en.md`, `<tag>.zh-CN.md`, `release.json` and `SHA256SUMS`. The ZIP also contains `LICENSE` and both notes under `ReleaseNotes/`.

For an on-demand preview, use **Run workflow** and choose the ref. There are no release-mode inputs: every manual dispatch is preview-only, even when a tag is selected. If a release upload fails, prefer **Re-run failed jobs** after resolving the cause: the publishing jobs reuse the same immutable `SteamWrapper-WinUI-release-assets` build artifact. **Re-run all jobs** builds and packages again; if the bytes differ for the same version, publishing must reject the replacement. Use a new version for different content, and never move a published tag or overwrite published assets.

<a id="发布渠道"></a>

## Release channels

GitHub Releases is the version-tag binary channel. The workflow can also copy the same assets to CNB when the repository has `CNB_RELEASE_TOKEN` with repository-release read/write permissions and the existing `CNB_GIT_TOKEN` for source/tag synchronization. It checks the uploaded downloads against the generated SHA-256 values. Without the release token, the CNB binary step is skipped; ordinary `main` source synchronization remains separate.

A source mirror or notes-only release is not binary delivery. Check the tag workflow's actual GitHub and CNB upload/download results before advertising either channel, and record a failed or skipped mirror accurately. The old independent CNB notes-only publisher is removed so it cannot race the version-tag binary workflow. Clean-system installation, signing, updater and uninstaller acceptance remain open even when uploads pass.

<a id="当前-dioxus-封面策略"></a>
<a id="current-dioxus-cover-policy"></a>

## Covers and network boundary

Current WinUI first reads local Steam `appcache/librarycache/` and per-user `config/grid/` art, then valid SteamWrapper cached covers. Missing or unreadable art retains a placeholder; network requests require the explicit option below.

Official Steam CDN cover fallback is explicitly optional, local-first and off by default. It requests missing covers only for locally discovered AppIDs, using allowlisted HTTPS hosts/redirects and bounded transfers/decoded image sizes. Downloaded art is managed only under SteamWrapper's `cache/covers/` with quota, expiry, eviction and a clear action. Disabling cancels downloads and prevents new requests; valid cached art remains available offline. Cleanup preserves custom art, Steam/game files, profiles and Runner. No account queries, library uploads or third-party metadata providers are included. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings), [implementation limits](/SteamWrapper/development/architecture/#covers-and-safety-boundaries) and the remaining [native/player acceptance](/SteamWrapper/project/roadmap/).
