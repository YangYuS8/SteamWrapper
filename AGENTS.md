# SteamWrapper v2 — Agent Guide

## Product and direction

Configure a game once in Manager, then launch it normally from Steam. Manager is configuration UI only; Steam calls the independent, headless Runner. Successful daily launch must not show Manager.

Windows is the current product priority. WinUI 3/C# is the only Manager implementation, with C# configuration services in `apps/manager-winui` and an independent Rust Runner connected by the existing TOML/CLI contracts. Read [the Windows design](docs/src/content/docs/project/design/windows-v2.md) for implementation work. Dioxus, its Rust management layer and its UI/build/release workflows have been removed. The scoped Windows 11 24H2 x64 core acceptance is complete for first stable delivery; v0.2.7 is the first stable Windows release, with its exact tag workflow, public downloads and project-signed update feeds verified. Future releases still require these gates. Manager runs in the Windows account used for Steam. A fresh-account primary sign-in, two-user GUI, cross-user Run as and multi-monitor hardware matrix are not established by the same-primary-SID ordinary-permission test; preserve these limits and the failed cross-user evidence. Linux / SteamOS expansion is deferred; preserve existing Rust Runner compatibility and process CI.

## Working agreement

- `main` is the canonical development branch for v2. Start focused feature branches from `main` (use `codex/` for agent-created branches) and target pull requests to `main`; keep `v2` as a retained migration reference. Check `git status --short --branch` before edits and before delivery; preserve unrelated changes. Do not commit, push, merge, or rewrite history unless authorized by the user.
- Read the affected source and tests. Expand to callers or architecture docs when the impact crosses boundaries; no whole-repository reading or full test run is required for every edit.
- Keep development tool versions reproducible using the repository manifests; keep the .NET pin in `mise.toml` consistent with `global.json`. mise is an optional convenience for the maintainer, not a contributor requirement. Direct SDK, pnpm and PowerShell commands are supported; see [Windows development](docs/src/content/docs/development/windows.md). System MSVC/SDK components use the official installer, directly or through the optional mise task.
- Use source, manifests, scripts and CI for implementation facts. Documentation records intent; roadmap checkboxes and old results are not current test evidence.
- Carry authorized work through the relevant verification and fix failures caused by the change. Routine implementation choices and isolated local tests do not need repeated approval. Ask only when missing information materially changes scope, compatibility, or authorization; continue independent work meanwhile.
- Current user instructions take precedence over repository and skill defaults, within system and tool constraints. A request to research a migration authorizes a concrete assessment, not removal of the current implementation. A later request to implement it does not require re-approving the same stack choice.
- If a file instruction blocks progress, link the file, quote the applicable rule, and explain the specific conflict. Do not invent an approval requirement from a guideline.
- Delegate bounded independent research or review when it saves time or improves quality. Report concisely in the user's language: result, relevant verification, and actual limitations.

## Compatibility contracts

Preserve the TOML serialization, stable data locations, Runner CLI meaning, and `%command%` position when changing UI frameworks:

