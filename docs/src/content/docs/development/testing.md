---
title: "Testing"
description: "Choose relevant service, native UI, Runner, package, and Steam validation gates."
---

<a id="testing"></a>

<a id="测试"></a>



SteamWrapper verifies the Rust core and independent Runner across Windows/Linux, and the WinUI Manager through C# service tests, cross-language contracts, self-contained publication checks and a local interactive native UI regression slice. Dioxus, its Rust management services, Native E2E and bundle workflow have been retired. Windows delivery still follows the [stage gates](/SteamWrapper/project/design/windows-v2/#8-实施顺序与停止条件).

The [measured Manager comparison](/SteamWrapper/project/decisions/manager-comparison/) is archived evidence for the stack decision. Its [comparison script](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/scripts/windows/Measure-ManagerComparison.ps1) and Dioxus source belong to commit `ca6a09e`; they are not current development prerequisites.

<a id="按改动选择验证"></a>

## Choose checks by change

Read the affected code and tests first, then choose checks that demonstrate the result of this change. Running the whole workspace before every edit is unnecessary, as are new source-string tests for documentation or purely cosmetic adjustments.

| Change | Local verification scope |
| --- | --- |
| Documentation / AGENTS / skills | Review diff, links and instruction conflicts; run `pnpm docs:check` and `pnpm docs:build` for documentation/site changes |
| Rust core behavior | Add a test that reproduces the missing behavior and observe the expected failure before implementation; run affected crate tests; expand to workspace checks/tests when shared contracts or other crates are affected |
| Runner launch / waiting | Real process regressions on the affected platform; expand to the workspace for CLI / TOML / shared-module changes |
| WinUI / C# services | `Invoke-WinUI.ps1 -Action Test`; add `Test-WinUIContracts.ps1` for profile-contract or Runner-distribution changes; publish the changed UI and run `Test-WinUINativeUi.ps1` on an unlocked interactive Windows desktop, with scoped manual checks for remaining UI gates |
| Purely visual changes | Build and inspect affected screens in an isolated Desktop preview; select existing tests according to impact, without using fixed CSS strings as visual acceptance |
| Publication / toolchain or shared builds | Relevant Rust/WinUI gates, current Windows Runner staging, complete publish-directory checks and `Test-WinUIPublish.ps1`; installer acceptance remains separate |

CI workflows continue to run their full gates. This table limits routine local work, not CI coverage. Repeat successful checks only when new changes, failures or unresolved questions justify it. Record missing tools as blockers; never label an unrun check as passed.

Behavioral regressions should verify externally observable results. Service or source-declaration tests do not prove native windows, accessibility, layout or file-picker behavior. A developer-only native UI regression harness now operates the actual WinUI application through Windows UI Automation; its first slice does not complete the [native acceptance roadmap](/SteamWrapper/project/roadmap/). Record the executed cases and scoped manual checks separately.

<a id="winui-迁移的新增验收"></a>

<a id="additional-winui-migration-acceptance"></a>

## WinUI acceptance

Verify the existing file contract between C# configuration services and Rust Runner first, then demonstrate the UI and installer. Available commands:

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test
pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Test-WinUINativeUi.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

The `Test` action runs both `SteamWrapper.Application.Tests` and `SteamWrapper.Windows.Tests`. It covers profile fidelity/conflicts/replacement failure, local Steam, cover preferences/download/cache services, stable Runner installation and shared-file locations, plus the actual Windows image decoder. The Windows test project links the production decoder source without loading WinUI or creating a window; it is not native UI automation. `Test-WinUIContracts.ps1` starts from shared historical fixtures. Rust compares the complete TOML and Profile after C# changes one field, then controlled parent/child processes verify exact argv, cwd, job/root waiting differences, exit codes and error logs for a new C# profile. See the [contract guide](https://github.com/YangYuS8/SteamWrapper/blob/main/tests/contracts/README.md). Test drivers, fixtures and generated user directories do not enter the publication directory.

