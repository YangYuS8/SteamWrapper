---
title: "SteamWrapper v2 roadmap"
description: "Windows preview feedback, delivery, releases, optional updates, and safe Steam integration."
---

<a id="steamwrapper-v2-roadmap"></a>

<a id="路线原则"></a>

## Direction

Keep the Windows-first product boundary: configure a game in the WinUI 3/C# Manager, then launch it through Steam's independent Rust Runner. C# configuration services, TOML, stable data paths and CLI remain the foundation. The next priorities are **player feedback → Windows delivery and releases → optional updates and safe Steam integration → later platform expansion**.

**Merging v2 into main is a mainline transition, not a stable product release.** Installation/update acceptance is still incomplete. As of **2026-10-02**, WinUI is the only Manager: the Dioxus app, Rust `manager-core`, Dioxus Native E2E and old UI release chain have been removed at the user's request. This changes the supported implementation; it does not mark unfinished Windows delivery gates as passed. The [Windows v2 design](/SteamWrapper/project/design/windows-v2/) records the architecture and original stages; the [WinUI assessment](/SteamWrapper/project/decisions/winui3/) records the technical basis. The milestones below set acceptance order without promising dates or reinterpreting published version numbers. See [preview validation](/SteamWrapper/project/validation/winui/) for scoped evidence.

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
| P0 | Native UI automation, player feedback, usable UI/errors and local-first optional covers | Current preview; scoped native, offline and network acceptance |
| P1 | Self-contained per-user installer and portable ZIP | P0 configuration flow; clean Windows install/update/relocation/uninstall acceptance |
| P2 | WinUI prereleases and stable delivery | P1 artifacts; tagged build, signing/checksums, bilingual notes and matching GitHub/CNB binaries |
| P3 | Optional application updates | P1 replacement/recovery and P2 trusted release metadata |
| P4 | Safe Steam Launch Options apply/restore | P0 configuration and P1/P2 delivery safeguards; does not depend on P3 |
| Later | Other Windows targets and platform expansion | Dependable Windows delivery first; separate evidence for each additional platform |

P0 feedback and P1 packaging preparation can progress together. A stable WinUI release requires P0–P2 acceptance; manual Launch Options remain supported while P3/P4 are unfinished. Optional update checks and automatic Steam writes must not delay configuration-safety fixes.

## P0. Player feedback, interface and covers

**Deliverable:** improve the existing preview and add the requested cover option while keeping configuration and launch independent of network access.

- [ ] Collect reproducible feedback with application/Windows versions, expected/actual behavior and relevant redacted diagnostics. Separate configuration, launcher-lifetime and delivery defects; do not request saves, game binaries or whole Steam account files.
- [ ] Add automated native UI regressions against the actual WinUI application with disposable Steam and user-data fixtures. Cover startup, language switching/restart, preserved edits, picker cancellation, save/conflict handling and Runner status. Keep service/contract tests; removed Dioxus tests do not establish WinUI UI coverage.
- [ ] Complete English/Simplified Chinese native acceptance for unsaved input preservation, keyboard use, Chinese input, scaling, pickers, cancellation and recoverable errors.
- [ ] Complete player acceptance for Chinese/spaced paths, launch failures and useful diagnostic logs. Retain the explanation that `job` returns launcher status and the limits of actual descendant exit-code evidence. Expand launcher observations only with scoped real-process/game evidence.
- [x] Keep covers **local-first and offline by default**. Prefer custom/local Steam art, including newer hash directories. Validate ordered local candidates; missing or unreadable art leaves a friendly placeholder without blocking saving or launch.
- [x] Add an explicit setting for **official Steam CDN fallback**, which users can disable. Explain that an image request contains the locally known AppID. Fetch only missing covers for AppIDs already discovered locally; do not upload library inventories, query accounts or add third-party metadata services.
- [x] Allow only documented official Steam CDN HTTPS hosts; check redirects against the same allowlist. Limit concurrency, request/response time, download bytes and decoded image size. Reject unsupported or malformed content.
- [x] Keep a small quota-limited cache under SteamWrapper's `cache` directory, with expiry/eviction and a clear action. Never overwrite custom art, Steam cache files, game files or profiles. Disabling fallback cancels downloads and stops new requests; valid downloaded cache remains available offline, and cleanup touches only SteamWrapper's downloaded covers.

**Acceptance:** repeatable native WinUI UI tests and broader player trials cover both languages, editing and failure recovery, with scoped evidence and unresolved issues recorded. Isolated cover tests verify no requests before opt-in or after disabling, local/custom priority, preference persistence, cancellation, offline/timeout/404/rate limits, bad redirects, oversized/corrupt images and cache limits. Native checks also verify responsive editing during cover failures. The cover preference, downloader and persistent cache are implemented as a scoped P0 slice; the native UI automation and broader player acceptance above remain open. Implementation checkboxes do not establish that every native or delivery gate passed. Cover success does not establish Overlay, achievement or game compatibility.

