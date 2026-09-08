<a id="windows-开发环境mise"></a>

# Windows development environment (mise)

English | [简体中文](windows-development.zh-CN.md)

Use the root `mise.toml` to manage project tools, `global.json` to select the .NET SDK, and `.vsconfig` to declare MSVC/Windows SDK components. The WinUI Manager is in `apps/manager-winui`; the existing Dioxus toolchain remains available for migration-baseline checks. The standalone template smoke project stays under ignored `target/toolchain-smoke/` for environment diagnostics.

<a id="版本与管理范围"></a>

## Versions and management scope

| Tool | Pinned version | Management |
| --- | --- | --- |
| .NET SDK | 10.0.400 | mise core; SDK roll-forward disabled in global.json |
| Rust | 1.98.1, rustfmt/clippy | mise invokes existing rustup; Windows uses the MSVC host |
| PowerShell | 7.6.5 | mise; tasks do not depend on Codex private runtime paths |
| Node / pnpm | 24.18.0 / 11.10.0 | mise; aligned with existing CI / packageManager, for Dioxus E2E and brand asset generation/checks |
| Dioxus CLI / just | 0.7.10 / 1.58.0 | mise; official Dioxus GitHub binaries |
| WinUI CLI template | 0.0.6-alpha | `windows:templates` installs the official NuGet template; this is its preview version |
| WinUI smoke dependencies | Windows App SDK 2.4.0, SDK.BuildTools 10.0.26100.7705, WinApp 0.3.1 | The verification script pins direct package references independently of the machine-wide Windows SDK |
| WinUI Manager components | WindowsAppSDK.WinUI 2.3.6, InteractiveExperiences 2.1.6, SDK.BuildTools 10.0.26100.7705 | Windows App SDK 2.4.0 component set; NuGet locks all transitive dependencies |
| MSVC / Windows SDK | VC.Tools.x86.x64 / Windows11SDK.26100 | `windows:setup` invokes Microsoft's official installer; these are system components |

`mise.lock` records available Windows x64 download URLs and hashes. Core .NET/Rust still delegate to the official installation script/rustup; the lockfile is not a complete offline mirror. The MSVC bootstrapper uses a verified 18.9.1 URL/SHA-256, while its components resolve through Microsoft's channel. mise cannot isolate or byte-pin every system component.

The .NET core backend uses a shared SDK root. Pinning a mise version alone does not replace .NET's SDK resolver, so a matching `global.json` is also provided. [mise .NET management](https://mise.jdx.dev/lang/dotnet.html), [Rust management](https://mise.jdx.dev/lang/rust.html)

<a id="首次准备"></a>

## Initial setup

Run these commands from a Windows terminal at the repository root:

```powershell
mise trust
mise install
mise run windows:setup
mise run windows:templates
mise run windows:doctor
mise run windows:winui-smoke
```

`mise trust` trusts only the reviewed configuration in this repository. `mise install` installs its declared tools. The system-component task verifies the bootstrapper's SHA-256 and Microsoft signature, then installs the compiler/SDK and required dependencies from `.vsconfig`. It returns immediately when the full component set is already installed. The full Visual Studio IDE is not required. [Microsoft MSVC installation](https://learn.microsoft.com/en-us/cpp/overview/acquire-msvc?view=msvc-170)

Microsoft's installer requires normal UAC permission. The script uses `--norestart` and never restarts automatically. Exit code 3010 explicitly means installation succeeded but a restart is required; it is neither an installation failure nor evidence that the restart has happened. [Official installer parameters](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=visualstudio)

`windows:doctor` locates the required components with vswhere and loads Microsoft's Developer PowerShell. It does not permanently change PATH or print the full environment. mise supplies `pwsh`; tasks do not depend on Windows PowerShell 5.1 or Codex PATH injection. [Developer PowerShell](https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=visualstudio)

<a id="日常命令"></a>

## Daily commands

WinUI development entry points:

```powershell
mise run winui:test       # Profile safety, local Steam, Runner installation and UI language services
mise run winui:contracts  # C# / Rust round trips and controlled real Runner parent/child processes
mise run winui:build      # Release XAML compilation; stage the current Rust Runner
mise run winui:publish    # Self-contained target/winui/publish directory, including native resource indexes
mise run winui:sandbox    # Publish and open the native preview with disposable Steam/user directories
```

Each project's `packages.lock.json` pins NuGet dependencies, and daily commands use locked restore. The service project explicitly lists the win-x64 runtime identifier to prevent lockfile drift when alternating between tests and UI publication. Use `--force-evaluate` only when updating dependencies, and review the lockfile changes.