Cover regressions use disposable Steam/settings/cache fixtures and injected HTTP handlers, with no requests to a real account or writes to a real library. Verify ordered custom/local candidates and hash layouts; default-disabled and persisted preferences; cached offline reuse; cancellation, timeout, 404/rate limits and cooldown; allowlisted redirects; bounded bytes/concurrency and cache quota/expiry/clear; and preservation of unrelated files. Windows decoder tests exercise valid PNG/JPEG, truncated containers, valid-CRC PNG with damaged zlib data, dimensions/pixel/byte limits, pre-cancellation, and available WebP codec behavior. Codec tests do not prove row rendering, responsive editing, language layout or dialog cancellation; those still need actual WinUI acceptance under P0.

Directory separation added regressions for AppID association, preservation of runtime paths outside the library, and actual installation conflicts across two libraries. That implementation passed 49/49 C# tests. Isolated native save, rescan and creation of an ambiguous profile were also verified; see the [directory-separation record](/SteamWrapper/guides/translated-games/). These isolated results alone do not establish live translated-game migration or achievement compatibility.

The English-default / Simplified Chinese implementation subsequently passed 59/59 C# tests, including 10 new localization/preference cases. Two default-English tests first failed against the old service messages; UTF-8 BOM preference loading and nested duplicate-JSON-key rejection also failed before their fixes. The tests verify matching English/Chinese catalog keys and format arguments, language changes for existing nested status/errors, invariant diagnostics and user values, scanner/Runner messages in both languages, canonical preference persistence, preservation of unknown fields and profiles, invalid/duplicate/oversized JSON rejection, and BOM compatibility. Cross-language/Runner contracts and the final self-contained publish passed. The [later language validation](/SteamWrapper/project/validation/winui/#later-language-work) records isolated native switching, restart persistence, preserved inputs/profile bytes, and icon checks; it is not clean-system or live Steam evidence.

For native localization acceptance, use a fresh isolated data root with no `ui-settings.json` and verify the supported system UI language, with English as the fallback. Open profile editing, add arguments and create a validation/status message, then switch to 简体中文 and back. Confirm that visible application-owned labels, parameter rows, wait-mode choices, existing status messages, dialogs and picker action labels use the selected language, while unsaved names, paths, arguments and generated launch options remain unchanged. Reopen the sandbox Manager to verify persistence. Check both languages' wrapping, clipping, keyboard operation and dialog layout. Inspect the published `zh-CN/SteamWrapper.Application.resources.dll`; a service/catalog test cannot establish native rendering or publication completeness.

The WinUI Manager uses `ui-settings.json` beside `profiles.toml` with `language` values `en-US` / `zh-CN`. `en` / `zh-SG` / `zh-Hans` are accepted aliases with case-insensitive matching and whitespace trimming. An absent key follows supported system UI cultures (`zh-CN`, `zh-SG` and explicitly `zh-Hans`); other cultures use English. Explicit saved choices take priority; invalid explicit values or unreadable settings use English. Reads and cover-only writes do not persist the detected language. Successful writes refresh the UI without reloading edited profiles; failures keep the previous language and report an error. Malformed settings remain untouched. OS-owned picker wording and raw external diagnostics retain their original language. Tests must use disposable settings directories and must not change actual AppData or Steam configuration.

The current Windows CI runs C# tests, cross-language Runner contracts and publication checks. The historical [WinUI CI run for `3d322db`](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718) passed; it is a dated result, not evidence for the latest commit. A hosted Windows Server 2025 build is not clean Windows 11 or native UI acceptance. The full acceptance scope is below. The local Unity game and all five isolated 9-nine translations separately completed the Steam flow; Episode 1 also covered its CHS launcher exiting first. See [live Steam validation](/SteamWrapper/project/validation/steam/) for the sequence and limits.

