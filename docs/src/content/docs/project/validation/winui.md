---
title: "First WinUI configuration-slice validation"
description: "WinUI preview implementation and dated service, native UI, and publish evidence."
---

:::note[2026-10-02 retirement context]
References to Dioxus and Rust `manager-core` below belong to the September historical record. Their source, tooling and UI release chain were removed on 2026-10-02; WinUI is the only Manager. Original measurements and scenario evidence retain their dates and scope; see the current [architecture](/SteamWrapper/development/architecture/).
:::

<a id="first-winui-configuration-slice-validation"></a>

<a id="首个-winui-配置切片验收"></a>



Initial record date: 2026-09-07. Branch: `v2`. Scope: the Windows configuration preview and existing Rust Runner contracts. The default Dioxus release chain has not been replaced. Later observations below retain their own scope; [live Steam validation](/SteamWrapper/project/validation/steam/) records the expanded 2026-09-08 game coverage.

<a id="已实现"></a>

## Implemented

- Native WinUI window, configured-game list, adding games/Chinese search/manual AppID, and manual Steam path selection.
- Local Steam library/cover discovery and missing-cover placeholders, without network cover requests.
- Native Windows file/folder pickers, basic/advanced arguments, working directory, and wait modes.
- Local TOML field edits, unknown-text preservation, atomic replacement/backups, and external editing-conflict checks.
- Stable Rust Runner installation, hash/version protection, exact Launch Options generation, and clipboard copying.
- Separate copied/applied states and guidance to preserve previous Steam options for restoration.
- mise build/test/publish/sandbox tasks and independent Windows CI, while retaining previous workflows.
- Selective Windows App SDK components, fresh-directory publishing, completeness checks, and recovery after failed replacement to prevent removed dependencies remaining in output.
- Actual file-location checks for configuration, stable Runner, and installation candidates; detect development-host private AppData redirection and guide reopening from Explorer.

<a id="实际验证"></a>

## Actual verification

The complete native interaction table below describes the preview before component reduction. The final reduced artifact separately passed sandbox window launch, existing configuration loading, native picker open/cancel, saving, and stable Runner readiness. Old-artifact interaction results did not substitute for that review.

| Check | Result and boundary |
| --- | --- |
| Toolchain after reboot | .NET 10.0.400, Rust 1.98.1, MSVC/SDK, and project tools available |
| `mise run winui:test` | 43 passed, 0 failed, 0 skipped: original 34 configuration/service regressions plus nine actual-location checks, including profile-only redirection, real native handles, and valid junction upgrades |
| `mise run winui:contracts` | Passed: complete historical TOML/C# single-field edit/Rust comparison; real Runner argv/cwd, job/root waiting differences, exit codes, and missing-target logs |
| `mise run winui:publish` / `winui:sandbox` | Self-contained publish succeeded with app PRI, .NET, WinUI, Runner, and manifest; sandbox window launched |
| Native interface | Isolated example-library scanning, Chinese search, adding games, picker open/cancel, choosing an exe with Chinese/spaces, saving, and stable Runner installation completed |
| Copy | Clipboard matched the stable Runner launch command byte-for-byte, including `--appid "480" -- %command%` |
| UI invalid save | Saving a nonexistent exe was rejected; the old configuration SHA-256 was unchanged, with an understandable error |
| Reload | Unsaved changes triggered navigation protection; discarding the invalid input and reloading retained the saved game |
| Remote CI | Pushed to `v2`; [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718) for `3d322db` passed C#, cross-language/Runner, publish, and five directory regressions and uploaded the preview. Server 2025 builds are not clean Windows 11 acceptance |
| Publish after component reduction | Locked restore / Release self-contained publish passed; retained dependency versions/hashes were unchanged, with PRI, WinUI, .NET, picker projections, and Runner present |
| `Test-WinUIPublish.ps1` | Five passed: no stale files, missing resources preserve previous output, locked candidate rollback, successful replacement contains new files only, and out-of-bounds rejection |
| Native review of reduced artifact | Opened Chinese configuration, opened/cancelled native picker, saved successfully, and generated the sandbox stable Runner command. Evidence: `target/ui-comparison-5523059ad7ac4b60a91e86f7ee931cee` |
| Actual-location native review | Direct host launch showed redirection guidance and saving did not produce copyable options; the new build opened through Explorer read/saved normally and generated the unchanged command format, with Explorer as parent |

