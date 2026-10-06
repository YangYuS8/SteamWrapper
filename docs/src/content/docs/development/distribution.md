---
title: "v2 distribution and installation"
description: "The WinUI preview directory, stable Runner installation, and remaining Windows delivery work."
---

<a id="v2-distribution-and-installation"></a>
<a id="v2-分发与安装方案"></a>
<a id="原则"></a>

## Principles

WinUI is the only current Manager. Delivery includes a **self-contained Windows 11 24H2 x64 directory** and an unsigned [per-user installer](/SteamWrapper/guides/installer-preview/). Version tags package Setup and portable ZIP; tags with a prerelease suffix publish previews, while pure version tags publish stable releases. Manual workflow runs build and test setup without publishing a release. Ordinary pull requests and `main` run checks without packaging the application. Project-authenticated application updates are implemented; public availability follows the actual version/feed publication. WinUI remains a preview until its client acceptance gates pass. General automatic Steam Launch Options application remains unimplemented; uninstall can remove only exact recognized SteamWrapper commands.

The installer preview bundles runtime files and installs per user without routine elevation. The `0.2.5` installation-options work allows choosing an empty directory on a fixed local drive at first install, with upgrades and repairs remaining at the registered root. Start menu shortcuts default on, desktop shortcuts default off, and completion can open Manager. Manager-only uninstall retains the stable Runner/data tree; seven independent default-off uninstall choices add narrowly bounded restoration and cleanup. Scoped local installation-option and native checks have passed; clean-client and broader recovery gates remain open. Busy Managers block mutation without forced exits. Unknown files are preserved; interrupted partial copies can be quarantined for manual diagnosis. Whole registry/shortcut/power-loss recovery, clean-client delivery and stable status remain separate gates.

The [approved Windows delivery plan](/SteamWrapper/project/design/windows-delivery/) distinguishes implemented deployment/update safeguards from remaining client acceptance. Windows Authenticode is optional and independent of the project update key. See the [code-signing policy](/SteamWrapper/project/design/code-signing/); no production Windows certificate is available.

GitHub/CNB binary releases require inspection of actual downloadable artifacts. Source synchronization or release notes alone do not establish a binary release. Clean-system installation, update, recovery and uninstall need separate Windows evidence.

<a id="winui-本地预览目录"></a>

## Local WinUI preview directory

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

The result in `target/winui/publish` contains Manager, .NET, Windows App SDK, native/localized resources, brand assets, and `Runner/`. The release workflow packages this complete layout as a Windows x64 portable ZIP. Extract every file and launch Manager from ordinary File Explorer. The separate installer preview embeds the same complete layout; Manager itself is not a single-file application.

`pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox` uses disposable isolated data; an ordinary launch uses real `%LOCALAPPDATA%`. A development host can redirect AppData, so path existence alone does not prove Steam sees the same files. Manager checks final shared file locations and reports not ready on redirection. See [Windows development](/SteamWrapper/development/windows/).

Publishing builds Rust Runner and generates `runner-manifest.json` with schemaVersion 1, contractVersion 2, Cargo version and actual SHA-256. The C# `RunnerInstaller` service checks resource bytes/metadata and installs atomically to stable `bin/`; it is not a Windows setup installer. It preserves newer compatible versions and refuses unknown or same-version/different-hash replacements. Hash-bound `runner-releases/` metadata supports recognition after an interrupted binary/sidecar commit. Hashes establish consistency, not publisher authentication.

Windows MSVC builds now statically link Runner's C/C++ runtime. The independent stable executable must start without a separately installed Visual C++ redistributable. Before publication staging, `Test-RunnerDependencies.ps1`, called through `Test-RunnerSigningMetadata.ps1`, inspects the actual x64/GUI PE with MSVC `dumpbin /imports` and rejects ordinary or delay-loaded redistributable imports; Windows 11 inbox DLLs remain valid dependencies. This fixes a real clean-client loader failure found in the public `0.2.5` Runner. The corrected static Runner is included in public `v0.2.6-preview.1`. The earlier no-SDK loader comparison remains a narrow historical result; it alone does not establish a complete client lifecycle; see [Testing](/SteamWrapper/development/testing/#clean-windows-sandbox-acceptance).

After the complete publish, build a local Setup using the verified Inno toolchain:

```powershell
pwsh -NoProfile -File scripts/windows/Install-WinUIInstallerToolchain.ps1
pwsh -NoProfile -File scripts/windows/New-WinUIInstaller.ps1 -Tag "<matching-tag>"
```

