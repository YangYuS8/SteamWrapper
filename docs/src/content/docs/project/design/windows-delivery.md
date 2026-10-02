---
title: "Windows installation, signing, and updates"
description: "Proposed per-user installer, SignPath signing, and optional Manager updates, with implementation and acceptance stages."
---

## Status and scope

**Proposed implementation plan, researched on 2026-10-03.** The maintainer prefers free open-source signing and accepts **SignPath Foundation** as the certificate publisher. No signing subscription, certificate approval, installer, client updater, deployment launcher, or update feed is implemented by this document.

The current product is an unpackaged, self-contained WinUI 3/C# Manager for Windows 11 24H2 x64 and an independent Rust Runner. Daily CI and version-tag/manual portable delivery are implemented. See [current distribution](/SteamWrapper/development/distribution/) for existing behavior; this plan refines P1–P3 of the [roadmap](/SteamWrapper/project/roadmap/), without completing their checkboxes.

## Recommended components

| Area | Proposal | Reason and boundary |
| --- | --- | --- |
| Installer | Pinned Inno Setup 7.1.0 x64, per-user EXE | Familiar English/Simplified Chinese wizard, offline full payload, no routine elevation |
| Manager deployment | One small C# deployment component, a stable Manager launcher, and complete version directories | Installer and updater share one activation/recovery protocol; no Rust management layer or new UI framework |
| Public code signing | Apply to SignPath Foundation | Free OSS preference; application review and signing approval remain external dependencies |
| Update discovery | C# service in Application with an independently signed channel index | Manager-only, disabled by default, no account or library upload |
| Applying updates | User-confirmed invocation of the same verified installer | One installation path; no first-release delta patches or ZIP self-overwrite |
| Portable users | Keep complete ZIP, provide checks and download guidance | No automatic replacement of arbitrary extraction directories |

Microsoft supports including the complete unpackaged self-contained layout in a custom installer. Both .NET and Windows App SDK dependencies must be included; a WinUI single-file executable is not the delivery target. [Microsoft deployment guide](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps).

Inno's version is a researched reference to pin during implementation, not a newly installed repository tool. Use its official download and verify its digest and publisher before adding it to the build. Direct compiler invocation remains supported; mise can offer an optional convenience. [Official downloads](https://jrsoftware.org/isdl.php/Inno-Setup-Downloads).