| Scope | Valid evidence |
| --- | --- |
| TOML compatibility | C# reads Rust fixtures, edits one field, and Rust checks unedited semantics after save; includes omitted wait_mode=root, new job profiles, alias keys, unknown fields/versions and all existing enum values |
| Save safety | Atomic-replacement failure, backup failure, multiple-writer/external-change conflicts, interruption and preservation of old files; serialization success is not proof of lossless saving |
| Configuration to runtime | Saved C# profiles drive real Rust Runner fixtures that assert argv, cwd, launcher/child waiting and errors; comparing TOML text alone is insufficient |
| Shared-data locations | Final handle paths for existing Runner/profiles and installation candidates; redirection reports not ready, candidate failure preserves old files, real junctions and legitimate path forms remain supported |
| WinUI interaction | Real native windows and pickers, cancellation, Chinese input, keyboard use, scaling and error recovery; old Dioxus DOM/RSX assertions do not apply |
| Windows publication | Self-contained installation on a clean Windows 11 x64 VM, stable Runner, update/file-lock/downgrade protection, moving Manager, and existing launch options remaining usable after uninstall |
| Steam apply/restore | Sanitized multi-user VDF fixtures, Steam-running protection, backups/rereads, conflict/interruption recovery and preservation of other settings; verify the private format first |
| Final play experience | A tester manually records running state, exit and playtime updates in real Steam, specifying the game, launcher and OS; fixtures cannot substitute |

