---
title: "SteamWrapper v2 roadmap"
description: "Windows preview feedback, delivery, releases, optional updates, and safe Steam integration."
---

<a id="steamwrapper-v2-roadmap"></a>

<a id="路线原则"></a>

## Direction

Keep the Windows-first product boundary: configure a game in the WinUI 3/C# Manager, then launch it through Steam's independent Rust Runner. C# configuration services, TOML, stable data paths and CLI remain the foundation. The next priorities are **player feedback → Windows delivery and releases → optional updates and safe Steam integration → later platform expansion**.

**Merging v2 into main is a mainline transition, not a stable product release.** It does not finish installation/update acceptance or retire Dioxus. The [Windows v2 design](/SteamWrapper/project/design/windows-v2/) records the architecture and original stages; the [WinUI assessment](/SteamWrapper/project/decisions/winui3/) records the technical basis. The WinUI configuration preview is implemented, and Dioxus remains the migration baseline. The milestones below set acceptance order without promising dates or reinterpreting published version numbers. See [preview validation](/SteamWrapper/project/validation/winui/) for scoped evidence.

<a id="a-windows-工具链与配置契约"></a>

## A. Windows toolchain and configuration contracts

- [x] Trace original requirements, assess WinUI, and define product/architecture boundaries
- [x] Pin development tools with mise, install MSVC/Windows SDK, and validate an isolated self-contained WinUI build
- [x] Pass the existing Rust Runner's six tests on Windows, including Job Object and process-name waiting
- [x] Verify C# reading/single-field editing/Rust consumption: complete fields, defaults, legacy aliases, unknown data, Chinese text, paths, and arguments
- [x] Verify atomic configuration saves, preservation after replacement failure, backup, and editing conflicts (a final-check race remains for non-cooperating editors)
- [x] Pass C#-generated configuration to an actual Runner fixture and verify argv, cwd, and waiting
- [x] Add Windows build/contract CI incrementally while retaining existing workflows; the implementation baseline passed remote WinUI CI, while later changes need their own verification

The mise setup above is a historical local result. mise is optional for contributors; SDK requirements and direct PowerShell/pnpm commands are in [Windows development](/SteamWrapper/development/windows/).

<a id="b-winui-完整配置切片"></a>

## B. Complete WinUI configuration slice

- [x] Establish a WinUI window and independently testable C# application services, without new FFI/helpers
- [x] Configured-game home page, adding games, search, and manual Steam path selection
- [x] Native target selection, preservation of advanced arguments/working directory, and compatible TOML saving
- [x] Local covers or friendly placeholders, without a network-cover prerequisite
- [x] Install/repair stable Runner, retaining configuration and the old binary on failure
- [x] Generate/copy exact Launch Options with explicit guidance to preserve the old value and restore it manually
- [ ] Complete broader native interaction, Chinese input, keyboard use, scaling, cancellation and error-recovery acceptance under P0

<a id="c-windows-可用预览与替换门槛"></a>

## C. Usable Windows preview and replacement gate

- [x] Close Manager, launch/exit through real Steam, and record status/playtime; a local Unity game and all five 9-nine titles passed. See [per-game evidence and limits](/SteamWrapper/project/validation/steam/)
- [x] After the local Episode 1 CHS launcher exited first, the actual game and Runner remained until ordinary exit; Chinese opening and Steam playtime passed, covering only this observed launcher scenario

These results do not establish every launcher's compatibility, achievements, clean-system installation, safe updates or uninstall. The remaining player and delivery gates are P0–P2 below. The preview continues to support manually copied Launch Options: generation/copying is not a Steam write, and fixture success is not real Steam playtime validation.

## Next delivery milestones

| Priority | Deliverable | Dependency and completion gate |
| --- | --- | --- |
| P0 | Player feedback, usable UI/errors and local-first optional covers | Current preview; scoped native, offline and network acceptance |
| P1 | Self-contained per-user installer and portable ZIP | P0 configuration flow; clean Windows install/update/relocation/uninstall acceptance |
| P2 | WinUI prereleases and stable delivery | P1 artifacts; tagged build, signing/checksums, bilingual notes and matching GitHub/CNB binaries |
| P3 | Optional application updates | P1 replacement/recovery and P2 trusted release metadata |
| P4 | Safe Steam Launch Options apply/restore | P0 configuration and P1/P2 delivery safeguards; does not depend on P3 |
| Later | Dioxus retirement and other platforms | Replacement gates first; separate evidence for each additional platform |

