---
title: "Windows installation, signing, and updates"
description: "Per-user installation, project-signed updates, optional Windows code signing, and remaining acceptance gates."
---

## Status and scope

**Updated decision, 2026-10-05:** the maintainer reported that the SignPath Foundation application was declined. Windows Authenticode is now an optional improvement, not a prerequisite for releases or application updates. No refusal reason or certificate availability is assumed. The project uses its own update-signing key, independently of Windows publisher certificates.

The unpackaged, self-contained WinUI 3/C# Manager, Rust Runner, Inno installer, deployment journal and ordinary version-tag publication remain the product architecture. **[v0.2.7](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.7) is the first stable Windows release**, with a bounded support scope: Windows 11 24H2 x64, using the same Windows account as Steam with ordinary permissions. The update dialog, official-source downloads and user-confirmed installer handoff are implemented; automatic checks remain off by default.

The exact tag commit is `0987802b86460eff711c6cf694015cdbf086bbb2`; [release run 37500459000](https://github.com/YangYuS8/SteamWrapper/actions/runs/37500459000) passed all nine jobs. GitHub and CNB each passed anonymous seven-asset hash inspection, and both sites' stable/preview feeds passed real project-key signature, freshness and exact-installer binding checks. These publication checks did **not** execute the public `v0.2.7` Setup. Private installation/portable results and the earlier public CNB update retain their own bytes and environments. See [distribution](/SteamWrapper/development/distribution/) and [testing](/SteamWrapper/development/testing/) for current commands and exact evidence.

## Recommended components

| Area | Current choice | Reason and boundary |
| --- | --- | --- |
| Installer | Pinned Inno Setup 7.1.0 x64, per-user EXE | Familiar English/Simplified Chinese wizard, offline full payload, no routine elevation |
| Manager deployment | One small C# deployment component, a stable Manager launcher, and complete version directories | Installer and updater share one activation/recovery protocol; no Rust management layer or new UI framework |
| Public code signing | Optional future Authenticode | Application updates use a project key; no certificate application is required |
| Update discovery | C# service in Application with an independently signed channel index | Manager-only, disabled by default, no account or library upload |
| Applying updates | User-confirmed invocation of the same verified installer | One installation path; no first-release delta patches or ZIP self-overwrite |
| Portable users | Keep complete ZIP, provide checks and download guidance | No automatic replacement of arbitrary extraction directories |

Microsoft supports including the complete unpackaged self-contained layout in a custom installer. Both .NET and Windows App SDK dependencies must be included; a WinUI single-file executable is not the delivery target. [Microsoft deployment guide](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps).

Inno 7.1.0 x64 is pinned in `packaging/windows/inno-toolchain.json`; the toolchain script verifies its official download digest and publisher and installs it under ignored `target/toolchain`. Direct commands remain supported; mise offers optional aliases. [Official downloads](https://jrsoftware.org/isdl.php/Inno-Setup-Downloads).

WiX/MSI/Burn becomes relevant if enterprise deployment is requested. MSIX/Store needs separate package-identity, shared-data and uninstall acceptance. Velopack remains an alternative experiment: its default directory can collide with the existing data root, and its Windows updater can try to terminate processes locking its current directory. It does not remove the need for our data, Runner, trust and process policies. [Velopack Windows lifecycle](https://docs.velopack.io/packaging/operating-systems/windows).

## Installation layout and ownership

The shipped default Manager program root is separate from the stable data root. First installation can select another validated empty directory on a fixed local drive:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
  SteamWrapper.exe                 # implemented Manager-only launcher
  installation.json               # validated current/previous installation state
  versions\<release-tag>\          # one complete, immutable Manager layout
    SteamWrapper.Manager.exe
    ...runtime, native and localized resources...
    Runner\SteamWrapperRunner.exe  # bundled resource, not Steam's launch target

%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe       # unchanged stable Steam target
  updates\trust-state.json         # retained sequence/digest/clock state
  logs\, backups\, cache\
    cache\updates\<transaction>\  # bounded download and one-shot helper workspace
```

The stable launcher starts only Manager. It never appears in Steam Launch Options; daily play continues to use the stable Rust Runner without Manager, launcher, updater or network checks. Installation state is separate from game profiles and UI preferences.

First installation permits a validated empty directory on a fixed local drive, defaulting to the program root above. The per-user AppId and registered location identify the installation; updates and repairs remain there. The Start menu shortcut defaults on and desktop shortcut defaults off; the completed setup can open Manager. No service, scheduled task, startup registration or HKLM write is added. Shortcuts target the stable launcher; Manager retains a consistent AppUserModelID for taskbar pins. Local silent process steps, scoped English/Chinese native flows and the private SDK-free candidate lifecycle have passed; [Testing](/SteamWrapper/development/testing/) distinguishes their payloads, harness retries and remaining acceptance.

Set `PrivilegesRequired=lowest`, `CloseApplications=no` and `RestartApplications=no`. An install/update requires existing Manager instances to finish saves and exit normally; it never kills them or a game. Inno's default application-close behavior is not our policy, including silent mode. [Privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [application closing](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm).

Restrict the initial target to actual Windows 11 24H2 x64; ARM64 emulation and older Windows are separate targets. Include matching English/Simplified Chinese installer, recovery and uninstaller text, the canonical icon, license/notice material and a clear explanation of retained data.

## One deployment transaction

Implemented source boundaries are `packaging/windows/` for Inno and `apps/deployment-windows/` for shared C# deployment logic and the NativeAOT launcher/helper. It recovers without loading the replaced Manager. Version retention/pruning and scoped shortcut/registration recovery are implemented and tested. Graceful cross-instance shutdown requests and whole power-loss recovery remain separate work; busy operations are refused and users are asked to close Manager normally.

Inno manages the setup/uninstall entry, registration and shortcuts, and extracts input into a temporary workspace. The deployment component owns the stable launcher and manifest-tracked staging/version directories. Inno's `[Files]` uninstall log does not automatically follow a staging directory renamed by another process; do not rely on it to remove promoted versions. Installation and uninstall hooks must explicitly hand off ownership and lease lifetime to the shared component, including registration/shortcut failures.

Installer, manual repair and app updates call this same deployment protocol; uninstall uses its ownership and exclusive-lease rules:

1. Verify the selected package, version, installed ownership and compatible deployment protocol. Check disk space and reject unsafe roots/reparse points before mutation.
2. Write the complete new payload to a fresh same-volume staging directory. Validate every declared file, localized resource, runtime, bundled Runner and final signed-byte digest. Keep the active version untouched.
3. Obtain an exclusive per-user installation lease for activation. Launcher and every Manager instance participate in the lease from their earliest startup through normal exit. Block new Manager starts during activation, and wait for existing instances and profile/settings writes to finish. A one-time mutex check alone has a race.
4. Record a bounded journal, promote the verified directory and atomically replace the installation-state file with the new current/previous version. Only the deployment component writes this state; Inno and updater do not implement separate engines.
5. Release the installation lease and start Manager through the launcher. Accept a transaction-bound health acknowledgment after normal initialization, without automatic profile migration.
6. Mark healthy in a transaction-bound journal record under a separate short writer lock; this never changes the current-version pointer or upgrades the new Manager's lifetime shared lease to exclusive. Defer cleanup/compaction needing the exclusive installation lease to the next safe installation or repair. Prune only manifest-owned obsolete program files after the current version has acknowledged health, retaining the current and recorded previous version. A recorded previous pointer is not evidence that this previous Manager initialized successfully.

Version admission is bounded to 32 directories and a 32 MiB ownership journal. Installation can temporarily leave three versions until the next safe pruning opportunity. Uninstall supports up to 1,024 legacy versions within the same journal bound, without recursively clearing unknown files or recovery quarantine. Retention tests and real frozen old-helper recovery fixtures passed; synthetic payloads and simulated health in those legacy fixtures do not prove old Manager UI startup. The implementation preserves the older journal/state contract rather than rewriting historical installation metadata.

Atomic replacement of one state file does **not** prove a whole installer, registry, shortcut and power-loss transaction. Journal recovery, first installation and launcher self-update need actual failure tests. The launcher cannot be replaced while active; reject/defer this condition and do not queue forced replacement at reboot. Run an update helper from a verified independent cache location so it does not overwrite its own executable.

If new Manager exits before health acknowledgment, recover the previous pointer only after reacquiring the exclusive lease and checking data/Runner compatibility. A still-running but slow Manager is not proof of failure: report the timeout and provide recovery, without terminating it or automatically starting a competing version. The first delivery can promise verified manual recovery; unattended startup rollback is a later claim requiring its own evidence.

## Stable Runner and uninstall

Manager installation/update owns the bundled resource and does not replace the stable Runner or data tree. Existing C# `RunnerInstaller` remains the authority for shared Runner installation, manifest/hash recognition and atomic binary replacement. Manager installation itself does not write Steam Launch Options. Explicit uninstall choices below provide the only narrowly scoped exception for removal.

Manager-only updates can proceed while a game continues when the old Runner and profile contract remain compatible. Defer stable Runner replacement until safe; do not kill a game to release its binary. The current install service has busy-file handling, but no complete launch-versus-update lifecycle protocol. Add a tested cross-process Runner lease before claiming this coordination, preserving old supported Runners and their recovery behavior. Old Runners do not participate in a newly added lease: keep atomic replacement and Windows busy-file refusal for that compatibility phase, and do not claim race-free coordination merely from upgrading Manager. Incompatibility blocks installation or requires a separate reviewed migration; the first updater supports the existing profile/CLI contract only.

Default uninstall removes only owned Manager versions, launcher, shortcuts and uninstall registration, preserving separate data. It holds the same exclusive installation lease until file removal and Inno registration/shortcut removal finish. The verified uninstall helper runs outside the removed directory. Actual isolated Inno/helper process tests and the private SDK-free lifecycle cover this handoff; they do not establish every production failure combination.

Seven independent, default-off choices remove recognized SteamWrapper Launch Options, downloaded caches, logs, Manager preferences, profiles, exact profile backups, or verified stable Runner files. With Steam stopped, restoration backs up affected account files, clears only the exact generated command for this stable Runner/AppID, preserves other bytes and rejects concurrent changes. Custom commands remain untouched; clearing a command cannot recover unknown earlier arguments. Profiles/Runner deletion additionally requires all local accounts to be readable and free of remaining Runner references. Runner deletion holds its installation lock and validates actual bytes against supported sidecar or hash-addressed metadata; profile/setting/cache cleanup respects the corresponding writer locks.

Unknown or busy files, Steam restoration backups and `updates/trust-state.json` remain. No option touches games/saves, follows links or recursively clears a directory. Cleanup can report retained files without pretending that all selected data was removed. Nine actual cleanup selections passed against frozen `0.2.6` installer logic; shortcut and registration recovery passed in separately recorded portions, while the original combined run remains failed. Scoped English/Chinese native cancellation, cache cleanup and default-uninstall results also remain separate. These results do not establish all production `0.2.7` cleanup, language or failure combinations. [Inno uninstall deletion guidance](https://jrsoftware.org/ishelp/topic_uninstalldeletesection.htm).

Portable-to-installed use copies no game files and keeps the existing data/stable path. There is no in-place relocation: uninstall Manager while keeping data, then install into the new empty directory. Repair preserves unknown data and a newer compatible Runner; chosen directories, taskbar pins and reinstall after Manager-only uninstall have separate acceptance cases.

## SignPath application and release trust

The declined Foundation application and prepared provider tooling are recorded in the [code-signing policy](/SteamWrapper/project/design/code-signing/). Those drafts remain available if a future provider is selected. No subscription or production Authenticode signing is active.

Current Setup and project-owned PE files remain unsigned in the Windows sense. Signed update metadata authorizes their exact bytes to SteamWrapper; it does not create a trusted Windows publisher or remove operating-system prompts. A valid Authenticode signature would not guarantee warning-free SmartScreen behavior either. [Microsoft guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

## Signing order and version rules

The active release sequence is: build and test the complete payload, package Setup and ZIP, publish and download-verify the immutable version assets, then sign and publish the independent update index. The seven-asset schema-2 package remains explicitly `signed=false`; the legacy portable contract is unchanged.

`packaging/windows/update-trust.json` holds only public ECDSA P-256 keys. `Initialize-UpdateSigning.ps1` creates a private key in memory and sends it directly to the repository secret `STEAMWRAPPER_UPDATE_PRIVATE_KEY` through `gh` stdin. It refuses to replace existing trust. PR/main tests use disposable keys; only version publication and metadata renewal receive the real signing secret. This authenticates the project feed and bound installer hash, not the Windows publisher identity.

Every newly built installable payload advances the coordinated numeric version, including Manager, Application, Deployment, Host and Rust products. Same-version different bytes and silent downgrades remain rejected. Never move a published version tag or overwrite its assets. If Authenticode is added later, use another unused numeric version, sign owned PE/uninstaller files before final Setup, regenerate the Runner manifest after signing, and preserve upstream signatures. Existing `WindowsSigning.ps1` and provider drafts cover that optional future path.

For key rotation, first ship a client that trusts the next public key while the old key can still sign its update; switch publishing only afterwards. Losing the sole signing key requires a manually downloaded new client. Repository access and signing-secret custody remain maintainer responsibilities; no certificate authority manages this key.

## Optional update behavior and authentication

Players use **Check for updates**, download the offered version, and confirm installation. Automatic checks default off and run only while Manager is open after opt-in. A manual check does not enable them. Closing or cancelling ends the active request; ordinary Steam launches never check for updates. Release channel follows the installed version; source selection defaults to automatic, with GitHub/CNB choices under download-source options.

The fixed official `update-preview`/`update-stable` Releases contain `SteamWrapper-update.json`. Its envelope signs exact payload bytes before parsing the schema-2 product/channel/version/contract fields, installer SHA-256/length and optional CNB URL. The application accepts only configured project keys and fixed official repository paths. Missing feeds, invalid signatures, replay, expired metadata or clock rollback are failures, never evidence that the app is current. Sequence/clock state remains outside the clearable cache. A CNB mirror is advertised only after its matching installer has been verified.

All request and redirect hops use explicit HTTPS hosts, without credentials or cookies. Metadata is limited to 512 KiB; installers to 512 MiB; at most five redirects are followed. Downloads have cancellation, time/length/hash limits and a bounded `cache/updates/` directory, including a small allowance for the one-shot helper. Unknown files and reparse points are preserved or refused. Only recognized inactive update files are candidates for cleanup; profiles, covers, Steam and game files are untouched.

Installed Manager finishes the player's save/discard decision, starts a verified copy of the existing deployment host, and closes normally. The host waits for that exact process to exit, verifies and locks the installer again, runs Inno with visible progress and no restart/force-close permission, checks the activated release, then reopens Manager. Other Manager instances can block installation and require a normal close/retry. Existing journal/repair/rollback rules remain; no unattended rollback or game-process coordination is claimed. Portable copies offer the version download page and new-directory instructions instead of replacing arbitrary folders.

## Release workflow changes

Ordinary merges run CI; version tags build and publish application packages. Manual dispatch keeps producing preview artifacts only. The immutable seven-asset Setup/portable release contract and full release gates remain unchanged.

After GitHub publication and any verified CNB mirroring, a separate job publishes project-signed metadata to the rolling update Release. A weekly workflow renews the previously verified index for 28 days without selecting new binaries or rebuilding software. Publication and renewal share a concurrency group; renewal preserves the exact release identity and installer digest and advances the sequence. Only this dedicated metadata asset is mutable. Versioned installers remain immutable.

GitHub is the primary source; CNB is now a verified binary mirror and signed-feed fallback for `v0.2.7`. CNB needs tag-sync and release-write permissions; release operations prefer CNB_RELEASE_TOKEN and otherwise reuse a sufficiently scoped CNB_GIT_TOKEN; a source-only mirror is not a download source. Skipped or failed binary mirroring must not appear as a working mirror in the signed index. Secrets are never embedded in clients. Source changes, configured keys and successful local tests do not themselves establish that the public feed is available; the current release has separate anonymous publication evidence.

## Implementation stages and completion gates

| Stage | Current implementation | Remaining acceptance |
| --- | --- | --- |
| D1a/D1b installer and recovery | Inno, validated per-user root, leases, journal, repair/rollback and bounded retention; private `0.2.7` ordinary-permission lifecycle (same primary SID, Users/Medium, 14 steps), portable lifecycle (10), genuine isolated `0.2.6` → `0.2.7` Inno/maintenance (13), and separately scoped cleanup/recovery | Fresh primary standard-account sign-in, two-user GUI, multi-monitor, physical power loss and all language/failure combinations remain unverified. The disk-full VHD copy/recovery result has `actualInno=false`. |
| D2 version delivery | `v0.2.7` tag gates passed; seven immutable assets verified anonymously on both GitHub and CNB | Public `0.2.7` download inspection did not execute Setup; every future release needs its own publication evidence. |
| D3 Windows code signing | Optional preparation tools retained; Foundation application declined | Future provider setup only if selected; no longer blocks D4/D5 |
| D4 update checks | Bilingual UI, opt-in checks, replay/freshness protection; all four public `0.2.7` stable/preview feeds verified with the real key and exact installer binding | Enabled-startup checks and broader native/offline/cancel combinations remain unverified. Automatic checks are off by default; a verified feed is not a completed installation. |
| D5 confirmed installation | Real public CNB `0.2.5` → `0.2.6` update passed all 12 steps, including UI download, normal exit, actual Setup and healthy restart; genuine isolated `0.2.6` → `0.2.7` Inno/maintenance upgrade and rollback passed separately | The GitHub download timed out safely with no installer run and unchanged old state/data. Public `0.2.7` Setup execution and broader network/language matrices remain unverified; portable replacement stays manual. |
| Stable qualification | First stable `v0.2.7` released for Windows 11 24H2 x64, same Windows account as Steam with ordinary permissions | The bounded release does not claim fresh primary standard-account sign-in, separate-user desktops, two-user GUI, multi-monitor or full power-loss recovery. |

Historical `0.2.4` clients have no update UI, so one manual installation bootstraps future application updates. `0.2.7` is a new coordinated numeric payload; a changed prerelease suffix alone never authorizes different bytes under the same numeric version. Keep old binaries for real upgrade/rollback evidence rather than editing their metadata to simulate a new release.

The public Setup hash is `ac08f321a607ea1e806c146f7d9bdcb1de7df29a72bb7d7e37c5675911e627c5`. The actual private `0.2.7` ordinary-permission lifecycle used Setup hash `5c9ab6482f67711bc61813563e687cf13c2f10b79f47a1930127502e3b4a6b5f`; its portable, isolated upgrade, cleanup and VHD fixtures have separately recorded payloads. Those successful runs do not substitute for execution of the later public bytes. Preserve unknown files and quarantined stages, and never delete retained versions merely to satisfy a cache quota. Local isolation and SDK-free Sandbox results retain their distinct environments.

## Acceptance matrix

This matrix describes the broader test surface, not a list of gates all claimed passed by `v0.2.7`. Current scoped results are above and in [Testing](/SteamWrapper/development/testing/). Authenticode-specific cases apply only if that optional signing path is adopted.

| Area | Required observations |
| --- | --- |
| Clean installation | Supported Windows 11 x64 without SDKs, normal non-admin user, offline use, English/Chinese, Chinese/spaced user paths, two Windows users kept separate |
| Ownership | Wrong root, custom Steam/game/data locations, junctions, unknown files, repeated install/repair and Manager-only uninstall; no unrelated deletion |
| Concurrency | Multiple Managers, pending/active saves, new launch during activation, two installers/helpers, locked launcher and active Runner/game; no forced exits |
| Interruption | Fail/stop at each journal/file/state/shortcut/registry phase, disk full, antivirus/file locks, stale journal, failed startup, late health acknowledgment and manual recovery |
| Signing | Unsigned/wrong identity, altered PE, missing/bad timestamp, expired timestamped certificate, cached offline trust and missing chain, online revocation/unreachable response, pre-sign Runner hash, same-version changed bytes and shared-publisher unrelated package |
| Update metadata | Bad signature/key rotation, duplicate/malformed JSON, old sequence, same-sequence changed bytes, retained trust state after cleanup/uninstall, expiry/clock problem, wrong app/platform/channel/contract and substituted artifact |
| Network/cache | Disabled/offline, timeout/429/404, malicious redirect, streaming length overflow, partial/corrupt download, cancellation and quota; covers/user files retained |
| Product continuity | Stable Runner launches with Manager closed after upgrade/default Manager-only uninstall; profiles/options remain unless explicitly selected for removal; games/saves always intact; custom installation location and shortcut choices preserved |

Automated tests use disposable fixtures and real process behavior; clean VM installer runs are a separate gate from hosted Windows Server compilation and existing development publish tests. Live Steam acceptance remains scoped and authorized, with selected Launch Options recorded/restored and game/save integrity verified. Do not choose between conflicting save/cloud progress.