```text
profiles.toml
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Windows data stays under `%LOCALAPPDATA%\SteamWrapper\`: `profiles.toml`, `bin\SteamWrapperRunner.exe`, `logs\`, `backups\`, `cache\`.

Existing Linux data stays under `$XDG_DATA_HOME/SteamWrapper/`, falling back to `~/.local/share/SteamWrapper/`; its Runner is `bin/steamwrapper-runner`.

Launch Options must reference the stable Runner, never Manager, a versioned package location, or a temporary extraction path. Runner install/repair only replaces its own binary and preserves user data.

## Code boundaries

| Location | Responsibility | Boundary |
| --- | --- | --- |
| `crates/core` | Profile/TOML, Steam metadata/covers, Launch Options | No UI framework, UI event logic, or platform process APIs |
| `crates/runner` | CLI, target launch, platform waiting, runtime logs | Native, headless, independent of Manager and GUI assets; no background service |
| `apps/manager-winui/SteamWrapper.Manager` | Native Windows preview UI, pickers and clipboard | Calls C# Application services; no game launch/wait behavior |
| `apps/manager-winui/SteamWrapper.Application` | Profile editing, local Steam discovery, stable Runner installation | No GUI dependencies or Rust bridge; TOML/CLI compatibility is tested across languages |
| `apps/deployment-windows` | Manager launcher, installation lease, manifest/journal and repair/rollback/uninstall | No game launch or stable Runner replacement; only explicitly selected uninstall restoration/data cleanup may change the narrowly defined Steam/data files below; Inno shares this protocol |

Use English as the default project language, with complete Simplified Chinese localization and player-friendly configuration. With no saved UI language preference, follow the supported system UI language; unsupported languages fall back to English. Preserve an explicit saved choice, invariant service diagnostics, and user-entered game names, paths and protocol identifiers when switching languages. Maintain matching English and `zh-CN` documentation and resource keys. Keep friendly missing-cover placeholders. The original SteamWrapper icon combines a copper gear and a connecting rod; regenerate its PNG/ICO derivatives with `pnpm brand:generate` (or `mise run brand:generate`). WinUI uses the canonical `assets/brand/` files. Do not imply endorsement by Rust or Steam.

Keep Runner lifecycle fixes in Runner/platform modules with real process tests. Do not infer Job Object, process-name, process-group, Proton, or windowless guarantees from UI tests or another platform's results.

pnpm is development tooling for reproducible brand assets and the static Astro/Starlight documentation site. Do not reintroduce Dioxus, the retired Tauri/React stack, a Node UI runtime, Electron, or Python runtime components. The WinUI design does not add a Rust FFI bridge or management helper. C# implements the existing file contract; run `pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test` and `pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1` (or their `winui:test` / `winui:contracts` mise tasks) for relevant changes. Preserve unedited fields and reject unsafe writes; missing legacy `wait_mode` means `root`, while new Windows profiles default explicitly to `job`. Preserve the TOML syntax edits and readonly fallback for unsupported layouts; do not replace them with whole-model serialization.

## Data and Steam safety

- Covers are local-first and offline by default. Prefer custom Steam art, then local library-cache images. Only an explicit preference enables official Steam CDN requests for AppIDs discovered locally; keep HTTPS host/redirect checks, request/image limits and the quota-limited `cache/covers/` directory. Disabling cancels downloads; clearing touches only SteamWrapper's downloaded covers. Preserve custom art, Steam cache/game files and profiles; missing, unreadable or unavailable images retain placeholders. Do not expand into third-party metadata services, account lookups or user-data uploads. See the roadmap for the remaining native UI/player acceptance gates.
- No DLL injection, Steam/game binary patches, DRM bypass, hidden services, or user-data upload.
- First installation may select an empty directory on a fixed local drive, defaulting to `%LOCALAPPDATA%\Programs\SteamWrapper`; registered updates and repairs stay at that validated location. Installation is per-user and independent of the stable data root. Relocation means Manager-only uninstall preserving data, then a new installation; do not silently migrate files. Preserve unknown files and quarantined partial stages; never force-close Manager/Runner/games. Test with `Test-WinUIInstaller.ps1` and `Test-WinUIInstallerOptions.ps1` against isolated roots. Production signing and authenticated updates require real configured trust; do not invent keys/certificate pins or broaden the legacy portable release contract silently.
- Application updates use the project public keys in `packaging/windows/update-trust.json`, signed update metadata and exact installer hashes; Windows Authenticode is optional. Keep the player flow simple, automatic checks off by default, and the seven immutable release assets separate from the renewable update index. Only advertise verified mirrors. Test installation handoff with `Test-WinUIUpdateHandoff.ps1`; never execute a production installer against a test root or silently install over a portable directory.
- Default uninstall removes only owned Manager program files, shortcuts and registration. Seven independent, default-off choices may remove recognized SteamWrapper Launch Options, downloaded cache, logs, preferences, profiles, exact profile backups, and verified stable Runner files. Profiles/Runner deletion requires Steam to exit normally and a complete account scan with no remaining Runner references. Hold existing installation/data locks; preserve busy or unknown files, unverified Runner bytes, reparse points, Steam restoration backups and `updates/trust-state.json`. Never recursively clear a data root or delete game/save files.
- The explicit uninstall restoration choice may clear only the exact generated Launch Options command targeting this data root's stable Runner and matching AppID, after checking Steam is stopped and backing up each affected account file. Preserve every other byte and reject concurrent changes. Leave custom/unrecognized options alone. No old value was recorded when users manually pasted a command, so clearing our recognized command is not restoration of unknown historical arguments. General automatic apply/restore remains separate work; generating text is not applying it.
- Automated regression and previews use disposable Steam/user-data fixtures. Live Steam acceptance requires explicit user authorization for the real library; that authorization can persist across the agreed test session. Do not patch, replace, repair, uninstall, or clear game files. Record selected-game Launch Options before changing them, restore them after the test, and verify game-file integrity. Stop on unresolved save/cloud conflicts; do not choose which user progress to overwrite. Routine previews use `Invoke-WinUI.ps1 -Action Sandbox`.
- For authorized live Windows acceptance, open Manager from ordinary Explorer. A development host can redirect AppData writes into its private file view even when child processes report no package identity. Verify actual file locations; `File.Exists` or direct Runner success in that view does not prove Steam can access them. Keep Launch Options on the stable shared path, never a host package cache.
- Never print, commit, or copy credentials, tokens, or `.env` contents. Keep generated user data, logs, staged binaries, and test artifacts out of commits.

## Verification and task references

For behavioral changes, add a focused regression test and observe failure for the intended missing behavior before implementation. Documentation and cosmetic-only edits need proportionate review, not artificial source-string tests. Start with the affected test gate; use [Testing](docs/src/content/docs/development/testing.md) to choose further checks. Full CI/release gates remain required for their workflows; do not weaken them to make a local task pass.

Stop repeating successful checks unless new changes or unresolved concerns justify it. If a prerequisite is missing, report the command and blocker, then complete work that does not depend on it. Distinguish not run, blocked, failed, and passed.

Read these references only for the relevant task:

- Service or data boundaries: [Architecture](docs/src/content/docs/development/architecture.md).
- Windows requirements and implementation gates: [Windows v2 design](docs/src/content/docs/project/design/windows-v2.md). Stack/tooling evidence: [Technology stack](docs/src/content/docs/development/stack.md), [WinUI 3 assessment](docs/src/content/docs/project/decisions/winui3.md).
- Test commands and platform evidence: [Testing](docs/src/content/docs/development/testing.md).
- Packaging, stable Runner installation, update/uninstall: [Distribution](docs/src/content/docs/development/distribution.md). Stage the current-platform Runner and inspect the actual bundle; Linux success is not Windows/Steam Deck evidence.
- Priorities and deferred scope: [Roadmap](docs/src/content/docs/project/roadmap.md).

Update affected current docs when behavior, architecture, test commands, or delivery boundaries change. Keep current implementation, proposed direction, and verified platform results distinct.

## Documentation site

The canonical documentation lives in `docs/src/content/docs/`; English pages use root routes and complete Simplified Chinese counterparts use `zh-cn/` with matching paths. Use `pnpm docs:check` and `pnpm docs:build` (or the equivalent mise tasks) for documentation/site changes. The build checks actual static links, anchors, assets and search languages. Keep player guides separate from developer references and dated project evidence. GitHub Pages publishes only from `main` at `/SteamWrapper/`; `v2` and PR checks do not deploy. `docs/README.md` describes the source layout.