P0 feedback and P1 packaging preparation can progress together. A stable WinUI release requires P0–P2 acceptance; manual Launch Options remain supported while P3/P4 are unfinished. Optional update checks and automatic Steam writes must not delay configuration-safety fixes.

## P0. Player feedback, interface and covers

**Deliverable:** improve the existing preview and add the requested cover option while keeping configuration and launch independent of network access.

- [ ] Collect reproducible feedback with application/Windows versions, expected/actual behavior and relevant redacted diagnostics. Separate configuration, launcher-lifetime and delivery defects; do not request saves, game binaries or whole Steam account files.
- [ ] Complete English/Simplified Chinese native acceptance for unsaved input preservation, keyboard use, Chinese input, scaling, pickers, cancellation and recoverable errors.
- [ ] Complete player acceptance for Chinese/spaced paths, launch failures and useful diagnostic logs. Retain the explanation that `job` returns launcher status and the limits of actual descendant exit-code evidence. Expand launcher observations only with scoped real-process/game evidence.
- [ ] Keep covers **local-first and offline by default**. Prefer custom/local Steam art. Missing or unreadable art leaves a friendly placeholder without blocking saving or launch.
- [ ] Add an explicit setting for **official Steam CDN fallback**, which users can disable. Explain that an image request contains the locally known AppID. Fetch only missing covers for AppIDs already discovered locally; do not upload library inventories, query accounts or add third-party metadata services.
- [ ] Allow only documented official Steam CDN HTTPS hosts; check redirects against the same allowlist. Limit concurrency, request/response time, download bytes and decoded image size. Reject unsupported or malformed content.
- [ ] Keep a small quota-limited cache under SteamWrapper's `cache` directory, with expiry/eviction and a clear action. Never overwrite custom art, Steam cache files, game files or profiles. Disabling fallback stops new requests; cleanup touches only SteamWrapper's downloaded covers.

**Acceptance:** isolated tests verify no cover requests before opt-in or after disabling, local/custom priority, preference persistence, cancellation, offline/timeout/404/rate limits, bad redirects, oversized/corrupt images and cache limits. Native checks cover both languages and responsive editing during failures. Current WinUI still has local covers/placeholders only; the optional CDN path and persistent cache are planned work. Cover success does not establish Overlay, achievement or game compatibility.

## P1. Windows installation, update and uninstall

**Deliverable:** an unpackaged, self-contained per-user WinUI installer and complete portable ZIP from the same application layout.

