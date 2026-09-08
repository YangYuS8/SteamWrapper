---
title: "Measured Windows Manager comparison"
description: "Measured Manager behavior and resource comparisons with their evidence boundaries."
---

<a id="measured-windows-manager-comparison"></a>

<a id="windows-manager-实测比较"></a>



Date: 2026-09-07. The initial comparison used the then-current worktree above commit `31a609df027e54bf97156f7698d4a420bc7e3c71`: Dioxus 0.7.10/Rust Manager versus the first WinUI 3/C# Manager. Later component reduction and publish safeguards are recorded separately. Historical runtime data are not new-artifact measurements or a general ranking of the frameworks.

Continue with **WinUI 3 + C# configuration services + independent Rust Runner**, targeting the first Windows release. Because players configure once, close Manager, and launch normally from Steam, configuration reliability, Windows interaction, and stable delivery matter more than Manager's resident performance. Retain Dioxus and its CI until installation, updates, and real Steam acceptance justify switching the default release.

<a id="功能与兼容性"></a>

## Functionality and compatibility

The initial functional comparison reran these checks:

| Check | Result in that comparison | Evidence scope |
| --- | --- | --- |
| `mise.exe run winui:test` | 34/34 passed | C# configuration, services, file protection, and related behavior |
| `mise.exe run winui:contracts` | Passed | Historical Rust configuration → C# single-field edit → complete Rust semantic checks; actual Rust Runner argv/cwd, job/root waiting differences, exit codes, and error logs |
| `mise.exe run windows:rust-test` | 33 passed, 1 ignored by default | The ignored cross-language case passed separately in the preceding gate; seven source-string checks do not establish native UI behavior |
| Dioxus Native E2E | Three specs, six checks passed | Scanning, profile saves, Launch Options text, and stable Runner installation; configured targets were not launched |
| Additional native WinUI interaction | Passed | Other-platform configuration was read-only; saving a Chinese rename preserved every other byte, including empty/multiline arguments, unknown fields, alias keys, and omitted `wait_mode`; created one backup and installed stable Runner |

The first Dioxus E2E attempt used the ordinary binary overwritten by workspace tests, without the `e2e` feature. Rebuilding the correct artifact passed. That prerequisite-artifact error is not recorded as a product crash. Build with `e2e` before future E2E runs to avoid different tasks overwriting shared `target/debug` output.

A second probe supplied both **actual service implementations** with the same synthetic profile containing advanced fields, Chinese text, spaces, quotes, backslashes, empty/multiline arguments, and unknown tables, requesting only a target change. It exposed differences not covered by routine regression tests:

| Same-input probe | Then-current Dioxus/Rust services | Then-current WinUI/C# services |
| --- | --- | --- |
| Change only `target` | Cleared six arguments, set working directory to `.`, changed wait mode to `job`, and cleared process name | Changed only the target line, preserving all other text byte-for-byte |
| Unknown top-level/nested content | Lost all five categories in the probe | Preserved all |
| Save backups | None | One |
| Unsupported `version = 3` | Still allowed saving | Refused the write, preserving original bytes |
| Stable Runner newer/compatible, bundled Runner older | Replaced it with old bundled content based on hash difference | Retained the newer compatible version |

The Runner version probe represented `0.3.0` and `0.2.0` using synthetic files with hash/version manifests. It did not execute them or establish that those product versions were released. Cross-language gates separately verified executable Runner behavior.

These are service-implementation differences. The old [save service](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/manager-core/src/lib.rs) reconstructs Profile, [configuration serialization](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/config.rs) regenerates the file, and [Runner installation](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/manager-core/src/runner.rs) selects replacement by hash. Dioxus can fix these behaviors; they are not caused by WebView or Rust. C# safeguards come from the new implementation/tests, not from WinUI alone.

<a id="依赖精简前的资源测量"></a>

## Resource measurements before component reduction