WiX/MSI/Burn becomes relevant if enterprise deployment is requested. MSIX/Store needs separate package-identity, shared-data and uninstall acceptance. Velopack remains an alternative experiment: its default directory can collide with the existing data root, and its Windows updater can try to terminate processes locking its current directory. It does not remove the need for our data, Runner, trust and process policies. [Velopack Windows lifecycle](https://docs.velopack.io/packaging/operating-systems/windows).

## Installation layout and ownership

Choose the final layout before shipping an installer, to avoid a second migration when application updates arrive:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
  SteamWrapper.exe                 # proposed Manager-only launcher
  installation.json               # validated current/previous installation state
  versions\<release-tag>\          # one complete, immutable Manager layout
    SteamWrapper.Manager.exe
    ...runtime, native and localized resources...
    Runner\SteamWrapperRunner.exe  # bundled resource, not Steam's launch target

%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe       # unchanged stable Steam target
  updates\trust-state.json         # proposed retained sequence/digest/clock state
  logs\, backups\, cache\
    cache\updates\<transaction>\  # proposed bounded download/helper workspace
```

The new launcher starts only Manager. It never appears in Steam Launch Options; daily play continues to use the stable Rust Runner without Manager, launcher, updater or network checks. Installation state is separate from game profiles and UI preferences.

The first installer uses the fixed per-user program root, a constant AppId, current-user uninstall registration and a Start menu shortcut. Desktop shortcuts are optional; no service, scheduled task, startup registration or HKLM write is added. Shortcuts target the stable launcher; Manager retains a consistent AppUserModelID for taskbar pins. A custom install directory can be considered later with its own ownership/path validation.

Set `PrivilegesRequired=lowest`, `CloseApplications=no` and `RestartApplications=no`. An install/update asks existing Manager instances to finish saves and exit normally; it never kills them or a game. Inno's default application-close behavior is not our policy, including silent mode. [Privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [application closing](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm).

Restrict the initial target to actual Windows 11 24H2 x64; ARM64 emulation and older Windows are separate targets. Include matching English/Simplified Chinese installer, recovery and uninstaller text, the canonical icon, license/notice material and a clear explanation of retained data.

## One deployment transaction

Proposed source boundaries are `packaging/windows/` for the Inno definition and `apps/deployment-windows/` for shared C# deployment logic and the launcher/helper. Names are implementation proposals, not existing projects. A small NativeAOT deployment executable is worth prototyping because it can recover without loading the Manager version being replaced; size, build, localization and signature support must be verified.

Inno manages the setup/uninstall entry, registration and shortcuts, and extracts input into a temporary workspace. The deployment component owns the stable launcher and manifest-tracked staging/version directories. Inno's `[Files]` uninstall log does not automatically follow a staging directory renamed by another process; do not rely on it to remove promoted versions. Installation and uninstall hooks must explicitly hand off ownership and lease lifetime to the shared component, including registration/shortcut failures.

Installer, manual repair and app updates call this same deployment protocol; uninstall uses its ownership and exclusive-lease rules:

1. Verify the selected package, version, installed ownership and compatible deployment protocol. Check disk space and reject unsafe roots/reparse points before mutation.
2. Write the complete new payload to a fresh same-volume staging directory. Validate every declared file, localized resource, runtime, bundled Runner and final signed-byte digest. Keep the active version untouched.
3. Obtain an exclusive per-user installation lease for activation. Launcher and every Manager instance participate in the lease from their earliest startup through normal exit. Block new Manager starts during activation, and wait for existing instances and profile/settings writes to finish. A one-time mutex check alone has a race.
4. Record a bounded journal, promote the verified directory and atomically replace the installation-state file with the new current/previous version. Only the deployment component writes this state; Inno and updater do not implement separate engines.
5. Release the installation lease and start Manager through the launcher. Accept a transaction-bound health acknowledgment after normal initialization, without automatic profile migration.
6. Mark healthy in a transaction-bound journal record under a separate short writer lock; this never changes the current-version pointer or upgrades the new Manager's lifetime shared lease to exclusive. Defer cleanup/compaction needing the exclusive installation lease to the next safe window. Clean only manifest-owned obsolete program files after successful activation, retaining at least the last usable version and a verified repair path under a documented disk policy.

Atomic replacement of one state file does **not** prove a whole installer, registry, shortcut and power-loss transaction. Journal recovery, first installation and launcher self-update need actual failure tests. The launcher cannot be replaced while active; reject/defer this condition and do not queue forced replacement at reboot. Run an update helper from a verified independent cache location so it does not overwrite its own executable.

If new Manager exits before health acknowledgment, recover the previous pointer only after reacquiring the exclusive lease and checking data/Runner compatibility. A still-running but slow Manager is not proof of failure: report the timeout and provide recovery, without terminating it or automatically starting a competing version. The first delivery can promise verified manual recovery; unattended startup rollback is a later claim requiring its own evidence.

## Stable Runner and uninstall

Installers own the bundled resource but **not** the stable Runner or data tree. Existing C# `RunnerInstaller` remains the authority for shared Runner installation, manifest/hash recognition and atomic binary replacement. Manager installation itself does not write Steam Launch Options.

Manager-only updates can proceed while a game continues when the old Runner and profile contract remain compatible. Defer stable Runner replacement until safe; do not kill a game to release its binary. The current install service has busy-file handling, but no complete launch-versus-update lifecycle protocol. Add a tested cross-process Runner lease before claiming this coordination, preserving old supported Runners and their recovery behavior. Old Runners do not participate in a newly added lease: keep atomic replacement and Windows busy-file refusal for that compatibility phase, and do not claim race-free coordination merely from upgrading Manager. Incompatibility blocks installation or requires a separate reviewed migration; the first updater supports the existing profile/CLI contract only.

Default uninstall removes only owned Manager versions, launcher, shortcuts and uninstall registration. It acquires the same exclusive installation lease, requests normal Manager exit and blocks new starts until owned-file deletion and Inno registration/shortcut removal finish. Run the verified uninstall helper outside the directory it removes, and test the Inno/helper lease handoff rather than using a one-time process check. Keep profiles, settings, stable Runner, update trust state, logs, backups and caches. Do not add a first-release “delete everything” checkbox: automatic safe Steam Launch Options restoration is not implemented, and manually pasted references cannot be proved absent. Provide separate manual removal guidance. Uninstall deletes only tracked/manifest-owned files and never recursively clears an arbitrary user-selected directory. [Inno uninstall deletion guidance](https://jrsoftware.org/ishelp/topic_uninstalldeletesection.htm).

Portable-to-installed migration copies no game files and keeps the existing data/stable path. Repair preserves unknown data and a newer compatible Runner; relocation, taskbar pins and reinstall after Manager-only uninstall have separate acceptance cases.

## SignPath application and release trust

Prepare a real public WinUI installer preview before applying: a historical release of another implementation is not proof of the requested current form. Review dependencies and licenses, document product behavior, authors/reviewers/approvers, MFA and a bilingual code-signing/privacy policy. Foundation eligibility and approval are not guaranteed. Its terms require traceable own-code builds and human release-signing approval; third-party runtime files keep their upstream signatures. [Foundation conditions](https://signpath.org/terms.html), [application](https://signpath.org/apply).

The maintainer accepts Foundation as publisher. Do not advertise a provided certificate before approval. A valid signature does not promise that Defender, SmartScreen or Smart App Control will accept every new artifact; normal-protection download/launch tests remain necessary. EV does not provide an automatic SmartScreen bypass. [Microsoft SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

Use a SignPath provider adapter, a least-privilege submission token in the protected release environment, and approval in SignPath. PR/main CI and ordinary manual previews cannot access production signing. Signing accepts only reviewed mainline version tags and binds the GitHub-hosted build, source commit and uploaded artifact identity; self-reported JSON provenance is insufficient. Confirm service compatibility with the chained signing stages during onboarding. [SignPath GitHub origin verification](https://docs.signpath.io/trusted-build-systems/github).

Azure Artifact Signing is a conditional fallback if the maintainer meets its legal-identity eligibility; creating an Azure resource in another region is not identity approval. A paid CA/HSM option would require a separate budget decision. Neither is required for the selected free-first plan. [Microsoft eligibility](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart).

## Signing order and version rules

The future signed release sequence is:

```text
Review tag and repeat all gates
→ build full Manager/Runner/deployment payload and prepare Inno's uninstaller stub
→ sign project-owned PE files and the uninstaller stub, verify timestamp and Windows trust
→ regenerate Runner manifest using the final signed Runner bytes
→ build ZIP and Setup from the unchanged verified payload
→ sign the final Setup executable
→ inspect installed/archived payload, signatures and all final digests
→ generate release metadata/checksums and separately sign update metadata
→ upload/download-verify immutable assets, publish Release, then advance channel index
```

There are separate payload/stub and final-installer signing stages; Foundation approval might be needed more than once. Confirm provenance acceptance for the Inno-generated stub and second request during onboarding, rather than relying on a manually signed binary from outside the reviewed build. Do not assume one nested-signing request can change Runner bytes after its manifest is sealed. Sign the uninstaller before Inno embeds it; preserve its localization message files and verify its installed signature. [Inno signed uninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm).

Use SHA-256 and trusted RFC3161 timestamps, verify Windows Authenticode including expected identity, and treat missing timestamps/warnings as signing gate failures. Never re-sign third-party runtime files with the project's identity. The ZIP is a container: sign its own PE contents and bind the ZIP's final digest through independently signed metadata; do not describe it as an Authenticode-signed ZIP. [Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).

For application-performed offline verification, use WinVerifyTrust's `WTD_CACHE_ONLY_URL_RETRIEVAL`; merely disabling revocation checks does not prevent other certificate retrieval. Cached trust is not proof of fresh revocation status. Missing trusted chain/timestamp evidence fails validation with a repair/offline explanation, rather than accepting an untrusted package. Online revocation validation during an explicitly authorized update may contact certificate-authority endpoints separately from GitHub artifact requests; document bounded timeouts and unreachable/revoked outcomes. No such query starts from Runner or an ordinary offline Manager launch. Operating-system checks and warnings remain separate from the application's requests. [Microsoft trust flags](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/ns-wintrust-wintrust_data).

Current `Invoke-WinUI.ps1` calculates Runner SHA-256 before any signing. Split staging from final manifest generation. Current Runner has no version JSON probe or Windows version-resource build step; add and test own PE metadata without executing unknown installed binaries. Explicitly set every own EXE/DLL/stub to `ProductName=SteamWrapper` and the matching product version required by Foundation, including Application, localized own assemblies, launcher/helper and uninstaller. Application currently lacks an explicit version; SDK informational versions may append the source hash, so do not assume they match Manager/Rust product versions. Keep the source commit in release metadata. Current `RunnerInstaller` compares three-part numeric versions and rejects same-version/different-hash bytes, so signing or timestamp changes can cause installation conflicts.

For the first signed series, retain the current coordinated numeric versions and advance their base for every newly built/signed release. For example, do not freshly sign different Runner bytes for both `v0.2.1-preview.1` and `v0.2.1-preview.2` while still calling each Runner `0.2.1`. Introduce signing with a new unused base; do not re-sign an existing public tag. Reuse the exact immutable signed artifact when retrying a failed publishing job. Independent component contracts/versions and reuse of an unchanged signed Runner can be designed later with explicit compatibility metadata and a provider-approved artifact policy; they must not contradict the shared product-version restrictions. Do not simply remove version gates.

## Optional update behavior and authentication

Start with a visible **Check for updates** action. Default automatic checks are off. An explicit preference may check periodically while Manager is open; automatic download is a separate option, and applying an update always needs confirmation. Disabling cancels work. No service, startup task, permanent tray process, Runner request, game update or game-data upload is introduced. UI/preferences/errors must be complete in both languages and preserve unknown existing settings.

Use separate signed stable/preview indexes. The default channel follows the installed flavor; stable never silently switches to preview. WinUI currently remains a preview, so no stable index may imply that stable WinUI delivery exists. Show version, channel, changes, size and source before installation. Declining, going offline or having stale metadata leaves configuration and Steam launching usable.

Proposed indexes bind app ID, platform/minimum OS, channel, SemVer/numeric component versions, source commit, profile/Runner/deployment compatibility, artifact URLs and final SHA-256/length, increasing channel sequence, issuance and expiration. Verify a detached signature over the exact UTF-8 bytes **before** strict duplicate-rejecting JSON parsing. Embed a project-controlled update trust root; an unrelated legitimately Foundation-signed program must not be accepted just because its certificate subject is the same.

An initial ECDSA P-256 metadata-signing adapter can use .NET cryptography with a separately protected release key; it is not the Foundation's Authenticode private key. Define key IDs, format, rotation authorized by existing trust and recovery for lost/compromised keys. Store each channel's highest accepted sequence, exact index digest and clock state atomically in retained `updates/trust-state.json`, outside the clearable download cache. Allow the same sequence with the same digest for retries; reject an older sequence or the same sequence with different bytes. Cache clearing and default Manager uninstall do not reset this state. Report expired metadata or clock rollback/uncertainty as inability to establish freshness, not “up to date”; these conditions block updating, not offline configuration or Steam launching. These are selected update-security requirements, not a claim to implement the complete TUF specification. [TUF metadata model](https://theupdateframework.io/docs/metadata/).

Publish discovery indexes in a dedicated protected generated-metadata branch, read from fixed official GitHub URLs; do not let a release job commit generated feeds into `main` or redeploy documentation. This branch is not development source and triggers no application build. Advance it only after verified release assets are available. Renew expiring metadata through a narrowly scoped refresh workflow that signs metadata but does not rebuild/re-sign binaries. Concurrent feed changes use a compare-and-swap update and monotonic sequence. Final key custody, expiration/renewal intervals and branch rules are implementation setup decisions.

First enable GitHub downloads. Disable automatic redirects; check each HTTPS hop against explicitly verified GitHub release-storage hosts, with no cookies, credentials, downgrade or arbitrary/local destinations. Proposed starting limits are 512 KiB metadata, a 512 MiB maximum package, five redirects and a 512 MiB update-cache quota, with bounded time/concurrency and manifest-declared real byte limits. Discover actual storage hosts during acceptance; an unknown host fails safely rather than widening the allowlist. CNB fallback comes after matching signed bytes and its storage path are tested. Store unique partial downloads under `cache/updates/`; verify size/hash, signed metadata and Authenticode before marking an installer usable. Cache cleanup touches only owned update downloads, never covers or the rest of user data.

For installed Manager, confirmed updates finish saves in all instances, exit naturally and let a verified independent helper call the same installer. Pass a validated installation receipt and transaction ID, not an arbitrary command or URL. For portable Manager, offer verified download and new-directory instructions; no automatic write to its extraction directory.

## Release workflow changes

Preserve daily compilation/tests and tag-only deliverable building. Extend the current metadata schema and validators before adding installer/signature assets: today they deliberately accept exactly five portable-preview assets with `signed=false` and `installer=false`. Future manifests must explicitly enumerate type, digest and signature policy for every downloadable artifact; old-format validation remains versioned rather than silently weakened.

Tag releases add signing approvals, Setup/uninstaller inspection and clean-client evidence. A required-signed channel fails when signing/approval/timestamp verification is unavailable; it cannot silently publish unsigned files. Explicit unsigned previews remain a separate labeled path and are not accepted by the authenticated updater. Manual dispatch continues to produce preview artifacts without a public Release.

Upload the same final immutable bytes to GitHub and configured CNB. Publish channel metadata only after advertised assets are verified. If CNB fails, advertise GitHub availability without describing CNB as complete; add the mirror only after verification. Retrying consumes the already signed artifact, not a new signature timestamp. Signing approval expiry or artifact-retention expiry needs a documented new-version/recovery path.

## Implementation stages and completion gates

| Stage | Concrete work | Gate before proceeding |
| --- | --- | --- |
| D1a: isolated installer prototype | Pin Inno; prototype C# launcher/deployment boundary; final layout, dual-language setup, shortcuts, Manager-only uninstall and portable migration | Disposable clean supported Windows, standard account, offline installation, both languages, stable data path and retained Runner; no SDK/runtime preparation |
| D1b: installation recovery | Shared installation lease, complete version staging, journal/pointer, launcher upgrade, manual repair and owned-file cleanup | Real-process concurrency, interrupted phases, lock/disk/reparse failures, taskbar identity, recovery and no mixed-version DLLs |
| D2: signing readiness | Public installer preview, dependency/license inventory, Runner PE metadata, signing policy/roles/MFA and Foundation application | A reviewed application dossier and actual provider approval; no unsupported claim of certificate availability |
| D3: signed releases | Two-stage signing integration, signed uninstaller, post-sign Runner manifest, versioned artifact schema and update trust root/index | Wrong signer/tamper/timestamp/hash/version rejection; inspected downloadable signed installer and ZIP; matching advertised mirrors |
| D4: check-only updates | Dual-language update UI/preferences, signed-index verification, channels, freshness and bounded network/cache | No request before opt-in or after disable, correct offline/rate-limit/error behavior, rollback/freeze/key-rotation tests; no writes to app/game files |
| D5: confirmed installation | Verified download and on-demand helper calling the accepted installer, multi-instance save/exit, compatible Runner deferral | End-to-end upgrade/repair and clean-client failure recovery; portable stays manual; no killed game or overwritten profile |
| Stable qualification | P0 native/player gates plus accepted installer/signing/updates scope and documented support | Fresh download with Windows protections enabled and separately authorized real Steam tests; no expansion of game/achievement claims |

D1 implementation can start while signing preparation is researched. D1a is an isolated prototype; a public upgradeable installer preview requires D1b acceptance, before submitting the current-form D2 application. D2 approval time is external and no calendar deadline is promised. Check-only updates can be developed against fixtures before D3, but public authenticated installation requires D1b and D3. Automatic downloads or unattended startup rollback do not block the first reliable installer.

## Acceptance matrix

| Area | Required observations |
| --- | --- |
| Clean installation | Supported Windows 11 x64 without SDKs, normal non-admin user, offline use, English/Chinese, Chinese/spaced user paths, two Windows users kept separate |
| Ownership | Wrong root, custom Steam/game/data locations, junctions, unknown files, repeated install/repair and Manager-only uninstall; no unrelated deletion |
| Concurrency | Multiple Managers, pending/active saves, new launch during activation, two installers/helpers, locked launcher and active Runner/game; no forced exits |
| Interruption | Fail/stop at each journal/file/state/shortcut/registry phase, disk full, antivirus/file locks, stale journal, failed startup, late health acknowledgment and manual recovery |
| Signing | Unsigned/wrong identity, altered PE, missing/bad timestamp, expired timestamped certificate, cached offline trust and missing chain, online revocation/unreachable response, pre-sign Runner hash, same-version changed bytes and shared-publisher unrelated package |
| Update metadata | Bad signature/key rotation, duplicate/malformed JSON, old sequence, same-sequence changed bytes, retained trust state after cleanup/uninstall, expiry/clock problem, wrong app/platform/channel/contract and substituted artifact |
| Network/cache | Disabled/offline, timeout/429/404, malicious redirect, streaming length overflow, partial/corrupt download, cancellation and quota; covers/user files retained |
| Product continuity | Stable Runner launches with Manager closed after upgrade/uninstall; profiles/options/saves intact; portable relocation and pinned taskbar shortcuts preserved |

Automated tests use disposable fixtures and real process behavior; clean VM installer runs are a separate gate from hosted Windows Server compilation and existing development publish tests. Live Steam acceptance remains scoped and authorized, with selected Launch Options recorded/restored and game/save integrity verified. Do not choose between conflicting save/cloud progress.