- [ ] Bundle .NET, Windows App SDK, native/localized resources and the independent Runner. Ordinary players should not install SDKs or prepare runtimes; no single-file EXE is promised.
- [ ] Install Manager per user without routine administrator rights. Keep data under `%LOCALAPPDATA%\SteamWrapper\` and Steam references on stable `bin\SteamWrapperRunner.exe`, never a versioned Manager or extraction directory.
- [ ] On a clean supported Windows 11 x64 VM without development tools, verify installation, both languages, first configuration, actual shared data paths and launch through stable Runner with Manager closed.
- [ ] Verify in-place updates, moving Manager/portable files, busy Runner files, unknown/incompatible versions, interrupted replacement and rollback. Preserve profiles, preferences, backups, logs and working Launch Options. Do not downgrade a newer compatible Runner or stop an active game to replace it.
- [ ] Uninstall Manager while retaining user data and stable Runner by default. Full cleanup needs an explicit choice and handling of known Steam references; retain Runner with guidance when manually pasted or unenumerable references cannot be proven removed.
- [ ] Record artifact/installed size, cold startup, supported Windows versions, tested games and limits. Provide English and complete Simplified Chinese installation, update, recovery, relocation and removal instructions.

**Acceptance:** record installer and portable results separately, including failure recovery and an unchanged usable configuration after a failed update. A development-machine publish is not clean-VM acceptance. Authorized real Steam tests separately require prior Launch Options/save protection and post-test integrity checks.

## P2. WinUI prereleases and stable delivery

**Deliverable:** repeatable releases from a reviewed tag, initially marked prerelease and promoted to stable only after P0/P1 acceptance.

- [ ] Build/test the exact tagged revision and inspect actual installer/portable contents, Runner metadata and localized resources. Clearly distinguish retained Dioxus artifacts during transition.
- [ ] Establish Windows artifact signing, publisher identity and timestamp verification. Check signatures after packaging; label an unsigned prerelease accurately. A checksum is not a signature, and players should not be asked to disable protection.
- [ ] Publish SHA-256 checksums, exact version/commit/platform labels, English and complete Simplified Chinese release notes, known limits and installation/update/recovery instructions.
- [ ] Publish matching binaries and checksums to GitHub Releases and CNB Releases, then verify both downloadable copies. Source synchronization alone is insufficient; a failed mirror/upload leaves that channel incomplete.
- [ ] Switch the default stable Manager/release chain only after the release checklist and clean-system evidence pass. Preserve prerelease/stable distinctions and identify unverified operations or platforms.

**Acceptance:** another maintainer can identify the source tag, download every advertised artifact from both channels, verify its digest and applicable signature, and follow the documented installation/update/uninstall flow. Signing credentials and release secrets stay out of repository content. Branch merging, tagging or a CI preview upload alone does not complete this gate.

## P3. Optional application updates

**Deliverable:** an optional Manager update entry point using P1 replacement/recovery and P2 release trust.

- [ ] Start with user-invoked checks; automatic checks require an explicit, reversible preference. Show stable/prerelease channel, version, notes, size and source before installation.
- [ ] Validate release metadata and downloaded artifact authenticity/integrity, then use the accepted installer/replacement path. Never silently downgrade Runner, overwrite profiles or replace files used by an active game.
- [ ] Test disabled/offline operation, timeout, missing/malformed metadata, interrupted downloads, corrupt/untrusted packages, busy files and rollback. Failed or skipped updates leave the existing app usable.
- [ ] Keep update checks out of Runner's daily game-launch path; add no hidden background service, account requirement or library upload.

**Acceptance:** users can decline updates or disable checks without losing configuration or launch functionality. Manual download/install remains available. This updates SteamWrapper, not game files.

<a id="d-windows-安全一键应用与恢复"></a>
<a id="d-safe-windows-one-click-apply-and-restore"></a>

## P4. Safe Windows one-click apply and restore

**Deliverable:** an optional, reviewable write to the selected Steam user's selected game, with a safe restore path.

- [ ] Identify local Steam, the game and multiple users without guessing an account. Show exact previous/proposed Launch Options and require an explicit target choice.
- [ ] Block writes while Steam is running and recheck immediately before mutation. Preserve unrelated data, stable Runner references and the existing `%command%` position.
- [ ] Back up original values/files before mutation; replace atomically, read back and recover after interruption. Record enough provenance to restore only this change.
- [ ] Detect external edits before apply and restore. Surface conflicts, preserving current data and backups rather than overwriting a later user value or another game's settings.
- [ ] Test no/one/multiple users, nonempty old options, Steam starting during the operation, malformed/read-only/locked files, failed writes, interrupted recovery, later edits and repeated restore.
- [ ] Verify authorized live selected-game sessions, restoration and file/save integrity. Do not expand wait-mode or achievement claims from successful configuration writes.
- [ ] Make one-click apply the default flow only after these gates pass; keep manual copy/restore available.

**Acceptance:** success means the selected setting was written and verified. Failure preserves the previous usable state or provides a specific recovery path. Unresolved save/cloud conflicts stop live acceptance rather than selecting progress to overwrite. P4 precedes new Linux/SteamOS/Proton work but does not require the optional updater to ship first.

<a id="后续评估"></a>

## Later assessment

- Retire Dioxus, old management layers and replaced workflows only after WinUI configuration, delivery and default-release gates pass. Audit dependencies and configuration compatibility first; merging into main alone is not the trigger.
- Assess Windows 10, ARM64 and MSIX separately, with actual artifact/platform evidence rather than extending Windows 11 x64 results.
- Assess import/export, multiple targets and batch restore from player needs after the single-game path is dependable.
- Keep existing Linux compatibility and CI. New Linux, SteamOS and Proton scope needs separate requirements, process tests and support matrices, outside the first Windows stable release gate.

<a id="现有实现记录与证据边界"></a>

## Existing implementation and evidence boundaries

Current source contains Rust core/manager-core/Runner, Dioxus 0.7.10 UI, local Steam scanning, CDN cover fallback, TOML saving, stable Runner installation, Launch Options generation, platform process code, and Dioxus Native E2E/packaging workflows. They provide migration references, not proof that the current Windows acceptance has passed.

The old roadmap's Dioxus and Linux/AppImage checks are historical implementation records available at `31a609d:docs/roadmap.md`; they are not mixed into current acceptance. Existing Linux code and CI remain, with new scope deferred. The WinUI configuration preview and contracts are implemented; see the [environment record](/SteamWrapper/development/windows/). Current WinUI covers are local-only; the opt-in CDN/cache policy above is new planned work, distinct from retained Dioxus fallback. The new installer, optional application updater and one-click Steam apply/restore are still unimplemented. This roadmap plans those features; it does not implement them or expand game/achievement guarantees.