The tag's numeric base must match the compiled source/payload. This writes a local installer and inspection metadata; it does not create a Git tag or publish a Release. mise is optional, and these developer tools are not player prerequisites. Actual isolated/guest verification commands and their evidence limits are in [Testing](/SteamWrapper/development/testing/).

An identical existing Runner can be recognized and adopted. An unknown different binary is preserved with a matching-package instruction. Busy-file failures preserve the old Runner/configuration. Missing Runner resources do not prevent editing profiles, but Launch Options are not presented as ready.

Canonical assets are `assets/brand/steamwrapper.svg`, `.png` and `.ico`; the WinUI project includes the applicable icon/resources. Use `pnpm brand:generate` after editing the original SVG and `pnpm brand:check` to verify derivatives. pnpm and `@resvg/resvg-js` are development tools, not runtime requirements.

<a id="dioxus-desktop-bundle"></a>

## Archived Dioxus package inspection — 2026-09-08

The Dioxus Manager, NSIS/AppImage chain and Native E2E are removed from current development. The [old packaging configuration at ca6a09e](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/apps/manager-dioxus/Dioxus.toml) is an archive, not current distribution instructions.

On 2026-09-08, the final local Dioxus NSIS build produced `SteamWrapperManager_0.2.0_x64-setup.exe` at **5,167,920 bytes**, with English and Simplified Chinese (`English`, `SimpChinese`) installer resources. The installer and the actual packaged Manager PE each contained all 10 canonical icon sizes (16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixels), with every frame's SHA-256 matching the canonical ICO. Inspection confirmed the WebView2 download bootstrapper, no offline runtime installer, and `silent = true` in the WebView installation configuration. Bundled Runner was **1,180,160 bytes**, with its SHA-256 matching the release Runner. The local records are `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` and `bundle.log` in the same ignored directory. This was a build and package-content check: the installer was not run, and installation, runtime download, updates/uninstall, clean-system behavior, and WinUI delivery were not validated by it.

## Windows

Version tags package a complete portable ZIP and per-user Setup without Windows Authenticode signing. A pure `vMAJOR.MINOR.PATCH` tag selects stable; a SemVer prerelease suffix selects preview. Manual dispatch produces trial artifacts without a public Release. Project-signed metadata authenticates application updates independently of a Windows publisher certificate; Authenticode is optional. Stable publication still requires actual client acceptance: passing packaging or local fixtures alone is insufficient.

The default installer root is `%LOCALAPPDATA%\Programs\SteamWrapper`; first installation can select another validated empty directory on a fixed local drive. Updates/repair stay at the registered location. Relocation requires Manager-only uninstall preserving data, then installation at the new location. Steam references only the stable Runner in the separate data tree. Version directories, manifests, launcher and lease/journal recovery are owned by `apps/deployment-windows`; Inno owns its maintenance copy, uninstall registration and shortcuts. The [installer guide](/SteamWrapper/guides/installer-preview/) lists the seven removal choices and their safeguards, including stopped Steam, account-file backups, unresolved-reference refusal, exact owned-file selection and permanently retained restoration backups/update trust state.

