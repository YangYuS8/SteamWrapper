---
title: "Windows installer preview"
description: "Build, try, repair and remove the unsigned per-user installer, with explicit preview limits."
---

## Current boundary

The Inno Setup installer and C# deployment component are implemented for **Windows 11 24H2 or newer, x64**, as a **technical preview without Windows Authenticode signing**. They include the complete self-contained WinUI layout, both languages and the independent Runner. Normal branch CI tests and compiles source; it does not produce a setup executable. Explicit manual runs build preview artifacts only. Version-tag delivery packages Setup and portable ZIP using the explicit schema-2 contract, retaining the original portable validator. Authenticode is optional; the stable-delivery gates in the [execution queue](/SteamWrapper/project/roadmap/#execution-queue-2026-10-03) remain open.

This is not an Authenticode-signed or stable release. Isolated process tests on a development machine or hosted Windows Server do not establish clean Windows 11 acceptance. The remaining clean-client, normal-protection download, multi-user, scaling and real Steam delivery gates are recorded in the [delivery plan](/SteamWrapper/project/design/windows-delivery/). Do not disable Windows protection to run the preview.

[v0.2.5-preview.1 is publicly available](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.5-preview.1) as a GitHub prerelease, published on 2026-10-05 in China (2026-10-04 20:57:52 UTC). Its seven assets include Setup (49,901,116 bytes), portable ZIP (73,765,434 bytes) and bilingual notes. The [release workflow](https://github.com/YangYuS8/SteamWrapper/actions/runs/37232987692) passed the final installer/options gates. Use the [Setup-first installation guide](/SteamWrapper/guides/installation/). A CNB binary mirror is advertised only after its upload and download verification succeeds.

## Build a preview

With the documented Windows development tools installed, run from the repository root:

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Install-WinUIInstallerToolchain.ps1
pwsh -NoProfile -File scripts/windows/New-WinUIInstaller.ps1 -Tag v0.2.5-preview.1
```

The last command produces `target/winui/installers/v0.2.5-preview.1/SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe` and inspection metadata for the current `0.2.5` source. The tag must match the numeric source version. It labels a local artifact; the command does not create a Git tag or publish a Release. Do not reuse a public version for changed bytes. Earlier artifacts and genuine numeric upgrade/rollback results remain dated historical evidence.

Changing only the prerelease suffix does not provide an upgrade path: the deployment manifest changes while the numeric version remains the same, and installation rejects different content at the same base. New installable payloads need a new coordinated three-part source/product version; retry an existing build with its exact immutable files. See [release version rules](/SteamWrapper/development/distribution/#prepare-and-trigger-a-release).

Inno Setup 7.1.0 x64 is downloaded only from the official site, with the pinned SHA-256 and publisher signature verified. It is installed under `target/toolchain`; contributors may also supply a matching verified compiler using `-Compiler`. mise aliases are optional conveniences. Developer SDKs and Inno are build tools, not player requirements.

For disposable acceptance:

```powershell
pwsh -NoProfile -File scripts/windows/Test-WinUIHostLanguage.ps1
pwsh -NoProfile -File scripts/windows/Test-WinUIInstallerScripts.ps1
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1
```

The Host-language command runs five real final NativeAOT maintenance processes under a fresh `target/winui/host-language-acceptance/<id>` fixture. Without a CLI language override, it checks the actual Windows UI language for missing or language-less preferences, explicit English/Chinese choices and malformed-settings fallback, preserving fixture bytes and the published Host. It reads no real user preferences. The 2026-10-03 local run passed on `zh-CN` Windows; this is not acceptance on every system language or a clean client.

The latter runs real setup, compatible maintenance rollback and uninstall processes under a fresh repository `target` root, with a distinct test AppId and shortcuts redirected to a disposable fixture directory. Its default synthetic next-version bundle tests the deployment transaction only; it is not a real next-version build or signing evidence. It never uses the real game library. The script reports the isolated directory containing its logs and `evidence.json`; its path includes Chinese text, spaces and an apostrophe to test path handling.

For genuine numeric-version upgrade acceptance, freeze the complete old portable publication before replacing it, reject reparse/private inputs, and record source/copy hashes. Build the new coordinated source/product version normally; changing the old Runner manifest or PE metadata does not create a new-version binary. The following historical `0.2.3` → `0.2.4` example requires those exact frozen publications; replace `REPLACE_WITH_ID` with the recorded baseline directory name and choose the actual coordinated versions for a new run:

```powershell
$baseline = 'target/winui/upgrade-baselines/REPLACE_WITH_ID/v0.2.3'
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1 `
  -PublishDirectory $baseline `
  -UpgradePublishDirectory target/winui/publish `
  -Tag v0.2.3-installertest.1 `
  -UpgradeTag v0.2.4-installertest.1
```

When an upgrade publication is supplied, the script checks all seven own PE product/version fields in both layouts before invoking the compiler or installer. The expected successful evidence includes `numericUpgradeUsesSyntheticMetadataFixture=false` and a compatible rollback executed by the actual maintenance process, followed by reactivation through the real upgraded installer. Inspect the recorded tags, versions, owned-file preservation and user-data hashes. This command uses the isolated test root, not the production installation. Local success still does not establish clean Windows, native wizard/Explorer, multi-user or every interruption/registry/shortcut failure gate. No clean VM was available for the local 2026-10-03 preparation.

The completed `0.2.3` local run on 2026-10-03 used frozen `0.2.2` and genuinely compiled `0.2.3`, with **13 expected real process steps**. Actual maintenance rollback to `0.2.2` preserved 1,066 owned version files and maintenance/uninstaller/shortcut state before Inno re-upgraded. Locked-owned and unknown-file removals were refused as expected; normal uninstall, reinstall and the final uninstall succeeded. Six separate data fixtures retained their hashes. Its evidence records `numericUpgradeUsesSyntheticMetadataFixture=false`, `unsigned=true` and `cleanVm=false`. The earlier `0.2.1` → `0.2.2` result remains separate dated evidence in [Testing](/SteamWrapper/development/testing/).

The later frozen `0.2.3` → genuinely compiled `0.2.4` run on 2026-10-03 also passed **13 expected real process steps**. Actual maintenance rollback `0.2.4 → 0.2.3` preserved 1,204 owned version files and maintenance/uninstaller/shortcut state, followed by Inno re-upgrade. Late owned-file locks and unknown files correctly blocked uninstall; subsequent normal uninstall/reinstall passed. Six data fixtures retained their hashes. Evidence is `target/winui/installer acceptance 中文 ' f9b299a94e654ab78a528bd1ea227c37/evidence.json`, again genuine, unsigned and `cleanVm=false`. This local result does not complete clean-client, retention or real signing gates.

## Installation and daily use

The `0.2.5` implementation includes the following installation and removal choices. See [Testing](/SteamWrapper/development/testing/) for the separately recorded service, native-window and installer results; earlier dated installer runs do not establish these new options.

Choose English or 简体中文 in setup. Installation is per user, with no routine elevation. First installation can use an empty directory on a fixed local drive; the default layout is:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
  SteamWrapper.exe
  installation.json
  versions\<tag>\
  maintenance\SteamWrapper.Deployment.exe
```

The Start menu shortcut is selected by default; the desktop shortcut is off by default. Setup also offers opening Manager when installation finishes. Shortcuts target the stable `SteamWrapper.exe` launcher, which starts Manager only. Steam continues to call `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe`; do not paste a Manager, deployment helper or version-directory path into Steam Launch Options.

Updates and repairs use the registered installation directory. To change location, uninstall Manager while keeping its data, then install into the new empty directory. The installer does not move an existing installation or its data tree.

Installing Manager does not modify Steam options, games or the stable Runner. Manager's existing Runner install/repair action remains separate. Profiles, UI preferences, profile backups, logs and caches stay under `%LOCALAPPDATA%\SteamWrapper\`. Uninstall restoration can also retain a recovery backup beside Steam's account file, as described below. Portable users can keep their existing data and install Manager without copying game files.

Close all Manager windows normally before install, repair, rollback or uninstall. The deployment lease blocks changes while Manager is running and blocks new Manager starts during activation. Busy operations fail with retry guidance; they do not terminate Manager, Runner or games. A locked launcher is not forcibly replaced at reboot.

## Repair and rollback

Re-run the matching verified setup to restore a missing stable Manager launcher at its registered location. Alternatively, with Manager closed, use the installed maintenance helper. These commands show the default directory; substitute your chosen program directory when needed:

```powershell
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --repair --language en
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --rollback --language zh-CN
```

Repair resolves a supported interrupted deployment journal and restores a missing launcher from its verified version. It refuses unknown or altered files rather than overwriting them. It is not a general repair of corrupted runtime files. Rollback selects the retained compatible previous version after verifying its complete manifest; it does not roll back profiles or stable Runner.

If a staging copy is incomplete, repair preserves every uncertain byte in `.recovery-<transaction>` under the program root, with a recovery receipt. This directory is not launched or automatically cleared, and does not prevent use of the restored valid version. Retain it for diagnosis and review it manually before removing it. Uninstall also leaves it intact. Old complete versions currently remain available; automatic pruning and a retained-version disk quota are not implemented. Installation now admits a new payload only when reported free space covers its complete staged files and manifest, an atomic launcher copy, bounded state/journal writes and a 16 MiB reserve. This is an admission check, not a reservation against other disk writers.

Isolated deployment tests stop real compiled fixture processes without unwinding at five installation and two recovery-rename checkpoints. They verify durable journals, released leases, complete-version repair and preservation of unknown partial bytes. Controlled free-space tests verify refusal before a new deployment journal or version is created. These tests do not fill the real system disk or simulate registry/shortcut failure or full-machine power loss. See [Testing](/SteamWrapper/development/testing/) for the exact evidence scope.

An additional focused 14-case uninstall slice passed at six journal/isolation/deactivation/cleanup checkpoints using only the fixture process's own exit; the existing seven installation/recovery cases also passed separately. This does not extend the earlier complete 99-case suite into a claimed new full-suite run.

A transaction-bound acknowledgment is written only after Manager initializes. An unhealthy/slow startup does not trigger forced shutdown or unattended rollback. Manual recovery is the current boundary. File-state journal recovery does not promise an atomic transaction across Windows registry, shortcuts and every power-loss point.

## Uninstall

Use Windows installed-app settings or the installed uninstaller, with Manager closed. Uninstall removes manifest-owned Manager versions, stable Manager launcher, setup registration and shortcuts. Unknown or altered installation files reject the operation before ordinary owned-file deletion; preserve the diagnostic and investigate before retrying.

An interrupted removal uses a separate uninstall journal and an isolated `.removal-<transaction>` tree. Deactivated or partly removed files are never treated as a launchable version. After the reported file occupation ends, repeat uninstall or use the same verified installer (or a newer numeric release) to recover. Unknown bytes remain preserved. These file-level recovery tests do not establish recovery of every Windows registry or shortcut failure.

By default, uninstall keeps all separate player data. Seven additional choices are independent and off by default:

- Remove recognized SteamWrapper Launch Options.
- Delete downloaded cover and update caches.
- Delete SteamWrapper logs.
- Reset Manager preferences.
- Delete game profiles.
- Delete recognized profile backups.
- Delete the verified stable Runner and its matching metadata.

Removing Launch Options requires Steam to be closed normally. Each affected account file is backed up first. Only an exact standard command generated for this data root's stable Runner and the matching AppID is cleared; custom commands and other file contents are preserved. Because manually copied commands did not record earlier arguments, this cannot restore an unknown previous value. Profiles and Runner can be deleted only after Steam is closed and scanning all local accounts finds no remaining references to that Runner. Unrecognized references must be reviewed manually.

Restoration first keeps the file replaced by the atomic operation beside the Steam account file as `localconfig.vdf.steamwrapper-backup-<guid>`, then verifies and copies it to SteamWrapper's data backup directory. This works when Steam and AppData are on different drives. The adjacent backup is removed only after success; a concurrent edit or interruption leaves it for recovery and blocks profile/Runner deletion. Keep Steam closed, preserve both the current file and any backups, and review them before retrying. Do not overwrite the current file or delete the adjacent backup blindly.

Cleanup selects known files only and preserves busy or unrecognized files and unverified Runner bytes. Profile-backup cleanup does not delete Steam restoration backups. Update trust state is always retained. No option deletes games or saves, follows a filesystem link, or recursively clears a folder. A partial-cleanup message means the retained files need your review.

## Signing and updates

The [code-signing policy](/SteamWrapper/project/design/code-signing/) makes Windows Authenticode an optional improvement after the declined Foundation application. No Windows publisher certificate is claimed. Application updates use a separate project signing key; checksums and PE product metadata alone are not signatures. Each changed installable payload uses a new coordinated numeric version and preserves third-party licenses/notices and upstream signatures.

The `0.2.5` release includes manual update checks, optional startup checks, verified downloads and confirmed installation. Its public GitHub preview feed and exact Setup download have passed service-level signature, size and hash verification; the public downloaded installer was not executed in that check. Metadata renewal also passed without rebuilding software or changing version assets. The genuine isolated installation handoff is separate evidence, and clean-client/public download-to-install acceptance remains open. Earlier versions without the update interface require one manual installation. See [Testing](/SteamWrapper/development/testing/#project-update-checks-and-installation) for the scope and [distribution](/SteamWrapper/development/distribution/) for the release contract. Daily game launch remains independent of Manager and network access.