Manager now references the component packages above instead of the Windows App SDK 2.4.0 umbrella package, retaining the same component versions and hashes. InteractiveExperiences is explicitly pinned to 2.1.6 to avoid falling back to 2.1.3. AI, ML, Search, Widgets, DWrite and their unused publication files no longer enter new artifacts. The independent environment smoke still uses the umbrella package.

Manager uses Windows App SDK's [native picker API](https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers). The project is maintained directly and does not depend on installing the alpha template. `EnableMsixTooling` generates the application PRI resource index; `WindowsPackageType=None` and disabled package generation/signing prevent registration of an MSIX debug identity. Publication checks include Manager PRI, .NET, WinUI and Runner. Compilation alone does not prove that XAML can load at startup.

`winui:publish` first writes into a fresh `target/winui/publish-staging-<id>` directory. It validates the Manager executable/assemblies, PRI, .NET, WinUI, picker projections, Runner and manifest, then replaces `target/winui/publish`. Directory operations stay within this repository's `target/winui`, reject reparse paths, and serialize replacement with a publication lock. A preview running from the destination directory prevents replacement. Validation failure keeps the old version; an ordinary replacement failure restores the old directory. Blocked recovery or cleanup reports the retained location. Directory renames are not a power-loss transaction, and failed candidates remain available for investigation.

The publication regression runs the real publish command, then tests recovery in isolated directories without another test framework:

```powershell
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
# Check only directory replacement/recovery, without rebuilding:
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1 -SkipBuild
```

The full command contains five checks: no stale sentinel file, preservation of the old version when a resource is missing, rollback when a candidate is locked, successful replacement containing only new files, and rejection of out-of-scope paths. All test files stay under `target/winui`. Close any preview running from the publish directory before testing.

Each sandbox creates example Steam manifests, LOCALAPPDATA and XDG_DATA_HOME under `target/winui/sandbox/<id>` and sets STEAMWRAPPER_E2E_ROOT. Example games contain no real game executable; choose a controlled test executable to exercise configuration. Outside the sandbox, the artifact attempts to use normal user-data locations; its actual file view still needs the checks below. Routine automation uses the sandbox entry point. Do not copy the EXE out of the complete publication directory.

The UI defaults to English and offers English / 简体中文 in the sidebar. Both Managers store `language` in a separate `SteamWrapper/ui-settings.json` beside `profiles.toml`: canonical values are `en-US` and `zh-CN`. `en` and `zh-Hans` are accepted aliases, with whitespace trimming and case-insensitive matching; missing or unknown values default to English. Successful preference writes refresh application-owned labels, dynamic controls and service/status messages without reloading the form or discarding edits. Failed writes keep the current language and the original settings file. Unknown JSON fields are preserved; malformed, duplicate-key, non-object or oversized settings are not overwritten. User names, paths, arguments, protocol identifiers and diagnostic logs are not translated. Native OS dialogs retain system-owned wording.

WinUI's English neutral resources and Simplified Chinese satellite resources live under `SteamWrapper.Application/Localization`. The explicit .NET resource culture is independent of the OS language and does not change the process's global culture. When inspecting a published artifact, check `zh-CN/SteamWrapper.Application.resources.dll` as well as the existing native resources. [ResourceManager culture-specific lookup](https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-resources-resourcemanager-getstring)

Brand assets are generated from `assets/brand/steamwrapper.svg`. After editing that source, run `mise run brand:generate`, then `mise run brand:check` to verify SVG, PNG, ICO and bundled copies. Do not edit exported icons separately.

Legacy implementation and environment diagnostics:

```powershell
mise run windows:doctor       # Tool versions, link/cl and SDK paths
mise run windows:rust-test    # Current Rust workspace tests
mise run windows:verify       # Rust / Dioxus builds and isolated Native E2E; stop on failure
mise run windows:winui-smoke  # Self-contained publication of the independent XAML smoke project
```

`windows:verify` installs frozen pnpm dependencies, stages the bundled Runner, and runs the existing quality gates. It does not build NSIS, publish a release, or operate real Steam automatically. Existing `just` commands remain available. These Windows entry points use PowerShell directly, without Bash cleanup scripts.

For individual tool commands:

```powershell
mise.exe exec -- dotnet --version
mise.exe exec -- cargo test --locked -p steamwrapper-runner
```

The local PowerShell `mise` activation function consumes the bare `--` separator in `exec` calls, so use `mise.exe` for these individual commands. `mise run ...` is unaffected. The user's PowerShell profile was not changed to work around this.

<a id="共享数据路径与真实-steam-验收"></a>

## Shared data paths and live Steam acceptance