Regressions first observed missing behavior before fixes: the initial C# service threw an unimplemented exception, Rust assertions caught the absent single-field edit, and fixes covered explicit root, invalid Windows process_group, sandbox-library escape, and VDF names with parentheses. Actual launch found a missing PRI resource index; fixing SDK build switches let the window load. Publish checks then included app PRI to avoid an EXE-only false pass.

Contract evidence: `target/winui-contracts/bec08e11a3bc44bfbe8ce050e82dbd4a/results`. Native test directory: `target/winui/sandbox/9373d81fc50e4c8f97e1fd3fc17f93ac`. These configuration, contract, and sandbox-native checks used isolated `STEAM_DIR`, `LOCALAPPDATA`, `XDG_DATA_HOME`, and `STEAMWRAPPER_E2E_ROOT`; they did not operate on the real Steam library.

A later user-authorized real galgame session completed WinUI configuration, native Steam launch, and direct Runner comparison, tracing the earlier OS Error 3 to development-host AppData redirection. After ordinary Explorer installation, **the same command completed Steam → Runner → game → normal exit**, showing Stop during play, launchable/latest-cloud status afterward, and 11.2 → 11.4 hours. Original Launch Options were restored to empty; all 35 game files and four existing saves retained their hashes. Location-protection changes then passed 43 C# tests and cross-language/Runner contracts (`target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`), plus publish and both native launch contexts. See [real Steam validation](/SteamWrapper/project/validation/steam/).

Later publish regression first showed the old script retaining a unique sentinel, then verified fresh-directory replacement left no stale dependencies. A locked-file case also caught `Move-Item` creating an empty destination before failing. After switching to same-parent `Directory.Move`, old-byte restoration and candidate preservation passed. Evidence: `target/winui-component-study/publish-regression-before.log`, `publish-regression-after.log`, and `integrated-publish.json`.

<a id="运行预览"></a>

## Running the preview

```powershell
mise run winui:sandbox
```

This creates a new example Steam library and user directory. The publish directory is `target/winui/publish`; retain the entire directory. Open `SteamWrapper.Manager.exe` from ordinary Explorer for authorized real-library acceptance. See [Windows development](/SteamWrapper/development/windows/) for development-host AppData redirection and location checks. Automated regression uses the sandbox.

