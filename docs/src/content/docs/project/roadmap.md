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
| P2 | WinUI prereleases and stable delivery | P1 artifacts; tagged build, checksums, bilingual notes and verified advertised sources; Authenticode optional |
| P3 | Optional application updates | P1 replacement/recovery and P2 trusted release metadata |
| P4 | Safe Steam Launch Options apply/restore | P0 configuration and P1/P2 delivery safeguards; does not depend on P3 |
| Later | Other Windows targets and platform expansion | Dependable Windows delivery first; separate evidence for each additional platform |

P0 feedback and P1 packaging preparation can progress together. A stable WinUI release requires P0–P2 acceptance; manual Launch Options remain supported while P3/P4 are unfinished. Optional update checks and automatic Steam writes must not delay configuration-safety fixes.

## Execution queue (2026-10-03)

**Planning baseline:** [PR #13](https://github.com/YangYuS8/SteamWrapper/pull/13), merged as `1687bca`, includes the unsigned installer, deployment/recovery components, signing validation and the internal update-check kernel. Recorded verification includes 185 C# tests, 11 isolated real installer/uninstaller processes and [manual preview run 37060817829](https://github.com/YangYuS8/SteamWrapper/actions/runs/37060817829). These are development/hosted-runner results, not clean Windows 11 or native UI acceptance. The default upgrade fixture changes version metadata synthetically; it is not a genuine next-version binary. Local-first covers and the optional official CDN are already implemented. No current WinUI public installer, Foundation approval, production update feed or Steam apply/restore is established by that evidence.

**Local execution scope (2026-10-03):** W1's developer-only actual-window UIA slice passed **10 cases**, including picker cancellation, selectable/searchable local games with missing/corrupt art and CDN off, and safe save with exact stable Runner Launch Options. CI compiles the harness only; native execution needs an unlocked interactive desktop. W2 completed **13 isolated real process steps** using hash-verified frozen `0.2.1` and genuinely compiled `0.2.2`, including maintenance rollback and Inno re-upgrade; evidence records `numericUpgradeUsesSyntheticMetadataFixture=false`, preservation of 928 owned version files and six data fixtures, and `cleanVm=false`. [Testing](/SteamWrapper/development/testing/) records the scope; the [installer guide](/SteamWrapper/guides/installer-preview/) provides the reproducible command. No clean Windows VM was available. IME/scaling/clipboard, broader native/player acceptance, clean-client delivery and remaining recovery/retention gates keep W1 and W2 open.

**Additional local `0.2.3` slices (2026-10-03):** genuinely compiled `0.2.3` passed **11 native cases**, adding system-language startup without saving a preference; the complete Deployment gate passed **99 cases**, including real native long-path uninstall and explicit CLI-language regression coverage. Seven controlled free-space admission tests and seven real compiled child-process stop/recovery cases cover five installation and two recovery-rename checkpoints. The Host's language tests cover supported system defaults, explicit preferences, UTF-8 BOM/aliases and read-only error fallback. Five final NativeAOT maintenance processes additionally verified system-derived recovery messages on actual `zh-CN` Windows, explicit English/Chinese preferences and malformed-settings fallback. This does not establish actual system-disk exhaustion, full-machine power loss, registry/shortcut recovery or version retention.

**Final genuine upgrade slice (2026-10-03):** frozen `0.2.2` → genuinely compiled `0.2.3` completed another 13 expected isolated real process steps. Actual maintenance rollback preserved 1,066 owned version files and setup-owned state before Inno re-upgraded; locked/unknown-file uninstall refusals and subsequent normal uninstall/reinstall passed. Six data fixtures retained their hashes. This evidence records `numericUpgradeUsesSyntheticMetadataFixture=false`, `unsigned=true` and `cleanVm=false`, retaining the earlier `0.2.1` → `0.2.2` result as a separate record. It does not complete W2's clean-client or retention gates.

**First public technical preview (2026-10-03):** [v0.2.3-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.3-preview.1) was published by successful [run 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907). All seven official GitHub downloads passed length/digest and schema-2 checks, seven own PE versions matched, Setup remained unsigned, and five downloaded NativeAOT Host language cases passed on actual `zh-CN` Windows. The public Setup was inspected, not installed in this check. CNB binary credentials were absent and that mirror was skipped; no CNB binary download is advertised. W3's current-form GitHub technical-preview evidence is established; W1/W2 stable acceptance and W4's actual approval/signing remain open.

**Focused `0.2.4` slices (2026-10-03):** the fix for queued `TextChanged` events falsely marking loaded fields dirty passed four new add/manual-AppID/dirty-edit/keyboard flows and eight affected editor cases, **12 actual native cases**, with six fixture processes exiting normally. Keyboard evidence is limited to HWND messages/focus; IME/DPI still need acceptance. Separately, **14 focused uninstall process-stop cases** passed at six journal/isolation/deactivation/cleanup checkpoints, and the existing **seven installation/recovery cases** passed after the shared fixture change. These are additional scoped results, not a claimed complete 113-case suite.

**Genuine `0.2.3 → 0.2.4` slice (2026-10-03):** frozen `0.2.3` and genuinely compiled `0.2.4` passed **13 expected isolated Inno/maintenance process steps**. Actual rollback `0.2.4 → 0.2.3` preserved 1,204 owned version files and maintenance/uninstaller/shortcuts before Inno re-upgraded. Late owned-file locks and unknown files refused uninstall; subsequent normal uninstall/reinstall passed, with all six data fixtures unchanged. Evidence records a non-synthetic, unsigned upgrade and `cleanVm=false`; seven current own PE versions, five NativeAOT Host language cases and cross-language contracts also passed separately. [Testing](/SteamWrapper/development/testing/) identifies the actual records. These results do not close W2's clean-client or retention gates.

**Project-signed updates (2026-10-05):** the maintainer reported the SignPath application was rejected; no reason is inferred. The current `0.2.5` source implements a simple bilingual update dialog, opt-in startup checks, project-signature verification, bounded downloads and a confirmed handoff to the existing Inno installer. A real public key and GitHub signing secret are configured. A genuine isolated `0.2.4` → `0.2.5` installation handoff passed, including normal originating-process exit, healthy Manager restart, previous-version retention, unchanged profiles/preferences/stable Runner and removal of the test installation. The [testing record](/SteamWrapper/development/testing/#project-update-checks-and-installation) scopes this evidence as `cleanVm=false` and `signedFeedNetwork=false`. New tag/feed publication, public download-to-install acceptance and broader recovery gates remain pending; CNB has no published binary assets or configured release credential. Authenticode signing is optional and does not gate stable delivery or updates.

**Installation and uninstall choices (2026-10-05, acceptance pending):** the current implementation adds an empty fixed-local-drive directory choice for first installation, registered-location updates/repair, Start menu enabled by default, optional desktop shortcut and opening Manager on completion. Default uninstall removes only Manager, shortcuts and registration. Seven independent opt-in choices cover recognized Steam launch-command removal and six data categories. Exact standard commands are backed up before clearing; custom commands and unknown historical arguments are not reconstructed. Profiles/Runner removal requires stopped Steam and no unresolved account references; games, saves, Steam restoration backups, update trust state and unknown files remain protected. This new integration needs its own isolated acceptance; the earlier update-handoff result does not validate these choices. See the [installer guide](/SteamWrapper/guides/installer-preview/).

The following tasks refine P0–P4. Implementation and fixture results do not close their independent delivery acceptance gates.

| Task | Work | Completion evidence |
| --- | --- | --- |
| W1 — Native preview acceptance (P0) | Prove an out-of-process native UI harness against the existing WinUI window and disposable fixtures, then cover adding/searching games, dirty edits, picker cancellation, save conflicts, Runner status, clipboard and persisted language/preferences. Exercise English/Chinese, keyboard/IME, 100%/150%/200% scaling and cover failure/cancellation. | Repeatable actual-window regressions, scoped manual checks for native controls the harness cannot exercise, and fixes for configuration loss or blocked daily use. Covers stay responsive, offline by default and local-first; service tests or opening a sandbox window alone are insufficient. |
| W2 — Clean-client delivery and recovery (P1 / D1a–D1b) | Test Windows 11 24H2 x64 and a newer supported client, without developer SDKs or prepared runtimes: ordinary accounts, offline/both-language setup, two users, Explorer launch, actual shared paths, shortcuts/pins and portable migration. Split genuine upgrade/rollback, interruption and version-retention work into separate changes. | Freeze the previous base before genuinely compiling the next-base payload, using `Test-WinUIInstaller.ps1 -UpgradePublishDirectory`; evidence records `numericUpgradeUsesSyntheticMetadataFixture=false`. Exercise real process stops, disk exhaustion, late locks and registry/shortcut failures. Preserve data/Runner and repeatable recovery. After health confirmation, retain the current healthy and last verified usable previous version; prune only verified owned older files under the exclusive lease. Keep unknown/quarantined recovery data and enforce disk limits. |
| W3 — Public unsigned installer prerelease (P2) | The explicit version-2 schema packages installer and portable ZIP, lengths/digests, `signed=false` and `installer=true`, preserving the schema-1 five-asset validator. Publish a clearly scoped technical preview with exact version/commit, bilingual notes and recovery limits; W1/W2 acceptance remains required for stable delivery. | Inspect actual packages and verify downloads from GitHub and every advertised, configured CNB mirror. Main/PR runs remain normal CI; manual dispatch remains artifact-only. The unsigned installer is a supported distribution form; technical previews do not establish clean-client or stable acceptance. |
| W4 — Optional Authenticode signing (D2–D3) | Retain the SignPath drafts and validators for a possible future provider. The rejected application does not block unsigned releases or project-key-authenticated updates. | Any future signed release needs real provider approval, verified signatures/timestamps and unchanged upstream signatures. This is optional and outside stable-release prerequisites. |
| W5 — Player-facing update checks (P3 / D4) | Implemented in `0.2.5`: bilingual native dialog, manual check, startup checks off by default and preserved preferences. Channel follows the installed tag; source defaults to GitHub with CNB network fallback. Show version, release-page link and friendly errors. | Verify the new native flow and the published project-signed feed. Checks never launch an installer or enter Runner's game-launch path. Public source availability is not established by a configured key alone. |
| W6 — Verified download and confirmed installation (P3 / D5) | Implemented: bounded cancellable download, signed manifest plus final size/hash verification, unsaved-edit handling and an installer handoff through the existing Host. The helper waits for normal Manager exit, verifies the file again and starts the same Inno installer. Portable copies use release-page downloads. | Genuine isolated `0.2.4` → `0.2.5` installation handoff, healthy restart and data preservation passed on 2026-10-05. Public-feed/download integration, clean clients, broader busy-file/interrupted/rejected-update and recovery acceptance remain pending. Do not force-close games/Manager, silently downgrade or overwrite profiles. Authenticode is optional; project-signature verification is required. |
| W7 — Safe Steam apply/restore (P4) | Develop disposable VDF/account fixtures after configuration gates; enable writes only after W1/W2 and relevant P2 delivery safeguards. Explicitly select account/game and preview old/new values; preserve syntax/unknown fields, back up, block/recheck running Steam, atomically write/read back and restore only unchanged values owned by this operation. | Multi-user, locks, malformed files, external edits, Steam-start races and interrupted recovery pass before a separately authorized single-game galgame trial. Record/restore Launch Options and compare game-file hashes without repairing game files; stop on save/cloud conflicts. Keep manual copy/restore available. This task does not depend on W5/W6. |

The stable-delivery sequence is **W1/W2 acceptance → W3 verified delivery**. W4 Authenticode signing is optional. W5/W6 use an independent project key and need real feed/download/installation acceptance before being advertised as a verified update service. W7 remains independent after its configuration-safety dependencies. The first stable scope is P0–P2; optional updates and Steam writes must not delay configuration-safety fixes. Windows 10, ARM64, MSIX and a new Linux/SteamOS Manager remain later assessments; existing Rust Linux process CI continues.

**Version rule for the current deployment contract:** every new installable payload/manifest needs a new coordinated `MAJOR.MINOR.PATCH`. Changing only a preview suffix retains the numeric version, so installation correctly rejects same-version/different-content. Current source is `0.2.5`, following the published unsigned `0.2.4` payload. Retry the exact immutable artifact; do not rewrite a public tag or weaken the version gate. This rule applies regardless of Authenticode signing.

**Retention compatibility gate:** the frozen `0.2.1`/`0.2.2` deployment implementations reject unknown installation-root files and JSON fields. Adding a health-history sidecar or state property without a compatible metadata design can prevent the old Manager from starting after rollback. Prove actual old-binary rollback before enabling retention; do not infer historical previous-version health or delete unknown/quarantined data to meet a quota.

The uninstall journal accepts at most 32 retained versions; installation currently neither prunes versions nor bounds the admitted version count, so a longer series can prevent uninstall. Compatible health history and bounded retention/admission remain required W2 stable-delivery work; this gap does not block the clearly scoped technical preview.

## P0. Player feedback, interface and covers

**Deliverable:** improve and accept the existing preview and implemented cover option while keeping configuration and launch independent of network access.

- [ ] Collect reproducible feedback with application/Windows versions, expected/actual behavior and relevant redacted diagnostics. Separate configuration, launcher-lifetime and delivery defects; do not request saves, game binaries or whole Steam account files.
- [ ] Expand the first native UIA regression slice against the actual WinUI application with disposable Steam and user-data fixtures. Complete startup, language switching/restart, preserved edits, picker cancellation, save/conflict handling and Runner status coverage with scoped evidence. Keep service/contract tests; removed Dioxus tests do not establish WinUI UI coverage.
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

The approved [Windows delivery plan](/SteamWrapper/project/design/windows-delivery/) includes the unsigned [Inno/C# installer preview](/SteamWrapper/guides/installer-preview/), installation leases and recovery, optional Authenticode preparation, and project-signed application updates. The update UI/download/handoff now exists in `0.2.5`; real public-feed and full delivery acceptance remain pending. The clean-client and broader delivery checkboxes below stay open; Foundation approval is no longer a prerequisite.

- [ ] Bundle .NET, Windows App SDK, native/localized resources and the independent Runner. Ordinary players should not install SDKs or prepare runtimes; no single-file EXE is promised.
- [ ] Install Manager per user without routine administrator rights. Keep data under `%LOCALAPPDATA%\SteamWrapper\` and Steam references on stable `bin\SteamWrapperRunner.exe`, never a versioned Manager or extraction directory.
- [ ] On a clean supported Windows 11 x64 VM without development tools, verify installation, both languages, first configuration, actual shared data paths and launch through stable Runner with Manager closed.
- [ ] Verify in-place updates, moving Manager/portable files, busy Runner files, unknown/incompatible versions, interrupted replacement and rollback. Preserve profiles, preferences, backups, logs and working Launch Options. Do not downgrade a newer compatible Runner or stop an active game to replace it.
- [ ] Verify Manager-only uninstall preserves user data, stable Runner and recovery/ownership receipts. The first installer has no delete-all-data choice or automatic Steam restore; provide separate manual removal guidance while Steam references cannot be proven removed.
- [ ] Record artifact/installed size, cold startup, supported Windows versions, tested games and limits. Provide English and complete Simplified Chinese installation, update, recovery, relocation and removal instructions.

**Acceptance:** record installer and portable results separately, including failure recovery and an unchanged usable configuration after a failed update. A development-machine publish is not clean-VM acceptance. Authorized real Steam tests separately require prior Launch Options/save protection and post-test integrity checks.

## P2. WinUI prereleases and stable delivery

**Deliverable:** repeatable releases from a reviewed tag, initially marked prerelease and promoted to stable only after P0/P1 acceptance.

- [x] Separate daily test/compile CI from version-tag Setup/portable technical-prerelease packaging; retain explicit manual previews without public releases, strict version/notes preflight, checksums and an optional CNB binary mirror
- [x] Build/test the exact tagged WinUI revision and inspect actual installer/portable contents, Runner metadata and localized resources; first established for `v0.2.3-preview.1`. Label historical launcher/UI releases accurately; the old public `v1.0.0` launcher is not a current WinUI delivery or an installer-acceptance result.
- [ ] Optional: add Windows Authenticode publisher identity and timestamp verification if a provider becomes available. Label unsigned releases accurately. Project update signing does not remove Windows reputation warnings; players should not disable protection.
- [x] Publish SHA-256 checksums, exact version/commit/platform labels, English and complete Simplified Chinese release notes, known limits and installation/update/recovery instructions for `v0.2.3-preview.1`.
- [ ] Publish matching binaries and checksums to GitHub Releases and CNB Releases, then verify both downloadable copies. Source synchronization alone is insufficient; a failed mirror/upload leaves that channel incomplete.
- [ ] Designate a WinUI release as stable only after the release checklist and clean-system evidence pass. Preserve prerelease/stable distinctions and identify unverified operations or platforms.

**Acceptance:** another maintainer can identify the source tag, download every advertised artifact from both channels, verify its digest and applicable signature, and follow the documented installation/update/uninstall flow. Signing credentials and release secrets stay out of repository content. Branch merging, tagging or a CI preview upload alone does not complete this gate.

The [tag-release workflow and maintainer steps](/SteamWrapper/development/distribution/#prepare-and-trigger-a-release) automate P2; merging does not publish a version. Current source is `0.2.5`; earlier `0.2.3`/`0.2.4` public releases and upgrade trials remain dated evidence. Version tags retain the installer/portable contract and add a separately project-signed update manifest; manual previews remain artifact-only. The project public key and GitHub signing secret are configured, but a new successful tag run and actual feed/download verification are still required. CNB binary mirroring remains unavailable without release credentials and matching assets. Clean-client and retention acceptance remain stable-delivery gates; Foundation approval does not.

## P3. Optional application updates

**Deliverable:** an optional Manager update entry point using P1 replacement/recovery and P2 release trust.

- [x] Implement user-invoked checks and an explicit startup-check preference, off by default. Show the version, release-page link and optional source choice; follow the installed channel automatically.
- [x] Verify project-signed release metadata and downloaded length/hash before confirmed installation through the existing Inno path. The helper rechecks the file after normal Manager exit; portable copies stay manual.
- [ ] Test disabled/offline operation, timeout, missing/malformed metadata, interrupted downloads, corrupt/untrusted packages, busy files and rollback. Failed or skipped updates leave the existing app usable.
- [x] Keep update checks out of Runner's daily game-launch path; add no hidden background service, account requirement or library upload.

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

The old roadmap's Dioxus and Linux/AppImage checks remain historical records at `31a609d:docs/roadmap.md`. Their removal on 2026-10-02 does not change earlier results. Current WinUI configuration, local-first/optional-CDN covers, unsigned installer, tag delivery and project-signed update UI/download/handoff are implemented. Clean-client delivery, retention, public update-feed acceptance and one-click Steam apply/restore remain unfinished. Authenticode is optional. Implementation does not establish unrun acceptance or expand game/achievement guarantees.
