<a id="测试"></a>

# Testing

English | [简体中文](testing.zh-CN.md)

SteamWrapper v2 verifies behavior, services, UI and packages separately. The WinUI preview has C#, cross-language and real Runner tests; Dioxus baseline gates remain in place. Final Windows delivery still follows the [redesign's stage gates](windows-v2-design.md#8-实施顺序与停止条件).

The same-input configuration probes, native-save checks and resource measurements for both Windows Managers are in the [measured comparison](windows-manager-comparison.md). The resource-measurement script is `scripts/windows/Measure-ManagerComparison.ps1`. Prepare both release artifacts first, then run measurements sequentially after other builds and tests finish.

<a id="按改动选择验证"></a>

## Choose checks by change

Read the affected code and tests first, then choose checks that demonstrate the result of this change. Running the whole workspace before every edit is unnecessary, as are new source-string tests for documentation or purely cosmetic adjustments.

| Change | Local verification scope |
| --- | --- |
| Documentation / AGENTS / skills | Review diff, links, instruction conflicts and skill metadata; UI compilation and packaging are not required |
| core / manager-core behavior | Add a test that reproduces the missing behavior and observe the expected failure before implementation; run affected crate tests; expand to workspace checks/tests when shared contracts or other crates are affected |
| Runner launch / waiting | Real process regressions on the affected platform; expand to the workspace for CLI / TOML / shared-module changes |
| Dioxus interaction / service wiring | Relevant Rust tests, `dx check` / build, and isolated Native E2E covering the behavior |
| WinUI / C# services | `mise run winui:test`; add `winui:contracts` for profile-contract or Runner-distribution changes; use `winui:publish` and isolated native interaction for UI changes |
| Purely visual changes | Build and inspect affected screens in an isolated Desktop preview; select existing tests according to impact, without using fixed CSS strings as visual acceptance |
| E2E tooling or dependencies | Frozen-lockfile install, TypeScript check, affected Native E2E |
| Packaging / publication / toolchain or shared builds | Full quality gates, current-platform release Runner staging, actual package extraction inspection |

CI / release workflows continue to run their full gates. This table limits routine local work, not CI coverage. Repeat successful checks only when new changes, failures or unresolved questions justify it. Record missing tools as blockers; never label an unrun check as passed.

Behavioral regressions should verify externally observable results. Existing `ui_contract` source assertions prove that declarations exist, not that windows, accessibility, layout or native file selection work.

<a id="winui-迁移的新增验收"></a>

## Additional WinUI migration acceptance

Verify the existing file contract between C# configuration services and Rust Runner first, then demonstrate the UI and installer. Available commands:

```powershell
mise run winui:test
mise run winui:contracts
mise run winui:publish
mise run winui:sandbox
```

`winui:test` covers profile fidelity/conflicts/replacement failure, local Steam, stable Runner installation and shared-file locations. `winui:contracts` starts from shared historical fixtures. Rust compares the complete TOML and Profile after C# changes one field, then controlled parent/child processes verify exact argv, cwd, job/root waiting differences, exit codes and error logs for a new C# profile. See the [contract guide](../tests/contracts/README.md). Test drivers, fixtures and generated user directories do not enter the publication directory.

Directory separation added regressions for AppID association, preservation of runtime paths outside the library, and actual installation conflicts across two libraries. That implementation passed 49/49 C# tests. Isolated native save, rescan and creation of an ambiguous profile were also verified; see the [directory-separation record](translated-games.md). These isolated results alone do not establish live translated-game migration or achievement compatibility.

The English-default / Simplified Chinese implementation subsequently passed 59/59 C# tests, including 10 new localization/preference cases. Two default-English tests first failed against the old service messages; UTF-8 BOM preference loading and nested duplicate-JSON-key rejection also failed before their fixes. The tests verify matching English/Chinese catalog keys and format arguments, language changes for existing nested status/errors, invariant diagnostics and user values, scanner/Runner messages in both languages, canonical preference persistence, preservation of unknown fields and profiles, invalid/duplicate/oversized JSON rejection, and BOM compatibility. Cross-language/Runner contracts and the final self-contained publish passed. The [later language validation](winui-preview-validation.md#later-language-work) records isolated native switching, restart persistence, preserved inputs/profile bytes, and icon checks; it is not clean-system or live Steam evidence.

For native localization acceptance, use a fresh isolated data root with no `ui-settings.json` and verify English regardless of the Windows display language. Open profile editing, add arguments and create a validation/status message, then switch to 简体中文 and back. Confirm that visible application-owned labels, parameter rows, wait-mode choices, existing status messages, dialogs and picker action labels use the selected language, while unsaved names, paths, arguments and generated launch options remain unchanged. Reopen the sandbox Manager to verify persistence. Check both languages' wrapping, clipping, keyboard operation and dialog layout. Inspect the published `zh-CN/SteamWrapper.Application.resources.dll`; a service/catalog test cannot establish native rendering or publication completeness.