See [cover settings](/SteamWrapper/guides/configuration/#cover-settings) for the controls and offline behavior, and [architecture](/SteamWrapper/development/architecture/#covers-and-safety-boundaries) for request/cache limits. Official CDN fallback is best effort: a known AppID may have no image at the fixed portrait URL, especially for newer hashed assets. That response keeps a placeholder and never triggers an account or third-party metadata lookup.

## P1. Windows installation, update and uninstall

**Deliverable:** an unpackaged, self-contained per-user WinUI installer and complete portable ZIP from the same application layout.

The approved [Windows delivery plan](/SteamWrapper/project/design/windows-delivery/) maps P1–P3 into D1a/D1b installation/recovery, D2/D3 signing readiness/releases and D4/D5 optional checks/confirmed updates. The unsigned [Inno/C# installer preview](/SteamWrapper/guides/installer-preview/), lifetime lease, journal/manual repair and signing-policy groundwork are implemented. Internal update validation uses fixtures only. The clean-client and broader delivery checkboxes below remain open; Foundation approval and production signed releases are not available.

- [ ] Bundle .NET, Windows App SDK, native/localized resources and the independent Runner. Ordinary players should not install SDKs or prepare runtimes; no single-file EXE is promised.
- [ ] Install Manager per user without routine administrator rights. Keep data under `%LOCALAPPDATA%\SteamWrapper\` and Steam references on stable `bin\SteamWrapperRunner.exe`, never a versioned Manager or extraction directory.
- [ ] On a clean supported Windows 11 x64 VM without development tools, verify installation, both languages, first configuration, actual shared data paths and launch through stable Runner with Manager closed.
- [ ] Verify in-place updates, moving Manager/portable files, busy Runner files, unknown/incompatible versions, interrupted replacement and rollback. Preserve profiles, preferences, backups, logs and working Launch Options. Do not downgrade a newer compatible Runner or stop an active game to replace it.
- [ ] Uninstall Manager while retaining user data and stable Runner by default. Full cleanup needs an explicit choice and handling of known Steam references; retain Runner with guidance when manually pasted or unenumerable references cannot be proven removed.
- [ ] Record artifact/installed size, cold startup, supported Windows versions, tested games and limits. Provide English and complete Simplified Chinese installation, update, recovery, relocation and removal instructions.

**Acceptance:** record installer and portable results separately, including failure recovery and an unchanged usable configuration after a failed update. A development-machine publish is not clean-VM acceptance. Authorized real Steam tests separately require prior Launch Options/save protection and post-test integrity checks.

## P2. WinUI prereleases and stable delivery

**Deliverable:** repeatable releases from a reviewed tag, initially marked prerelease and promoted to stable only after P0/P1 acceptance.

- [x] Separate daily test/compile CI from version-tag portable packaging and prerelease publication; retain explicit manual previews without public releases, strict version/notes preflight, checksums and an optional CNB binary mirror
- [ ] Build/test the exact tagged WinUI revision and inspect actual installer/portable contents, Runner metadata and localized resources. Label historical Dioxus releases as historical; they are not current WinUI artifacts or a retained release chain.
- [ ] Establish Windows artifact signing, publisher identity and timestamp verification. Check signatures after packaging; label an unsigned prerelease accurately. A checksum is not a signature, and players should not be asked to disable protection.
- [ ] Publish SHA-256 checksums, exact version/commit/platform labels, English and complete Simplified Chinese release notes, known limits and installation/update/recovery instructions.
- [ ] Publish matching binaries and checksums to GitHub Releases and CNB Releases, then verify both downloadable copies. Source synchronization alone is insufficient; a failed mirror/upload leaves that channel incomplete.
- [ ] Designate a WinUI release as stable only after the release checklist and clean-system evidence pass. Preserve prerelease/stable distinctions and identify unverified operations or platforms.

**Acceptance:** another maintainer can identify the source tag, download every advertised artifact from both channels, verify its digest and applicable signature, and follow the documented installation/update/uninstall flow. Signing credentials and release secrets stay out of repository content. Branch merging, tagging or a CI preview upload alone does not complete this gate.

The [tag-release workflow and maintainer steps](/SteamWrapper/development/distribution/#prepare-and-trigger-a-release) implement the automation slice of P2. Merging does not publish a new version. Current source versions are `0.2.1`, advanced for Runner PE metadata. Manual preview workflows additionally build/test an unsigned installer; public-tag delivery remains the portable five-asset contract pending D1b/D3. Download verification, configured CNB binaries, signing and clean-client acceptance require actual release evidence.

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

- Assess Windows 10, ARM64 and MSIX separately, with actual artifact/platform evidence rather than extending Windows 11 x64 results.
- Assess import/export, multiple targets and batch restore from player needs after the single-game path is dependable.
- Keep existing Rust core/Runner Linux compatibility and CI. There is no retained Linux Manager after Dioxus removal. New Linux, SteamOS and Proton scope needs separate requirements, process tests and support matrices, outside the first Windows stable release gate.

<a id="现有实现记录与证据边界"></a>

## Existing implementation and evidence boundaries

Current source contains the WinUI Manager, C# configuration services and independent Rust core/Runner. The Manager supports local Steam discovery/covers, TOML editing, stable Runner installation and Launch Options generation. The removed [Dioxus app](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus), [Rust management layer](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core) and [old UI release workflow](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/.github/workflows/release.yml) remain inspectable at `ca6a09e` as historical references, not current Windows UI or delivery evidence.

The old roadmap's Dioxus and Linux/AppImage checks are historical implementation records available at `31a609d:docs/roadmap.md`; they are not mixed into current acceptance. The A/B/C checks above retain their original scope, including the then-retained workflows. Their removal on 2026-10-02 does not change earlier test results or satisfy the remaining delivery gates. The WinUI configuration preview and contracts are implemented; see the [environment record](/SteamWrapper/development/windows/). Covers include corrected local discovery and the optional CDN/cache slice above, with offline defaults. Daily CI and version-tag/manual delivery are separated, with the tag prerelease automation slice implemented. The unsigned installer prototype and signing/update-validation kernels are implemented; clean-client delivery, production signing, enabled updates and one-click Steam apply/restore remain unfinished. Automation does not expand game/achievement guarantees or establish unrun release acceptance.