Routine automation uses isolated Steam/user data. Live Steam acceptance requires explicit user authorization; this user authorized galgame tests that preserve game files. Record original launch options, file integrity and save protection separately. Tests must not decide which progress to overwrite in an unresolved cloud conflict. Real user data, full Steam configuration and local test backups do not enter commits or CI artifacts. See the [main design](/SteamWrapper/project/design/windows-v2/#4-配置保真是第一个门槛) for configuration boundaries.

For live acceptance, open `SteamWrapper.Manager.exe` from its complete publication directory through normal Windows File Explorer. Configure the profile and stable Runner, close Manager, then launch through Steam. On this machine, Codex's process environment previously mapped literal AppData paths into its package `LocalCache`. A shell or Manager reporting no package identity does not rule out redirection; final file-handle paths revealed the different views. See [shared data paths and live Steam acceptance](/SteamWrapper/development/windows/#shared-data-paths-and-live-steam-acceptance). Routine automation continues to use the isolated sandbox; mise aliases are optional.

Actual 2026-09-07 record: `The NOexistenceN of you AND me` (AppID 2873080) formed `Steam 4268 → Runner 4624 → game 19752 → Unity 12996` at 12:46:03. Following a normal exit from the title screen, Steam recorded all three child processes exiting with code 0 at 12:53:33. The UI returned to “Play,” cloud status was up to date, displayed playtime rose from 11.2 to 11.4 hours, and launch options were restored to empty. Opening the same Manager through normal Explorer and installing/configuring in the real stable directory succeeded with the existing command format, without changing quoting or slash rules. Final independent SHA-256 checks matched 35/35 game files and 4/4 original saves to the initial baseline, with no redirection in save-handle paths. This result applies to that game on this machine, not other games, clean VMs or installers.

Earlier isolated-directory testing on 2026-09-08: Episodes 2, 3, 4 and New of 9-nine each ran their out-of-library translations from Steam through the stable Runner. Chinese opening dialogue, normal exit, Steam running state and displayed playtime updates were confirmed. Episode 1 failed at the product-ID check when launched from its then-existing original entry point, before reaching the title screen; no Steam-path acceptance was performed at that stage. That failure record remains intact; results after restoring the CHS entry point are separate.

After Episode 1 recovery, normal-folder direct launch at 14:06:56–14:08:31 and Steam → Runner → CHS → game at 14:15:53–14:18:15 both passed Chinese opening dialogue and normal exit. The game and Runner continued for about 2 minutes 21 seconds after CHS exited. The UI confirmed `job`; independent observation recorded zero sampling errors, zero metadata failures and no final residual processes. This completes the real launcher-exits-first gate for this specific local CHS scenario. Logs recorded exit 0 only for CHS and Runner. The [current job implementation](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/platform/windows.rs) returns the launcher's status; the actual game's exit code is unknown, and neither the UI nor parent/child process relationships prove Job membership.

The 68 official files, three restored files and other non-save files remained unchanged. Four save differences already present before launch were recorded separately. Direct and Steam stages each naturally updated only five `savedata` files; all 24 original/checkpoint backup copies remained intact. Shared profiles for all five games were saved. Temporary Steam launch options were restored to empty (Episode 1 changed from an absent field to an empty string, with the same meaning). Episode 1 cloud sync stayed enabled, up to date and conflict-free; playtime rose from 36 to 38 minutes. Achievements remained 0/4, but no unlock condition was reached, so this is not a compatibility failure. Natural achievement unlocks, actual cloud synchronization of translated saves and broader launcher compatibility remain unverified. This game-validation round made no product-source changes and did not repeat compilation or full automated gates.

<a id="当前实现分层"></a>

## Current verification layers

| Layer | Command | Coverage |
| --- | --- | --- |
| Rust core / Runner | `cargo test --locked --workspace` | TOML, VDF, paths, Steam metadata, Launch Options and platform Runner behavior; no GUI dependency |
| C# services | `Invoke-WinUI.ps1 -Action Test` | Profile fidelity and safe writes, local discovery, language/cover settings, bounded cover requests/cache, stable Runner installation and shared-data locations |
| Windows image decoder | `Invoke-WinUI.ps1 -Action Test` | Exact production decoder with Windows codecs; valid/malformed images, resource limits and pre-cancellation, without a WinUI window |
| C# / Rust contract | `Test-WinUIContracts.ps1` | Complete unedited semantics plus real controlled Runner argv/cwd, waiting, exit and error behavior |
| Windows publication | `Test-WinUIPublish.ps1` | Self-contained Manager/Runner resources and publish-directory replacement/recovery |
| WinUI interaction | `Test-WinUINativeUi.ps1` after publication; `Invoke-WinUI.ps1 -Action Sandbox` for additional manual checks | UIA regressions against actual windows with disposable data; remaining picker, input, layout and player gates are scoped separately |

<a id="本地命令"></a>

## Native UI regression

After a complete publication, run `pwsh -NoProfile -File scripts/windows/Test-WinUINativeUi.ps1`, or optional `mise run winui:native-test`. The wrapper validates the existing portable layout, performs locked restore/build of `SteamWrapper.NativeUi.Tests`, then opens the actual Manager in new disposable Steam/user-data fixtures. It does not republish Manager, build an installer or use the real library. `-PublishDirectory` selects a specific complete portable layout; installed version directories are rejected.

Execution needs an **unlocked interactive Windows desktop**; keep that desktop available while the suite operates its fixture windows. CI only compiles this developer-only console UIA harness. Its WPF reference supplies Windows automation APIs; it is not another Manager implementation and is not shipped in application packages. A hosted service-session build is not a native test pass.

The first slice checks English startup, existing AppID immutability, Unicode edits across language changes, cancellation of unsaved navigation/window close, external-save conflicts, Chinese preference/unknown-setting persistence across restart, and unknown Runner failure without replacing its bytes. It also exercises native target-picker cancellation, selecting/filtering local games with missing/corrupt art while CDN is off, and a successful save preserving unknown TOML and generating stable Runner Launch Options. These selection checks do not prove every rendered cover or zero network traffic. Generated evidence and window snapshots remain under `target/winui/native-ui/`. The harness closes only its own fixture Manager normally; unresolved fixture windows and diagnostic files are retained. IME composition, display scaling, accessibility/layout, clipboard, actual download/network behavior and broader player acceptance still need separate evidence.

**Local 2026-10-03 record:** the wrapper executed all **10 native cases successfully** against the genuinely compiled `0.2.2` portable publication. Three disposable fixtures covered the normal editor/restart, picker/cover/successful-save flow and unknown Runner failure. Evidence records the actual publication EXE/DLL/Runner/manifest hashes and `cleanVm=false`; successful save also preserved TOML comments, unknown fields and backup bytes. This is actual interactive-window evidence for that slice, not CI execution, IME/scaling/clipboard, zero-HTTP or live Steam acceptance. W1 remains open.

**Later system-language record on 2026-10-03:** a new actual-window case failed against `0.2.2` on this `zh-CN` Windows desktop because first startup showed English. The compiled `0.2.3` implementation passed **11 native cases** in four disposable fixtures, including system-derived Chinese without writing a `language` preference and the existing explicit-English/Chinese-restart flows. Culture-injected service tests separately cover unsupported/traditional cultures, explicit invalid values, malformed settings and cover-only writes. This changes the first-run default; it does not claim IME, scaling or clean-client acceptance.

## Installer and signing commands

`Invoke-WinUI.ps1 -Action Test` also runs the deployment-library process/manifest/journal regressions. `Test-WinUIInstallerScripts.ps1` tests packaging guards without producing an application installer; `Test-WindowsSigning.ps1` exercises policy fixtures and real Windows trust failures without requesting signing. `Test-RunnerSigningMetadata.ps1` inspects the built Runner PE without executing it. These checks are part of daily Windows CI.

After full publication, `Test-WinUIProductMetadata.ps1` inspects all seven own EXE/DLL products, including Chinese resources, and the actual x64/GUI NativeAOT Host. The release workflow requires this gate; it does not execute those files or establish their publisher signature.

`Test-WinUIHostLanguage.ps1` separately starts the published NativeAOT Host in a fresh isolated program/data fixture, without `--language` or culture injection. On this `zh-CN` Windows desktop, missing and language-less preferences first failed because the Host was published with invariant globalization; after removing that mode, all five cases passed, including explicit English/Chinese and malformed-settings fallback. Settings, profiles and the independent Runner fixture retained their bytes. The isolation route requires the existing test-root authorization and bounds program/data paths to one sandbox; production preference locations are unchanged. This is actual local Host evidence, not another system culture or a clean VM.

After a complete publish and verified Inno toolchain installation, `Test-WinUIInstaller.ps1` runs real setup/uninstall and compatible maintenance-rollback processes with isolated program/data roots. Its default next-version input is a synthetic metadata fixture. Use a frozen old complete layout and `-UpgradePublishDirectory` pointing to a genuinely compiled new numeric version for real-version acceptance; see the [installer guide](/SteamWrapper/guides/installer-preview/) for commands and evidence limits. Version-tag and manual preview workflows run the isolated gate and separately build Setup; ordinary branch CI does not package Setup. Local real-version success still does not establish clean Windows 11, native wizard/Explorer or registry/shortcut/power-loss acceptance.

Disk admission now budgets payload files, the manifest, an atomic launcher copy, bounded state/journal replacements and a 16 MiB reserve. Its regression first observed an incorrectly accepted short budget, then verified refusal without activation or changed prior files. Seven isolated child-process stop cases cover five install and two recovery checkpoints using `Environment.Exit(73)`, durable receipts/journals, OS lease release, recovery/quarantine and unchanged separate data fixtures. These are compiled-engine process-stop tests, not a full machine power loss, actual disk filling or registry/shortcut fault. Version pruning is still pending: extending strict legacy state/root formats would break rollback to the old binaries and requires a separate compatible protocol.

The first genuine `0.2.2 → 0.2.3` installer run exposed a long-path uninstall refusal after adding original dependency licenses. A focused real Win32 regression reproduced an owned path growing from 248 to 281 characters during isolation. The fix uses Unicode extended paths for already verified delete handles; ownership, hash, size, reparse/readonly rejection and locking checks remain intact. Uninstall/reinstall and independent data preservation passed after the fix. The final Deployment suite passed **99/99**; explicit CLI language on invalid-root errors also has actual-process coverage. No Windows path-policy or player-data changes were made.

`Test-WinUIInstallableReleaseScripts.ps1` checks explicit schema-2 creation/download validation while preserving the schema-1 validator. GitHub and CNB publisher tests run both default legacy inputs and `-Installable`, with disposable APIs and no network writes. `Test-SignPathConfiguration.ps1` checks draft/declared prerequisites and exact signing targets, without a submission or credentials. The [application dossier](/SteamWrapper/project/design/signing-application/) distinguishes local preparation from external approval and real signed-artifact acceptance.

**Local 2026-10-03 real-version record:** a hash-verified frozen `0.2.1` layout and genuinely compiled `0.2.2` payload completed **13 real process steps with their expected outcomes**, including English installation, Chinese repair/upgrade, actual maintenance rollback `0.2.2 → 0.2.1`, Inno re-upgrade, busy/unknown-file/late-owned-lock refusals and removal/reinstall. `numericUpgradeUsesSyntheticMetadataFixture=false`; rollback preserved hashes for 928 owned version files plus maintenance/uninstaller/fixture shortcuts, and all six data fixtures remained unchanged. Both setups and their project-owned PE products matched their real numeric versions; current C#/Rust contracts passed separately. Logs and `evidence.json` remain under `target/winui/installer acceptance 中文 ' <id>/`. Evidence explicitly records `unsigned=true` and `cleanVm=false`. No clean VM was available; this does not complete W2, whole interruption/registry/shortcut recovery, pruning or authenticated delivery.

**Later corrected `0.2.2 → 0.2.3` record on 2026-10-03:** the frozen `0.2.2` layout and final compiled `0.2.3` publication completed the same **13 actual process steps**, including successful uninstall/reinstall after the long-path correction. Actual `0.2.3 → 0.2.2` maintenance rollback preserved 1,066 owned version-file hashes and the separate maintenance/uninstaller/shortcut ownership, followed by Inno re-upgrade. All six data fixtures remained unchanged; the upgrade was genuine, unsigned and local, with `cleanVm=false`. These corrected results are separate from the retained first failed fixture and do not close the outstanding W2 gates.

## Local commands

Install Windows tools by your preferred method; mise is optional. See [Windows development](/SteamWrapper/development/windows/) for SDK requirements and the PowerShell wrappers. The Rust workspace contains only core and Runner. On Linux it no longer needs GTK/WebKit, Dioxus CLI, Xvfb or a desktop session.

```bash
cargo fmt --all -- --check
cargo check --locked --workspace
cargo test --locked --workspace
```

On Windows, use the WinUI commands above and `pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1` for publish/recovery regression. `Invoke-Build.ps1 -Action Doctor` checks .NET/Rust/MSVC/SDK; `-Action RustTest` runs `cargo test --locked --workspace`. `-Action Verify` runs those Rust checks, then C# `Test`, `Test-WinUIContracts.ps1` and WinUI `Publish`, stopping on failure. No Dioxus, pnpm Native E2E or automatic native UI acceptance is invoked. Add publication-recovery and isolated native acceptance checks when their behavior changes.

All automated previews and process fixtures must point `STEAM_DIR`, `STEAMWRAPPER_E2E_ROOT`, `XDG_DATA_HOME` and `LOCALAPPDATA` into disposable directories. Never substitute real Steam or user data to make a regression pass.

<a id="dioxus-native-e2e"></a>

## Archived Dioxus Native E2E evidence

Dioxus and `manager-core` have been removed from the current workspace. The [archived implementation and tests](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/apps/manager-dioxus), [management services](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/crates/manager-core) and [historical test guide](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/docs/src/content/docs/development/testing.md#dioxus-native-e2e) remain available at `ca6a09e`. Their commands and dependencies are not current instructions and do not validate WinUI.

On 2026-09-07, local Windows completed the then-current Rust workspace, Runner processes, Dioxus check/release build and three specs / six Native E2E tests. Commit `3d322db` also passed Windows/Ubuntu and Linux AppImage checks in [full v2 CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282786). See the [archived environment record](/SteamWrapper/development/windows/#local-installation-and-verification-record) for tooling fixes and limits.

The 2026-09-08 language/icon work passed 10 isolated Native E2E executions: six existing cases, two language/status/error cases and language save/restart in two processes. That Windows Rust workspace passed 43 tests; the C#-output contract was intentionally ignored by the generic run and passed separately through `winui:contracts`. The two former Manager packages accounted for 30 tests, including unknown JSON number fidelity, nested duplicate-key rejection and the shared 64-level depth limit. TypeScript, E2E tooling, Dioxus check/release build and scoped strict Clippy passed. The historical NSIS content check and its limits remain in [distribution](/SteamWrapper/development/distribution/#ci--release-validation). None of these archived results establishes a current WinUI native UI gate, installer or clean-system pass.

<a id="runner-稳定安装验证"></a>

## Stable Runner installation verification

WinUI's [RunnerInstaller](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application/Services/RunnerInstaller.cs) verifies the existing Runner and any existing `profiles.toml` before reporting ready, and checks installation candidates and post-installation locations. A missing profile does not prevent an independent health check. The [location check](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application/Services/SharedDataFileLocation.cs) compares final file-handle paths with logical paths after explicit link resolution. Redirection reports not ready and asks the user to reopen Manager from File Explorer. The UI shows copyable launch options only after the installation service is ready. Neither the Launch Options string contract nor ProfileStore's save algorithm changed.

This implementation added nine [location regressions](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application.Tests/RunnerLocationTests.cs): redirected installed Runner; redirected upgrade candidate preserving the old Runner/manifest/profile; redirected first-install candidate; profile-only redirection; path-query failure; ordinary native handles; real junction upgrades; Chinese/case/extended-prefix handling; and DOS/UNC prefix normalization. Four redirection scenarios first demonstrated the old implementation incorrectly reporting ready, then passed after the fix. The final `mise run winui:test` result for that round was 43/43, with `winui:contracts` also passing. Red/green evidence is under ignored `target/runner-location-tests/`; that round's contracts are in `target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`.

After service tests, the new publication received separate native checks. Launching Manager from the redirected tool environment displayed a location warning and did not show launch options or a copy button after saving. Launching the new Manager through ordinary Explorer saved successfully and generated the same existing launch options. These native checks are recorded separately from service/process evidence and do not replace clean VM or installer validation.

Current stable-Runner installation safety is covered by the C# Application tests and cross-language contracts. Retired Rust `manager-core` and Dioxus UI installation checks are archived above; their old results are not substitutes for the current service tests.

Runner process tests cover Linux `process_group`, Windows Job Object and `process_name` boundaries on both platforms. `process_name` matches names only and cannot establish ownership when concurrent processes share a name; it is not the default wait mode.

## CI

`v2-ci.yml` defines the Windows / Ubuntu Rust core/Runner format/check/test gates and platform process tests. `winui-windows.yml` runs C# Application and Windows decoder tests, C# / Rust contracts, actual WinUI compilation and a compile-only native UI harness gate on pull requests and `main`. It does not run UIA in the hosted service session. Daily CI also runs publication-replacement and release-package safety tests plus mock GitHub/CNB publisher tests using disposable file/API fixtures; these do not write to external releases. It uploads test evidence, not an application package.

`winui-release.yml` runs the complete gates again for version tags or an explicit manual preview, then publishes the self-contained application, executes all publication/recovery regressions and inspects the complete layout. Version-tag runs validate the source/tag/version and bilingual notes before creating the explicit schema-2 package: Setup, portable ZIP, two localized notes, the legacy portable descriptor, installable descriptor and checksums. Tag runs can publish an unsigned GitHub prerelease; manual runs only upload preview artifacts. See [release preparation](/SteamWrapper/development/distribution/) for the release boundary and optional CNB mirror.

The former Dioxus Native E2E, AppImage job and NSIS release chain are removed. Workflow declarations do not prove that the latest run passed; inspect actual results separately. Manual release-workflow previews run real isolated installer processes; local native UI automation now has a first regression slice. Complete native acceptance, clean-client delivery and enabled updater acceptance remain roadmap work.

<a id="限制"></a>

## Limitations

- C# service/contract and publish checks do not establish native UI behavior, accessibility or a clean Windows installation. The native UI harness proves only its executed fixture cases on an interactive desktop, not the complete W1 gate.
- Routine automation does not operate real Steam. Live acceptance needs authorization, recorded original options, save protection, integrity checks and restoration. One-click Launch Options apply/restore remains a future feature.
- Runner process fixtures prove only their tested platform and lifecycle scenario; they do not establish real Proton, breakaway, Unix daemonize/new-session or Steam Deck compatibility.
- The preview includes a complete self-contained Windows directory and a separate unsigned installer. Isolated installation/removal tests do not establish clean Windows VM, native wizard or authenticated update acceptance.
- The 2026-09-07–09-08 Dioxus records above are archived historical results, not current WinUI evidence.
