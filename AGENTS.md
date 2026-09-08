# SteamWrapper v2 — Agent Guide

## Product and direction

Configure a game once in Manager, then launch it normally from Steam. Manager is configuration UI only; Steam calls the independent, headless Runner. Successful daily launch must not show Manager.

Windows is the current product priority. The C#/XAML WinUI 3 preview and its C# configuration services live in `apps/manager-winui`, with an independent Rust Runner connected by the existing TOML/CLI contracts. Read [the Windows design](docs/windows-v2-design.md) for implementation work. Dioxus 0.7.10 and its release workflows remain the migration baseline until Windows delivery gates pass. Linux / SteamOS expansion is deferred; preserve existing compatibility and CI until an implementation task changes them.

## Working agreement

- Work on `v2`, never modify `main`. Check `git status --short --branch` before edits and before delivery; preserve unrelated changes. Do not commit, push, or rewrite history unless asked.
- Read the affected source and tests. Expand to callers or architecture docs when the impact crosses boundaries; no whole-repository reading or full test run is required for every edit.
- Manage project development tools with `mise.toml` / `mise.lock`; keep the .NET pin consistent with `global.json`. Windows setup and verification commands are in [docs/windows-development.md](docs/windows-development.md). System MSVC/SDK components use the official installer through mise tasks.
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
| `crates/manager-core` | Stable paths, profile services, scans, logs, Runner install/repair | No GUI dependencies or game launch/wait semantics; reuse core models |
| `crates/runner` | CLI, target launch, platform waiting, runtime logs | Native, headless, independent of Manager and GUI assets; no background service |
| `apps/manager-dioxus` | Current Dioxus Desktop configuration UI | Calls manager-core through `src/services.rs`; UI state stays in the app |
| `apps/manager-winui/SteamWrapper.Manager` | Native Windows preview UI, pickers and clipboard | Calls C# Application services; no game launch/wait behavior |
| `apps/manager-winui/SteamWrapper.Application` | Profile editing, local Steam discovery, stable Runner installation | No GUI dependencies or Rust bridge; TOML/CLI compatibility is tested across languages |

Use English as the default project and interface language, with complete Simplified Chinese localization and player-friendly configuration. Keep user-entered game names, paths and protocol identifiers unchanged when switching languages. Maintain matching English and `zh-CN` documentation and resource keys. Keep friendly missing-cover placeholders. The original SteamWrapper icon combines a copper gear and a connecting rod; regenerate its PNG/ICO derivatives with `mise run brand:generate` and keep the Dioxus copies byte-identical to `assets/brand/`. Do not imply endorsement by Rust or Steam.

Keep Runner lifecycle fixes in Runner/platform modules with real process tests. Do not infer Job Object, process-name, process-group, Proton, or windowless guarantees from UI tests or another platform's results.

The current Dioxus app uses pinned 0.7.10 APIs and local CSS; consult official docs/source when changing APIs or versions. pnpm is development tooling for Native E2E and reproducible brand assets only. Do not reintroduce the retired Tauri/React stack, a Node UI runtime, Electron, or Python runtime components. The WinUI design does not add a Rust FFI bridge or management helper. C# implements the existing file contract; run `mise run winui:test` and `mise run winui:contracts` for relevant changes. Preserve unedited fields and reject unsafe writes; missing legacy `wait_mode` means `root`, while new Windows profiles default explicitly to `job`. Preserve the TOML syntax edits and readonly fallback for unsupported layouts; do not replace them with whole-model serialization.

## Data and Steam safety

- Local Steam metadata/covers are readable. The existing Dioxus fallback uses a public Steam CDN URL for a locally known AppID. The first WinUI design uses local covers and placeholders only. Do not expand into third-party metadata services, account lookups, user-data uploads, or new persistent cover downloads without a product request.
- No DLL injection, Steam/game binary patches, DRM bypass, hidden services, or user-data upload.
- Future Steam Launch Options apply/restore must detect Steam running, account for multiple users, back up before writing, and preserve/restore previous options. Generating text is not applying it.
- Automated regression and previews use disposable `STEAM_DIR`, `STEAMWRAPPER_E2E_ROOT`, `XDG_DATA_HOME`, and `LOCALAPPDATA` fixtures. Live Steam acceptance requires explicit user authorization for the real library; that authorization can persist across the agreed test session. Do not patch, replace, repair, uninstall, or clear game files. Record selected-game Launch Options before changing them, restore them after the test, and verify game-file integrity. Stop on unresolved save/cloud conflicts; do not choose which user progress to overwrite. `just dev` uses real data; routine automated previews use the sandbox path.
- For authorized live Windows acceptance, open Manager from ordinary Explorer. A development host can redirect AppData writes into its private file view even when child processes report no package identity. Verify actual file locations; `File.Exists` or direct Runner success in that view does not prove Steam can access them. Keep Launch Options on the stable shared path, never a host package cache.
- Never print, commit, or copy credentials, tokens, or `.env` contents. Keep generated user data, logs, staged binaries, and test artifacts out of commits.

## Verification and task references

For behavioral changes, add a focused regression test and observe failure for the intended missing behavior before implementation. Documentation and cosmetic-only edits need proportionate review, not artificial source-string tests. Start with the affected test gate; use [docs/testing.md](docs/testing.md) to choose further checks. Full CI/release gates remain required for their workflows; do not weaken them to make a local task pass.

Stop repeating successful checks unless new changes or unresolved concerns justify it. If a prerequisite is missing, report the command and blocker, then complete work that does not depend on it. Distinguish not run, blocked, failed, and passed.

Read these references only for the relevant task:

- Service or data boundaries: [docs/architecture.md](docs/architecture.md).
- Windows requirements and implementation gates: [docs/windows-v2-design.md](docs/windows-v2-design.md). Stack/tooling evidence: [docs/tech-stack.md](docs/tech-stack.md), [docs/winui3-assessment.md](docs/winui3-assessment.md).
- Current Dioxus UI, Native E2E, or bundle changes: [skills/dioxus-manager/SKILL.md](skills/dioxus-manager/SKILL.md). It is a repository workflow reference; it does not govern unrelated Runner or WinUI work.
- Test commands and platform evidence: [docs/testing.md](docs/testing.md).
- Packaging, stable Runner installation, update/uninstall: [docs/distribution.md](docs/distribution.md). Stage the current-platform Runner and inspect the actual bundle; Linux success is not Windows/Steam Deck evidence.
- Priorities and deferred scope: [docs/roadmap.md](docs/roadmap.md).

Update affected current docs when behavior, architecture, test commands, or delivery boundaries change. Keep current implementation, proposed direction, and verified platform results distinct.