The [comparison script](https://github.com/YangYuS8/SteamWrapper/blob/v2/scripts/windows/Measure-ManagerComparison.ps1) measured sequentially after both builds/functional tests completed and test windows exited. Both used the same isolated directory with 10 profiles, 10 Steam manifests, local covers, and the same release Runner; the real Steam library was untouched.

The machine ran Windows build 26200, an i7-12700H (20 logical processors), and 31.62 GiB of OS-visible physical memory. Dioxus children used WebView2 145.0.3800.97. Measurements used release artifacts built earlier that day; the script did not rebuild them. Binary SHA-256, timestamps, and machine information are in `metadata.json`. A worktree commit ID alone does not establish correspondence between binaries and uncommitted source.

Each app had one warm-up and six measured runs. Order within pairs was randomized and balanced. After a main-window handle appeared, the script waited five seconds and sampled the complete process tree at seconds 5/6/7. Dioxus includes its WebView2 children, not unrelated Edge/Codex processes.

| Metric | WinUI/C# before reduction | Dioxus/Rust |
| --- | --- | --- |
| Uncompressed application directory, same Runner included | 226.23 MiB / 522 files | 6.87 MiB / 4 files, plus system WebView2 |
| Idle private bytes across process tree, median | 83.02 MiB | 267.91 MiB |
| Sum of working sets, median | 158.93 MiB | 461.73 MiB |
| Idle process count, median | 1 | 7, including WebView2 children |
| Main-window handle appearance, median | 339.82 ms | 26.48 ms |
| Main-window handle appearance, min–max | 324.35–352.88 ms | 24.99–28.84 ms |

All six measured runs per app completed; all 14 launches/exits including warm-ups were normal, and fixture configuration SHA-256 never changed. Both EXEs use the GUI subsystem, so console windows were not counted as main windows. These startup numbers remain a window-creation proxy.

Interpretation limits:

- Handle appearance measures window creation with 10 ms polling, not first frame or interactivity; do not call it UI loading speed.
- Private bytes measure private allocation, not resident physical memory. Summed working sets may count shared pages more than once.
- Default pages and window sizes differ. This compares existing product startup/idle behavior, not identical-layout/functionality framework experiments.
- The machine was warm with OS/other-app background activity. System caches were not cleared; cold startup and a clean VM were not measured.
- Sizes are uncompressed application directories with the same Runner. Dioxus excludes shared system WebView2, while WinUI includes .NET/Windows App SDK. Their ratio is not a total installation-cost ratio.

<a id="后续组件精简与发布验证"></a>

## Later component reduction and publish validation

Manager uses the component set corresponding to Windows App SDK 2.4.0: direct references to `Microsoft.WindowsAppSDK.WinUI` 2.3.6 and `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6, retaining SDK.BuildTools 10.0.26100.7705. The explicit InteractiveExperiences pin prevents fallback to the WinUI package's minimum 2.1.3 dependency. All retained dependency versions/hashes match the original lockfile. These are selective component references, not manually deleted published DLLs. Microsoft supports the packages and their self-contained deployment. [Official component-package explanation](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003)

| Publish layout check | Original umbrella-package artifact | Final component artifact |
| --- | --- | --- |
| Uncompressed directory | 237,216,420 bytes / 226.23 MiB | 179,511,987 bytes / 171.196 MiB |
| Files | 522 | 457 |
| Unused AI/ML/Search/Widgets/DWrite files | Included | Excluded from publishing, 65 fewer files |

Native resource index, .NET, WinUI, picker projections, Runner, and manifest are present. Runner hashes match and all three Storage.Pickers activation registrations still point to the bundled `Microsoft.WindowsAppRuntime.dll`. Locked restore and Release self-contained publish passed. The final artifact separately passed sandbox native-window launch, configuration loading, picker open/cancel, saving, and stable Runner readiness; see [preview validation](/SteamWrapper/project/validation/winui/). **The six-round memory/startup measurements above were not rerun.**

Publishing now writes to a fresh staging directory, validates it, then replaces `target/winui/publish`. Regression first observed the old script retaining a unique sentinel file, then passed five checks: real publishing removes stale files, missing resources preserve the previous output, a locked candidate triggers rollback, successful replacement contains new files only, and out-of-bounds paths are rejected. Directory operations stay inside repository `target/winui`. A running preview prevents replacement, and failed candidates remain for diagnosis. Ordinary error rollback is verified; directory renames are not a power-loss transaction.

<a id="方案选择"></a>

## Choosing the design

The primary reasons for WinUI are Windows-first scope and a native configuration interface. Microsoft positions WinUI 3 as a native Windows desktop framework using C#/C++ and XAML; Dioxus Desktop combines native Rust code with a system WebView. Both can call Windows APIs, and Dioxus does not automatically add a Node runtime. [Official WinUI overview](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/), [official Dioxus Desktop overview](https://dioxuslabs.com/learn/0.7/guides/platforms/desktop/)

The C# configuration services now meet more complete fidelity/write-protection requirements and passed actual Rust Runner consumption tests. Completing this design follows the established Windows direction better than returning to repair the old management chain. Cross-language contracts are an ongoing maintenance cost, so retain those gates. This comparison produced no evidence that a Rust FFI/helper or Runner rewrite is needed.

WinUI's main costs are self-contained dependency size and Windows-specific build/delivery. Later component selection removed unused ONNX, DirectML, and other dependencies, but the final artifact still measured 171.196 MiB. Package-size improvement does not establish startup/memory improvement. Dioxus retains value if Linux/SteamOS becomes a priority again, for Rust management-model reuse, and for smaller app-supplied files.

Both share independent Rust Runner. Changing Manager does not directly improve Steam playtime, Job waiting, or game compatibility; these still need Runner and real Steam verification.

Later real galgame comparison traced the earlier OS Error 3 to the development host writing AppData into a private view inaccessible to ordinary Steam. After opening Manager through Explorer and installing to the normal location, the same command passed a Unity galgame Steam → Runner → game flow, ordinary exit, and playtime update. Added location checks passed 43/43 C# tests, cross-language/Runner contracts, and native review in both launch contexts. Runner and the Launch Options format were unchanged. The issue cannot be attributed to UI framework or Job wait mode. At that point, further real custom launchers/engines, clean Windows 11 installation/update/uninstall, and complete native input/accessibility acceptance remained. The results support the technical direction, not a declaration that a formal Windows release is ready. See [real Steam validation](/SteamWrapper/project/validation/steam/) and [preview validation](/SteamWrapper/project/validation/winui/) for later evidence.

<a id="复查入口与本机证据"></a>

## Rechecking and local evidence

```powershell
mise.exe run winui:test
mise.exe run winui:contracts
mise.exe run windows:rust-test
# Actual publish plus four isolated directory-protection checks: five total.
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
# For Dioxus Native E2E, first build with --features e2e as described in testing.md,
# then run the pnpm tests.
# Once both release artifacts are ready and other tests have ended,
# a new set of resource measurements can be generated:
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Measure-ManagerComparison.ps1
```

- Functional gates: `target/comparison-gates-eb091a2741314f3299d7c10db775b534/README.md` and logs.
- Cross-language/real Runner: `target/winui-contracts/67f27c0007cc4229af7e2407d15efe4b/results`.
- Same-input service probe: `target/comparison-config/evidence/observations.json`, `rust-result.json`, `csharp-result.json`, and both saved files; temporary probe source in `target/comparison-config`.
- Native single-field save: `target/ui-comparison-5523059ad7ac4b60a91e86f7ee931cee/before.toml`, `ui-result.json`, and the isolated saved file.
- Resource measurement: `target/manager-comparison/e9cb1333d8c64656b25f50e9536779a0`.
- Final component publish: `target/winui-component-study/integrated-publish.json`; publish regression: `publish-regression-before.log` and `publish-regression-after.log` in that directory.

`target` evidence is local temporary output and is not committed. This report, resource-measurement script, and publish-regression script remain in the repository. Component-comparison sizes above retain historical values; the new artifact after location checks was 179,515,507 bytes / 457 files, without repeated resource benchmarks. Steam playtime had been accepted for one game at that stage; clean Windows 11 installation acceptance remained incomplete. The live validation document records later game coverage separately.