Manager and the Runner launched by Steam must see the same `%LOCALAPPDATA%\SteamWrapper\profiles.toml` and `bin\SteamWrapperRunner.exe`. On this machine, a shell or Manager launched from Codex's process environment could resolve a literal normal AppData path into the Codex package's private `LocalCache`. File existence, matching hashes and direct execution did not prove that ordinary Steam could access it. A shell or Manager reporting no package identity also did not rule out the different file view. The discrepancy was confirmed through final file-handle paths.

The [shared-file location check](../apps/manager-winui/SteamWrapper.Application/Services/SharedDataFileLocation.cs) verifies the existing Runner and any existing profile before reporting Runner ready, and verifies the installation candidate and installed files during installation. If the final handle path differs from the logical path after explicit junction/symlink resolution, the service reports not ready and asks the user to reopen Manager from File Explorer. The profile-editing algorithm and Launch Options format remain unchanged. The comparison accepts legitimate links, case differences and `\\?\` / UNC prefixes. A missing profile does not prevent an independent Runner health check. This proves shared-location consistency, not successful live Steam launch.

With user authorization, follow the ordinary player launch path for live acceptance:

1. Record the selected game's original launch options and establish file-integrity and save-protection baselines. Stop on unresolved cloud conflicts.
2. Close Manager. Open the full repository `target\winui\publish` directory from normal Windows File Explorer's address bar, then double-click `SteamWrapper.Manager.exe`. Keep the publication directory complete. Invoking a process-launch API from a Codex shell is not evidence of leaving its file view.
3. Configure the profile and install the stable Runner in that Manager. Confirm no shared-location warning. Paste the existing-format launch options into Steam, close Manager, and launch the selected game from Steam. Record Runner/game processes, the title screen, Steam status after exit, and displayed playtime separately.
4. Restore the original launch options and recheck game files and original saves. Steam returning to “Play” or reporting an up-to-date cloud state does not replace file-integrity verification.

Daily development continues to use the mise and sandbox commands above. One live game acceptance through normal Explorer on this machine does not establish clean Windows VM, installer, update or uninstall acceptance.

<a id="winui-验证的边界"></a>

## Limits of WinUI verification

Microsoft's CLI template can create a WinUI/XAML project through .NET. Version 0.0.6-alpha unconditionally updates three NuGet packages in its post-creation actions; `UseLatestWindowsAppSDK=false` does not constrain those actions. After generation, the script pins actual package references and the minimum OS version with XML before publishing. Template arguments alone do not prove that dependency versions are pinned. [Official WinUI quickstart](https://learn.microsoft.com/en-us/windows/apps/get-started/start-here)

The smoke uses `net10.0-windows10.0.26100.0`, x64, unpackaged deployment, and self-contained .NET/Windows App SDK, without trimming. It verifies XAML compilation and the publication directory. It does not install or launch MSIX, enable Developer Mode, launch games, or establish clean-system runtime or native-interaction acceptance. The actual Manager has its own project, package locks, services and cross-language tests.

<a id="本机安装与验证记录"></a>

## Local installation and verification record

2026-09-07: the mise tools above were installed. Build Tools reported registration version `18.9.12112.369`, with MSVC `14.51.36231` and Windows SDK `10.0.26100.0` detected. The installer had returned 3010; the user subsequently restarted. This verification confirmed that .NET, MSVC, the SDK and project tools were available.

Completed local checks:

| Check | Result |
| --- | --- |
| `mise install`, repeated component setup, `windows:doctor` | Passed; installed components were not replaced again, and the current development shell was usable |
| WinUI self-contained publication after dependency pinning | Passed; non-empty EXE, `coreclr.dll` and `Microsoft.UI.Xaml.dll` present; trimming disabled |
| Fresh publication after Manager component reduction | Passed; 171.196 MiB / 179,511,987 bytes / 457 files; no stale AI/ML dependencies; Runner manifest hash matched |
| `Test-WinUIPublish.ps1` | Five checks passed; the old publication first reproduced the stale-sentinel failure, followed by new-publication and recovery verification |
| Shared-data location protection: `winui:test` / `winui:contracts` | 43/43 C# tests passed, including nine new location regressions; Runner/profile redirection first reproduced failures, then passed after the fix; native handle and real junction positive cases passed; cross-language and controlled Runner contracts passed |
| `cargo fmt --all -- --check`, `cargo check --locked --workspace` | Passed |
| `cargo test --locked --workspace` | All passed, including six Windows Runner tests |
| Frozen pnpm install, E2E TypeScript check | Passed |
| `dx check`, `dx build --release`, release Runner staging | Passed; Dioxus output at `target/dx/SteamWrapperManager/release/windows/app` |
| Cargo `e2e` feature build, isolated Native E2E | Passed: three specs / six tests |
| mise task validation, PowerShell AST, JSON/TOML version consistency, documentation links and diff | Passed |

Post-installation verification reproduced and fixed three existing Windows tooling/test issues: a hardcoded Linux wait mode in Manager service tests, EINVAL from directly launching `pnpm.cmd` in Native E2E, and a hardcoded `/` in a Runner path assertion. pnpm also explicitly disabled the Edge/Gecko download scripts unused by the current embedded provider, retaining esbuild. Product runtime logic and assertion requirements were not weakened.

The full verification task initially stopped on failure. After the final path-assertion fix, only the affected TypeScript and E2E checks were repeated. Other successful checks were not rerun. Logs remain in ignored `target/windows-verify.log`, `target/windows-runner-test.log`, `target/windows-e2e.log` and `target/winui-toolchain-build.log`.

Later implementation passed C# profile/service tests and `winui:contracts`: Rust compared complete semantics after C# edited a single field, and the real Runner verified Chinese paths, exact argv/cwd, job/root waiting differences, exit codes and missing-target logs. Evidence is under ignored `target/winui-contracts/`; native preview records are in [first-slice acceptance](winui-preview-validation.md). These fixtures alone do not establish a new installer, clean-system runtime or live Steam playtime acceptance. Live results are recorded separately below.

After Native E2E startup-failure logging was completed, local Windows again passed three specs / six tests, with exit code 0 and no residual Manager process. The log is `target/native-e2e-wrapper-1f429cd320e1437f98e8be2331c68c0f/native-e2e.log`.

The user-authorized live galgame `The NOexistenceN of you AND me` (AppID 2873080) completed the local Steam flow. On 2026-09-07 at 12:46:03, Steam launched Runner and the game. Following a normal exit from the title screen, Steam recorded Runner, the game and Unity child process all exiting with code 0 at 12:53:33. The UI returned to “Play,” cloud status was up to date, displayed total playtime rose from 11.2 to 11.4 hours, and the original empty launch options were restored. The earlier OS Error 3 corresponded to Codex's private AppData view. Opening the same Manager through normal Explorer and installing into the real stable directory succeeded with the unchanged launch-options format. Final SHA-256 checks matched the initial baseline for 35/35 game files and 4/4 original saves; final save-file handle paths also showed no redirection. See [live Steam validation](real-steam-validation.md).

The publication containing location protection received native checks in both launch contexts. Launching from the redirected tool environment displayed a location warning; saving did not show launch options or a copy button. Opening the new Manager from normal Explorer (PID 13644, parent PID 11316 `explorer.exe`) saved successfully and generated exactly the existing command format. This is local window/shared-path evidence. Clean Windows VM, installer and uninstall boundaries remain untested.

Component-reduction and publication-protection evidence is in `target/winui-component-study/integrated-publish.json`, `publish-regression-before.log` and `publish-regression-after.log`. This work verified builds, layout and publication recovery. The final reduced artifact separately passed sandbox native-window, profile loading, picker open/cancel, save and stable-Runner readiness checks. Six rounds of startup/memory measurements from the old 226.23 MiB artifact were not treated as measurements of the new artifact, and a clean Windows system was not tested. Windows CI runs `Test-WinUIPublish.ps1` before uploading the preview, completing publication and all five publication regressions.

Commit `3d322db` passed both [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718) and the [full v2 gates](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282786). The latter includes Windows/Ubuntu Native E2E, independent platform Runner process tests, Linux AppImage building, actual extraction inspection and upload. Missing Linux `libxdo`, a headless Native E2E environment and a relative-path error in AppImage extraction verification were fixed and confirmed by complete runs on the new commit; no gates were weakened. CNB synchronization succeeded. These records correspond to their code commit, not to an assumed successful run for later documentation-only commits.

The 2026-09-08 language implementation passed the final `mise run winui:test` with 59/59 tests, including 10 new localization/preference cases. The initial English-default regressions failed against the old Chinese messages before implementation. UTF-8 BOM preference compatibility and nested duplicate-JSON-key rejection also failed before their fixes. Coverage includes both resource catalogs and format placeholders, nested service messages in both languages, invariant diagnostics/user data, canonical language persistence, unknown JSON fields, malformed/duplicate/oversized settings, and BOM input. Cross-language/Runner contracts and the final self-contained publish passed, including the `zh-CN` satellite resources. The [later language validation](winui-preview-validation.md#later-language-work) records final native switching, restart persistence, preserved inputs/profile bytes, and application/window icon checks on a disposable fixture; it does not replace clean-system or live Steam acceptance.