Both Managers use `ui-settings.json` beside `profiles.toml` with `language` values `en-US` / `zh-CN`. `en` / `zh-Hans` are accepted aliases with case-insensitive matching and whitespace trimming. Missing or unknown language values default to English. Successful writes refresh the UI without reloading edited profiles; failures keep the previous language and report an error. Malformed settings remain untouched. OS-owned picker wording and raw external diagnostics retain their original language. Tests must use disposable settings directories and must not change actual AppData or Steam configuration.

The added Windows CI retains the old workflows and runs these tests and directory publication in order. [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718) for `3d322db` actually passed. A hosted Windows Server 2025 build is not clean Windows 11 acceptance. The full acceptance scope is below; do not extrapolate fixtures to untested platforms or live Steam. The local Unity game and all five isolated 9-nine translations separately completed the Steam flow. Episode 1 also covered its CHS launcher exiting first; see [live Steam validation](real-steam-validation.md) for the sequence and limits.

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

Routine automation uses isolated Steam/user data. Live Steam acceptance requires explicit user authorization; this user authorized galgame tests that preserve game files. Record original launch options, file integrity and save protection separately. Tests must not decide which progress to overwrite in an unresolved cloud conflict. Real user data, full Steam configuration and local test backups do not enter commits or CI artifacts. See the [main design](windows-v2-design.md#4-配置保真是第一个门槛) for configuration boundaries.

For live acceptance, open `SteamWrapper.Manager.exe` from its complete publication directory through normal Windows File Explorer. Configure the profile and stable Runner, close Manager, then launch through Steam. On this machine, Codex's process environment previously mapped literal AppData paths into its package `LocalCache`. A shell or Manager reporting no package identity does not rule out redirection; final file-handle paths revealed the different views. See [shared data paths and live Steam acceptance](windows-development.md#shared-data-paths-and-live-steam-acceptance). Routine mise/sandbox workflows remain unchanged.

Actual 2026-09-07 record: `The NOexistenceN of you AND me` (AppID 2873080) formed `Steam 4268 → Runner 4624 → game 19752 → Unity 12996` at 12:46:03. Following a normal exit from the title screen, Steam recorded all three child processes exiting with code 0 at 12:53:33. The UI returned to “Play,” cloud status was up to date, displayed playtime rose from 11.2 to 11.4 hours, and launch options were restored to empty. Opening the same Manager through normal Explorer and installing/configuring in the real stable directory succeeded with the existing command format, without changing quoting or slash rules. Final independent SHA-256 checks matched 35/35 game files and 4/4 original saves to the initial baseline, with no redirection in save-handle paths. This result applies to that game on this machine, not other games, clean VMs or installers.

Earlier isolated-directory testing on 2026-09-08: Episodes 2, 3, 4 and New of 9-nine each ran their out-of-library translations from Steam through the stable Runner. Chinese opening dialogue, normal exit, Steam running state and displayed playtime updates were confirmed. Episode 1 failed at the product-ID check when launched from its then-existing original entry point, before reaching the title screen; no Steam-path acceptance was performed at that stage. That failure record remains intact; results after restoring the CHS entry point are separate.

After Episode 1 recovery, normal-folder direct launch at 14:06:56–14:08:31 and Steam → Runner → CHS → game at 14:15:53–14:18:15 both passed Chinese opening dialogue and normal exit. The game and Runner continued for about 2 minutes 21 seconds after CHS exited. The UI confirmed `job`; independent observation recorded zero sampling errors, zero metadata failures and no final residual processes. This completes the real launcher-exits-first gate for this specific local CHS scenario. Logs recorded exit 0 only for CHS and Runner. The [current job implementation](../crates/runner/src/platform/windows.rs) returns the launcher's status; the actual game's exit code is unknown, and neither the UI nor parent/child process relationships prove Job membership.

The 68 official files, three restored files and other non-save files remained unchanged. Four save differences already present before launch were recorded separately. Direct and Steam stages each naturally updated only five `savedata` files; all 24 original/checkpoint backup copies remained intact. Shared profiles for all five games were saved. Temporary Steam launch options were restored to empty (Episode 1 changed from an absent field to an empty string, with the same meaning). Episode 1 cloud sync stayed enabled, up to date and conflict-free; playtime rose from 36 to 38 minutes. Achievements remained 0/4, but no unlock condition was reached, so this is not a compatibility failure. Natural achievement unlocks, actual cloud synchronization of translated saves and broader launcher compatibility remain unverified. This game-validation round made no product-source changes and did not repeat compilation or full automated gates.

<a id="当前实现分层"></a>

## Current verification layers

| Layer | Command | Coverage |
| --- | --- | --- |
| Rust domain / service | `cargo test --workspace` | TOML, VDF, paths, Steam filtering, covers, Launch Options, Manager services and Runner wait modes |
| Dioxus contract | `cargo test -p steamwrapper-manager-dioxus --test ui_contract` | Source declarations for player flows, file selection, services, bundles and brand consistency; not real native interaction |
| Dioxus build | `dx check` / `dx build --release` | Dioxus 0.7.10 project, RSX, static assets and release client build |
| Dioxus Native E2E | `pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native` | Real Dioxus binary and `manager-core` with isolated Steam / profile / Runner fixtures |
| Platform bundle | `dx bundle --release --package-types …` | Bundled Runner resources and NSIS / AppImage artifacts |

<a id="本地命令"></a>

## Local commands

mise manages the Windows environment. Use `mise run windows:doctor` to inspect it and `mise run windows:verify` for existing quality gates. See [Windows development](windows-development.md) for setup and WinUI compilation. The following `just`/underlying commands remain available; the WinUI smoke does not replace application or Steam acceptance.

Prefer the root `justfile`:

```bash
just dev          # Start Desktop Manager and hot reload with real Steam / user data
just dev-sandbox  # Start with disposable Steam / user-data fixtures
just test         # Rust formatting, checks and tests
just e2e          # Dioxus Native E2E
just verify       # All local quality gates
just bundle-linux # Stage Runner and build a Linux AppImage
```

`dev-sandbox` neither displays the real Steam library nor retains profiles or Runner. It is only for safe UI previews. `just --list` lists all recipes. Corresponding underlying commands:

```bash
pnpm install --frozen-lockfile
pnpm --filter steamwrapper-manager-dioxus-e2e exec tsc --noEmit
pnpm --filter steamwrapper-manager-dioxus-e2e run test:tooling

cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
cd ../..

cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Linux builds, tests and packaging need WebKitGTK, GTK3, `libxdo-dev`, AppIndicator, librsvg and `patchelf`. Current Dioxus Desktop links X11 libraries through `muda`'s default `libxdo` feature. Ubuntu needs `libxdo-dev` or Manager tests/AppImage builds fail at link time with `unable to find library -lxdo`. Linux dependency lists for CI Check, AppImage and release all include it. [Ubuntu package details](https://packages.ubuntu.com/noble/amd64/libxdo-dev)

Headless Linux CI also needs `xvfb`, `xauth` and `dbus-daemon` to run Native E2E with a virtual X display and temporary D-Bus session. Compilation/packaging alone do not require a display service. GTK initialization needs a usable display, but stderr from the historical CI exit 101 was not retained, so that result does not establish a specific panic cause. Linux Check uses the command below; Windows runs pnpm directly. [xvfb-run](https://manpages.ubuntu.com/manpages/questing/man1/xvfb-run.1.html), [dbus-run-session](https://manpages.debian.org/unstable/dbus-daemon/dbus-run-session.1.en.html)

```bash
xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" dbus-run-session -- pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Build each platform bundle on its own platform:

```bash
# Linux
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
cd apps/manager-dioxus
dx bundle --release --package-types appimage --out-dir ../../release-artifacts

# Windows (GitHub Actions Windows runner)
# stage-runner.sh generates resources/runner/SteamWrapperRunner.exe
# from target/release/steamwrapper-runner.exe, then runs dx bundle --package-types nsis
```

## Dioxus Native E2E

The 2026-09-08 language and icon changes passed 10 isolated Native E2E executions: the six existing cases, two language/status/error cases, and language save/restart in two separate processes. Final Windows Rust workspace check/test passed (43 tests; the C#-output contract is intentionally ignored by the generic workspace run and passed separately through `winui:contracts`). The two affected Manager packages account for 30 of those tests, including lossless unknown JSON number tokens, nested duplicate-key rejection and the shared 64-level depth limit. TypeScript, E2E tooling, Dioxus check/release build and scoped strict Clippy passed. See [distribution](distribution.md#ci--release-validation) for the independently inspected bilingual NSIS package and its limits.

Native E2E includes `wdio-dioxus-embedded-driver` only under the `e2e` Cargo feature. The production release graph contains neither the WebDriver bridge nor a test server.

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Test scripts create disposable temporary fixtures and point all these environment variables into them:

```text
STEAM_DIR
STEAMWRAPPER_E2E_ROOT
XDG_DATA_HOME
LOCALAPPDATA
```

The fixture includes Chinese/space-containing paths and a local Steam game manifest, deliberately omitting the local cover cache. After launching the real Manager, tests assert that this AppID uses a public Steam CDN cover URL. This checks URL generation and DOM binding, without depending on external image loading.

- Default library and manual-add entry points.
- First-launch installation of the bundled Runner into stable `SteamWrapper/bin/`.
- Local Steam scanning and the game-configuration dialog.
- Profile saving.
- Launch Options retaining the `--appid "123456" -- %command%` contract.

WDIO logs and sanitized fixture artifacts after success or failure are under `apps/manager-dioxus/e2e/artifacts/`, which is ignored; CI uploads them. Tests clean up temporary directories and must not read or modify real Steam configuration.

`scripts/dioxus-service.mjs` retains the locked Dioxus service and adds startup-failure cleanup. WDIO does not call `onComplete` when `onPrepare` fails, so the wrapper first runs that hook to flush app stdout/stderr logs, then exits with the original error. Test apps enable `RUST_BACKTRACE=1`. `test:tooling` uses Node child processes without launching a GUI to verify stdout/stderr attachments for early exit 101 and that a subsequent run after failure writes logs into a fresh output directory. The latter reproduced failure with the old service and passed through the wrapper. These tooling regressions do not replace real Linux GTK/WebKit Native E2E.

<a id="runner-稳定安装验证"></a>

## Stable Runner installation verification

WinUI's [RunnerInstaller](../apps/manager-winui/SteamWrapper.Application/Services/RunnerInstaller.cs) verifies the existing Runner and any existing `profiles.toml` before reporting ready, and checks installation candidates and post-installation locations. A missing profile does not prevent an independent health check. The [location check](../apps/manager-winui/SteamWrapper.Application/Services/SharedDataFileLocation.cs) compares final file-handle paths with logical paths after explicit link resolution. Redirection reports not ready and asks the user to reopen Manager from File Explorer. The UI shows copyable launch options only after the installation service is ready. Neither the Launch Options string contract nor ProfileStore's save algorithm changed.

This implementation added nine [location regressions](../apps/manager-winui/SteamWrapper.Application.Tests/RunnerLocationTests.cs): redirected installed Runner; redirected upgrade candidate preserving the old Runner/manifest/profile; redirected first-install candidate; profile-only redirection; path-query failure; ordinary native handles; real junction upgrades; Chinese/case/extended-prefix handling; and DOS/UNC prefix normalization. Four redirection scenarios first demonstrated the old implementation incorrectly reporting ready, then passed after the fix. The final `mise run winui:test` result for that round was 43/43, with `winui:contracts` also passing. Red/green evidence is under ignored `target/runner-location-tests/`; that round's contracts are in `target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`.

After service tests, the new publication received separate native checks. Launching Manager from the redirected tool environment displayed a location warning and did not show launch options or a copy button after saving. Launching the new Manager through ordinary Explorer saved successfully and generated the same existing launch options. These native checks are recorded separately from service/process evidence and do not replace clean VM or installer validation.

Rust `manager-core` tests cover Runner paths, no replacement when hashes match, missing/corrupt repair, atomic-replacement failure, and preservation of `profiles.toml` / `logs` / `backups` / `cache`. Dioxus Native E2E starts from an empty stable directory and checks that the real Runner is installed and shown as healthy on the settings page.

Runner process tests cover Linux `process_group`, Windows Job Object and `process_name` boundaries on both platforms. `process_name` matches names only and cannot establish ownership when concurrent processes share a name; it is not the default wait mode.

## CI

`v2-ci.yml` defines a Windows / Ubuntu Check matrix for Rust formatting, check, test, Dioxus check/release build, Native E2E and platform Runner process tests. Its Linux bundle job builds an AppImage and inspects the extracted Runner. Windows NSIS build/content checks are in `release.yml`. Workflow declarations do not establish that the latest run passed; verify actual results separately.

<a id="限制"></a>

## Limitations

- Passing local Linux Native E2E does not replace Windows WebView2, NSIS or physical Steam Deck validation.
- Routine automation does not operate real Steam. Live acceptance needs user authorization and recorded restoration. One-click Launch Options apply/restore remains a future product feature.
- Native E2E covers controlled local fixtures, not real Proton, breakaway, Unix daemonize or new-session behavior.
- Dioxus Browser Mode does not fit the current direct Rust service architecture. This project uses Native E2E to cover real UI/service boundaries.

Official references: Dioxus 0.7.10 Desktop / CLI documentation and the embedded-provider/bridge-setup documentation for `@wdio/dioxus-service` 1.0.0.

Local Windows completed Rust workspace, Runner process, Dioxus check/release build and three specs / six Native E2E tests on 2026-09-07. Commit `3d322db` also passed all Windows, Ubuntu and Linux AppImage gates in [full v2 CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282786). See the [development environment record](windows-development.md#local-installation-and-verification-record) for installation, tooling/CI fixes and evidence boundaries. These gates do not replace NSIS, a clean Windows VM or live Steam acceptance; the separately completed local [live-game flow](real-steam-validation.md) has its own explicit scope.