The current deployment source bounds version retention. On a later installation or repair, a healthy acknowledgment from the current Manager permits pruning under the exclusive installation lease: keep the current and recorded previous versions, and delete only hash-verified owned older files. An incoming version may temporarily leave three directories until a later maintenance operation after health confirmation. Without that confirmation, preserve historical versions and refuse admission beyond 32 versions or the 32 MiB ownership-journal budget. Do not infer that the recorded previous version was historically healthy. Legacy uninstall can inventory up to 1,024 versions within the same 32 MiB journal limit; busy, unknown or changed files and quarantined recovery data remain protected. Recovery reuses the existing staging protocol without new root files or state properties. The historical `v0.2.5-preview.1` does not include this retention change; [Testing](/SteamWrapper/development/testing/#version-retention-and-stable-channel-regressions) records the scoped source regressions.

On 2026-10-03, frozen `0.2.2` → genuinely compiled `0.2.3` passed 13 expected isolated real process steps, including actual maintenance rollback and Inno re-upgrade, late-file-lock/unknown-file refusal, uninstall and reinstall. Rollback preserved 1,066 owned version files, and six data fixtures retained their hashes. The new payload includes 601 files and the sealed third-party legal material. Evidence is explicitly unsigned, non-synthetic and `cleanVm=false`; the older `0.2.1` → `0.2.2` result remains separately dated. See [Testing](/SteamWrapper/development/testing/) for the actual records and remaining gates.

A later 2026-10-03 run of frozen `0.2.3` → genuinely compiled `0.2.4` passed 13 expected isolated Inno/maintenance steps. Actual rollback preserved 1,204 owned version files and maintenance/uninstaller/shortcuts before re-upgrade; late owned-file locks and unknown files refused uninstall, with subsequent normal uninstall/reinstall passing. Six separate data fixtures remained unchanged, with `numericUpgradeUsesSyntheticMetadataFixture=false`, `unsigned=true` and `cleanVm=false`. Current own PE versions, five actual NativeAOT Host language cases and cross-language contracts passed separately. This is scoped local delivery evidence; clean-client and retention gates remain open.

On 2026-10-06, frozen `0.2.5` → genuinely compiled `0.2.6` passed another **13 expected isolated Inno/maintenance outcomes**. Actual `0.2.6 → 0.2.5` rollback preserved 1,204 owned version-file hashes and maintenance/uninstaller/shortcuts before re-upgrade; all six data fixtures remained unchanged. Evidence is `target/winui/installer acceptance 中文 ' 98642fc6bdb34eb09d69bfb6e2aab89f/evidence.json`, with `numericUpgradeUsesSyntheticMetadataFixture=false` and `cleanVm=false`. The current `0.2.6` CLI service/contract gates also passed. This validates the genuinely new payload in isolated installer variants, not a published `v0.2.6` release or completed production clean-client acceptance.

After the static Runner change, a new 2026-10-06 isolated run repeated all **13 expected genuine `0.2.5 → 0.2.6` installer outcomes** at `target/winui/installer acceptance 中文 ' 9b6fb41052a44fc783e239c7315ff398/evidence.json`, preserving the same 1,204 rollback version-file hashes and six data fixtures. Corrected-Runner cross-language contracts also passed. The earlier run is retained as pre-linkage-change evidence; neither host-side run establishes production candidate Setup installation or a full clean-client lifecycle.

The corrected production-family local `0.2.6` candidate subsequently passed a **14-step first-install lifecycle** on a fresh offline build-26100 Sandbox without external SDK/runtime preparation. Native profile saving, exact stable Runner launch options, repair, Runner with Manager closed, default uninstall/data preservation, custom Chinese-folder reinstall and final owned-file/shortcut/registration removal passed. Actual Manager modules came from its own payload. [Testing](/SteamWrapper/development/testing/#clean-windows-sandbox-acceptance) records the exact Setup hash and scope: local dirty-source candidate, no numeric upgrade or public-release validation, Sandbox administrator account. This closes that candidate-first-install slice, not the overall W2, standard-user/IME/DPI or public stable-release gate.

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

Daily Windows CI tests the C# Application services and Windows decoder, runs cross-language contracts and real Runner fixtures, and compiles the actual WinUI Manager plus the developer-only native UI harness. The harness is not executed in hosted service sessions; actual native runs require an unlocked interactive desktop and disposable fixtures. Rust CI retains format/check/test gates and supported Windows/Linux process tests. These runs retain test evidence but do not self-contained-publish or upload an application package. GitHub Pages keeps its independent `main` documentation deployment.

Release builds repeat the test and compile gates for the selected source, then run self-contained publication, all publication/recovery regressions and actual package inspection. The portable ZIP contains both language resources and the verified Runner. Its checksum and release metadata identify the exact version, commit and Windows x64 platform. Publishing a prerelease does not establish clean-system installation, update, rollback or uninstall acceptance. Authenticode is optional; client acceptance still gates stable Windows delivery.

## Prepare and trigger a release

The [WinUI version release workflow](https://github.com/YangYuS8/SteamWrapper/blob/main/.github/workflows/winui-release.yml) separates application delivery from daily CI:

| Trigger | Result |
| --- | --- |
| Pull request or `main` push | Rust Windows/Linux checks, C# tests/contracts and actual WinUI compilation; no application archive |
| Push a version tag | Full build/test gates, complete Windows x64 Setup and portable ZIP, schema-2 checksum/metadata and bilingual notes; pure tags publish stable releases, prerelease suffixes publish previews |
| **Run workflow** on a selected branch/ref | Full gates, complete `SteamWrapper-WinUI-preview-windows-x64` layout and tested unsigned `SteamWrapper-WinUI-installer-preview-windows-x64` artifact; no public release |
| Relevant documentation changes on `main` | Independent documentation checks and GitHub Pages deployment |

Release tags use `vMAJOR.MINOR.PATCH` with an optional SemVer prerelease suffix. The three-number base must match `<Version>` in `SteamWrapper.Manager.csproj` and the package versions in both `crates/core/Cargo.toml` and `crates/runner/Cargo.toml`. Production Application, Deployment and Host versions must be coordinated as well. The commit must be reachable from `main`, and `releases/<tag>.en.md` plus `releases/<tag>.zh-CN.md` must be present in that revision. Invalid tags, mismatched versions or missing notes fail before delivery. Pure tags publish stable releases; prerelease tags publish previews. Only create the first pure tag after the remaining client gates pass, using a new coordinated numeric version such as `0.2.7` after `0.2.6-preview.1`.

The current coordinated source/product version is `0.2.7`, prepared for validation without a stable release. The latest public version is [v0.2.6-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.6-preview.1), also [mirrored on CNB](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.6-preview.1), with complete bilingual notes. [Release run 37462977733](https://github.com/YangYuS8/SteamWrapper/actions/runs/37462977733) passed both binary publications and signed preview indices; independent anonymous inspection of both seven-asset bundles passed at `target/winui/public-assets-effbde03ba68438ca6e0adbcaf066aa9/summary.json`. See the [current acceptance summary](/SteamWrapper/development/testing/#current-acceptance-2026-10-06): 178/37/160 C# cases and Runner contracts, focused Runner/stable-label UI checks, the isolated genuine 0.2.6 → 0.2.7 installation, ten clean candidate portable steps and five actual Host language cases passed. The public CNB 0.2.5 → 0.2.6 update passed its complete twelve-step UI-to-Setup lifecycle; the explicit GitHub download timed out without changing the old installation/data. The real guest-only VHD copy failure and repair passed separately with local payload manifests and actualInno=false. The final same-primary-SID Users/Medium 0.2.7 lifecycle and its controller passed all fourteen steps with exact guest-state restoration. Core first-release readiness is established within this scope; fresh-account primary sign-in and two-user GUI remain unverified.

Historically, the unsigned [v0.2.3-preview.1 technical preview](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.3-preview.1) was published by successful [run 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907). All seven public GitHub assets were downloaded and verified against their lengths, API digests and schema-2 inventory; seven own PE product versions and five actual downloaded NativeAOT Host language cases also passed. See [Testing](/SteamWrapper/development/testing/) for the scope. Earlier upgrade/rollback and PE-resource records remain dated evidence. Existing tags and releases must not be overwritten. Future versions must coordinate Rust, Manager, Application and deployment product versions and lockfiles, with complete bilingual notes. Confirm the intended main revision passed CI before tagging it; prepared notes or merging alone do not prove publication.

For installer upgrades, advance the three-part base for every new installable payload/manifest, not just the prerelease suffix. `v0.2.1-preview.1` → `v0.2.1-preview.2` changes the deployment manifest while both identify numeric `0.2.1`, and is rejected by the current same-version/different-content protection. Manual run-number artifacts are independent trials, not an upgrade sequence. Real upgrade acceptance uses a frozen old bundle and a genuinely compiled next unused base. The first newly signed payload must also use an unused base, for example `0.2.5` after unsigned `0.2.4`, rather than place newly signed/timestamped different Runner bytes under the previous unsigned version. Keep immutable retries unchanged.

The tag pipeline now uses an explicit schema-2 unsigned installable package while retaining the exact legacy schema-1 portable validator. The [execution queue](/SteamWrapper/project/roadmap/#execution-queue-2026-10-03) distinguishes completed retention/source regressions from the remaining native and clean-client/recovery acceptance for stable delivery. Windows Authenticode is optional following the declined Foundation application; project-signed application updates use a separate configured key. A Foundation certificate is not a stable-release prerequisite. The implemented public update flow still requires its actual client/download/installation evidence; general automatic Steam apply/restore remains deferred.

The already completed `0.2.5` publication below illustrates version-triggered delivery after source/notes review and CI. Do not repeat the existing tag; future releases need a new coordinated version:

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git tag -a v0.2.5-preview.1 -m "WinUI Windows preview 0.2.5-preview.1"
git push origin v0.2.5-preview.1
```

These commands describe an explicit release operation; their presence does not create a tag or prove publication. Check the selected commit before running them. The workflow checks out the exact tag and reruns its gates rather than borrowing a prior branch build. It creates a non-Latest draft, uploads and download-verifies all assets, then publishes according to the tag's channel. Stable releases become Latest; previews remain non-Latest. Retrying an already published release verifies its immutable assets without changing publication flags.

The seven assets are `SteamWrapper-<tag>-win-x64-setup.exe`, `SteamWrapper-<tag>-win-x64.zip`, `<tag>.en.md`, `<tag>.zh-CN.md`, `portable-release.json`, `release.json` and `SHA256SUMS`. Outer `release.json` uses schema 2, explicitly sets `signed=false`, `installer=true`, `portable=true`, and binds both artifacts' lengths/digests and the deployment inventory. `portable-release.json` preserves schema-1 portable metadata and its unchanged validation gate; `SHA256SUMS` covers the other six assets. The ZIP contains `LICENSE` and both notes under `ReleaseNotes/`. Packaging must preserve applicable bundled third-party notices/licenses and upstream signatures; third-party components must retain their actual licenses rather than being described collectively as MIT.

For an on-demand preview, use **Run workflow** and choose the ref. There are no release-mode inputs: every manual dispatch is preview-only, even when a tag is selected. If a release upload fails, prefer **Re-run failed jobs** after resolving the cause: the publishing jobs reuse the same immutable `SteamWrapper-WinUI-release-assets` build artifact. **Re-run all jobs** builds and packages again; if the bytes differ for the same version, publishing must reject the replacement. Use a new version for different content, and never move a published tag or overwrite published assets.

<a id="发布渠道"></a>

## Release channels

GitHub Releases is the version-tag binary channel. CNB mirroring uses `CNB_GIT_TOKEN` for source/tag synchronization and prefers `CNB_RELEASE_TOKEN` for release operations. If no separate release token is configured, it reuses `CNB_GIT_TOKEN`; that token must also have `repo-release` read/write permission for `Nesoriel/SteamWrapper`. Git synchronization alone does not prove release permission. The publisher checks uploaded downloads against the original SHA-256 values; unavailable credentials skip the optional binary step.

If the current preview needs mirror maintenance without rebuilding, use `gh workflow run cnb-release-mirror.yml --ref main -f tag=v0.2.6-preview.1`; its already verified mirror does not need a repeat upload. This maintenance workflow checks the public seven-asset GitHub bundle, exact mainline source tag and currently authorized signed release, then publishes and verifies the same CNB assets. It adds the verified mirror to the update feed under the same publication/renewal lock. It cannot promote a different historical version or overwrite versioned attachments. A permission failure requires adding `repo-release` read/write permission to the existing token or supplying `CNB_RELEASE_TOKEN`; never put a token in repository files or chat.

For `v0.2.3-preview.1`, all seven GitHub downloads were verified. CNB release credentials were not configured, so its binary mirror was skipped and no CNB binary download is advertised.

On 2026-10-05, [maintenance run 37285639449](https://github.com/YangYuS8/SteamWrapper/actions/runs/37285639449) published [the `v0.2.5-preview.1` CNB mirror](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.5-preview.1) and its public signed preview feed. All seven CNB assets passed anonymous length/SHA-256 checks against the unchanged GitHub assets. The actual `0.2.5` update service, explicitly selecting CNB, verified the project signature and downloaded the exact 49,901,116-byte Setup; the same-version check returned no update. The older installed tag was only a comparison input; Setup was not executed. Both sites serve identical signed index bytes. No software rebuild or immutable asset replacement was needed, and a scoped `CNB_RELEASE_TOKEN` is now configured.

The subsequent [renewal run 37286426643](https://github.com/YangYuS8/SteamWrapper/actions/runs/37286426643) also passed public signature and byte-equality checks for both feeds. It advanced the sequence and validity window while preserving the release identity, installer hash/length, mirror URL and all seven immutable GitHub asset IDs/hashes/lengths. This acceptance downloaded only metadata and did not execute Setup.

On 2026-10-06, [release run 37462977733](https://github.com/YangYuS8/SteamWrapper/actions/runs/37462977733) published `v0.2.6-preview.1` from `6d0acffd2b609cc7c95a0c1bf7dbd53d0a903a70` to GitHub and CNB, with the project-signed preview indices. Independent inspection downloaded both sites' complete seven assets anonymously and verified tag commit, API digests, lengths and schema-2 inventories. Setup is 49,913,873 bytes, SHA-256 `0f09539dcdf735a10eb64caee3c105481011df6241bd54f0d9480458f2858293`; ZIP is 73,826,444 bytes, SHA-256 `eb904fee536243cb0db0633a125ee60e7ddf8bf4a8724a1238cc14c93a688b61`. This asset inspection did not execute Setup. A separate fresh SDK-free Sandbox subsequently passed the full public CNB 0.2.5 → 0.2.6 update through the native UI, actual downloaded Setup and healthy automatic Manager restart. Data and the trust state captured before Install survived the update and default uninstall; Runner changed only after explicit profile Save. The fresh explicit-GitHub UI download failed under the existing timeout policy, preserving the older installation/profile/Runner bytes. Exact evidence and remaining gates are in [Testing](/SteamWrapper/development/testing/#current-acceptance-2026-10-06).

A source mirror or notes-only release is not binary delivery. Check the tag workflow's actual GitHub and CNB upload/download results before advertising either channel, and record a failed or skipped mirror accurately. The old independent CNB notes-only publisher is removed so it cannot race the version-tag binary workflow. Clean-system installation, signing, updater and uninstaller acceptance remain open even when uploads pass.

<a id="当前-dioxus-封面策略"></a>
<a id="current-dioxus-cover-policy"></a>

## Project-signed application updates

The Manager update flow authenticates project metadata rather than requiring an Authenticode certificate. The player clicks **Check for updates**, downloads an offered version and confirms installation. Automatic checks are off by default. Portable copies receive download guidance; the updater never overwrites arbitrary extraction folders. Ordinary Steam launches do not involve updates.

The version-tag workflow publishes immutable Setup/ZIP assets first, then `Publish-UpdateMetadata.ps1` signs a separate schema-2 payload in `SteamWrapper-update.json`. The fixed `update-preview`/`update-stable` Releases carry only this mutable index. Their tags do not match the software-build trigger. `update-metadata.yml` renews existing preview/stable feeds weekly for 28 days without rebuilding binaries, skipping channels not yet published. A missing feed is an unavailable update service, not an up-to-date result.

Stable publication advances both signed feeds to the same new installer, so existing preview users can move to the stable release. The installed tag selects the feed automatically; after installing a pure tag, Manager uses the stable feed. Each feed retains its own signature, sequence and freshness checks. A stable feed rejects prerelease targets. Both feeds retain downgrade and same-numeric-version replacement protection; changing only the suffix is not a supported upgrade.

One-time maintainer configuration uses `pwsh -NoProfile -File scripts/releases/Initialize-UpdateSigning.ps1` with authenticated `gh`. It generates an ECDSA P-256 key, sends the private half directly to GitHub's `STEAMWRAPPER_UPDATE_PRIVATE_KEY` secret, and writes only the public key to `packaging/windows/update-trust.json`. Existing keys are never replaced. Commit the public configuration before releasing a client. PR/main CI uses fixture keys; the protected signing secret is used only by release/renewal jobs. Players do not generate keys or install certificates. Key loss/rotation and download verification are described in the [delivery design](/SteamWrapper/project/design/windows-delivery/).

CNB remains unavailable as an update source until release credentials work and the matching binaries and public signed feed are verified. Signed metadata binds the same SHA-256/length for both sources. A CLI login alone does not configure long-lived CI credentials. The public client contains no access token. Existing releases without this update UI need one manual installation of the new client. Windows may still apply its own trust prompts or restrictions to unsigned executables.

## Covers and network boundary

Current WinUI first reads local Steam `appcache/librarycache/` and per-user `config/grid/` art, then valid SteamWrapper cached covers. Missing or unreadable art retains a placeholder; network requests require the explicit option below.

Official Steam CDN cover fallback is explicitly optional, local-first and off by default. It requests missing covers only for locally discovered AppIDs, using allowlisted HTTPS hosts/redirects and bounded transfers/decoded image sizes. Downloaded art is managed only under SteamWrapper's `cache/covers/` with quota, expiry, eviction and a clear action. Disabling cancels downloads and prevents new requests; valid cached art remains available offline. Cleanup preserves custom art, Steam/game files, profiles and Runner. No account queries, library uploads or third-party metadata providers are included. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings), [implementation limits](/SteamWrapper/development/architecture/#covers-and-safety-boundaries) and the remaining [native/player acceptance](/SteamWrapper/project/roadmap/).