Manager directly pins `Microsoft.WindowsAppSDK.WinUI` 2.3.6 and `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6, corresponding to the original Windows App SDK 2.4.0 component set. After the location-protection fix, the publish directory measured **171.199 MiB (179,515,507 bytes, 457 files)**, including .NET/WinUI/Runner, uncompressed. This is not an installer download size. The earlier reduced artifact measured 179,511,987 bytes.

The original umbrella-package artifact measured 226.23 MiB (237,216,420 bytes, 522 files); the [six-round resource benchmark](/SteamWrapper/project/decisions/manager-comparison/) measured that historical artifact. Memory/startup were not rerun after component reduction, and reproducible cold startup was not measured. Publish regression command:

```powershell
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
```

<a id="后续语言支持"></a>

## Later language work

The 2026-09-08 localization change makes English the default and adds complete Simplified Chinese application resources. WinUI provides a sidebar language selector and shares `ui-settings.json` in the stable data root with the other Manager. `language` stores `en-US` or `zh-CN`; compatible aliases are `en` and `zh-Hans`, with trimming and case-insensitive matching. Missing/unknown language values fall back to English.

A successful language save updates application-owned static, dynamic, status, and service-error text immediately without reloading the form or discarding current inputs/protocol values. Save failure retains the old language and reports the error; invalid existing JSON is not overwritten. User names, paths, launch commands, logs, and operating-system diagnostics remain literal. The final application-service suite passed 59/59 tests, including 10 new localization/preference tests. The nested duplicate-JSON-key case failed before its fix, then passed. Cross-language/Runner contracts and the final self-contained publish also passed; the publish contains the `zh-CN` satellite resources.

The final native UI check used a disposable Steam/AppData fixture on Windows 11 build 26200 x64. It verified English defaults, Chinese persistence after restarting the final published app, and the Chinese Add Game dialog. Switching languages preserved unsaved bilingual names, paths, and arguments; existing success/error statuses, the advanced Expander's accessible name, and selected wait-mode text updated in both directions. Generated Launch Options remained available, profile bytes stayed identical, and language changes did not mark the form dirty or trigger an unsaved-change prompt on normal close. The application and window showed the new icon. The local record is `target/community-i18n-ui/13a3f10fc6164a77886be0d47e7df4aa/native-validation.json`.

Native Windows chrome and operating-system diagnostics follow the system language. This isolated check did not touch real Steam options, profiles, or game files, and does not establish clean-system installation, live Steam compatibility, or the complete accessibility matrix.

## Cover validation on 2026-10-03

[PR #10](https://github.com/YangYuS8/SteamWrapper/pull/10) adds local-first covers, opt-in official Steam CDN downloads and an isolated, bounded download cache. The following results apply to that cover slice; they do not replace the dated configuration and launch evidence above.

| Check | Result and boundary |
| --- | --- |
| Local discovery | Read-only scanning found cover candidates for all 44 locally installed games, including the newer hashed cache layouts for AppIDs `1091500` and `3548580`. Candidate discovery alone does not prove every image rendered. |
| Automated Windows gates | On 2026-10-02 at `a5debf1`, [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387662) passed 99 Application tests and nine actual Windows decoder tests, C#/Rust contracts, self-contained publishing and publish regressions. Cases cover offline defaults, corrupt images, bounded redirects/downloads/decoding, cancellation, cache quotas/expiry/clearing and preference preservation. |
| Other PR gates | [Rust CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387721) passed on Windows and Linux. [Bilingual documentation CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387800) passed; Pages deployment was correctly skipped for the PR. |
| Resumed native English review | An isolated library displayed local covers for `1091500` and `3548580`, displayed the fixture's cached `480.cover` offline, and retained the placeholder for missing art on `9999999`. Filtering for Chill with You preserved its displayed cover. |
| Native Simplified Chinese review | The main window, Add Game dialog, cover-settings Expander, privacy text, unchecked opt-in and clear-cache notice rendered in Simplified Chinese; game names remained unchanged. Closing and relaunching retained the Chinese interface. |
| Settings layout | In English and Simplified Chinese at the observed 914 × 714 window size, expanded cover settings reduced the game list to 100 pixels and left the controls and notice visible. The Chinese collapse check restored the 310-pixel, four-row list. This does not cover the complete scaling matrix. |
| Native official CDN opt-in | A separate `1091500` fixture began without local art or cache: the default-off state showed a placeholder and created no cover file. Enabling through the English checkbox persisted `true`, downloaded and displayed an actual 54,176-byte official portrait. Disabling persisted `false`; after closing, relaunching and reopening the dialog, the cached portrait still displayed with the setting unchecked and its SHA-256 and modification time unchanged. |
| Native cache clear | Chinese clearing removed the fixture's `480.cover`; English clearing removed the actual downloaded `1091500.cover`. Both restored the respective placeholders and localized notices. The Chinese check retained both local Steam images with unchanged SHA-256 hashes. Neither test wrote a profile. |

The native observations used disposable Manager/Steam fixtures; they did not modify real Steam options, profiles or game files. They did not disconnect the operating-system network, capture network traffic or interrupt an in-flight HTTP request; default zero-request behavior and cancellation are covered by the focused service tests above. The broader P0 UI automation/accessibility matrix and clean-system installer acceptance remain open; see the [roadmap](/SteamWrapper/project/roadmap/).

<a id="尚未完成的验收"></a>

## Outstanding acceptance

The initial Unity game pass has since been joined by the five independent translated 9-nine packages on 2026-09-08, including the local Episode 1 CHS launcher exiting before its game. Those observations are bounded to the actual packages/scenarios in [live Steam validation](/SteamWrapper/project/validation/steam/); they do not establish all launchers, engines, or achievements.

The complete keyboard/Chinese IME, scaling/high-contrast/screen-reader matrix, clean Windows 11 VM, installer, signing, updates/uninstall, and automatic Steam Launch Options apply/restore are unfinished. The current target is Windows 11 24H2 (26100) x64; Windows 10 and ARM64 are unverified.

Configuration editing supports explicit profile tables emitted by Rust; inline/dotted layouts are readable but refuse saving. Cooperative locks and two byte checks cannot eliminate non-cooperating external edits between the final check and replacement. Unknown or same-version/different-content installed Runner files are not forcibly overwritten; they require a matching package.
