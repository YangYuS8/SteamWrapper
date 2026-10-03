---
title: "Windows installer preview"
description: "Build, try, repair and remove the unsigned per-user installer, with explicit preview limits."
---

## Current boundary

The Inno Setup installer and C# deployment component are implemented for **Windows 11 24H2 or newer, x64**, as an **unsigned preview**. They include the complete self-contained WinUI layout, both languages and the independent Runner. Normal branch CI tests and compiles source; it does not produce a setup executable. An explicit manual release-workflow run builds an installer preview. Public version tags currently use the existing portable ZIP release contract. The [execution queue](/SteamWrapper/project/roadmap/#execution-queue-2026-10-03) plans a public unsigned installer after delivery acceptance and an artifact-schema change, before Foundation application; production signing has its own later gate.

This is not a signed or stable release. Isolated process tests on a development machine or hosted Windows Server do not establish clean Windows 11 acceptance. The remaining clean-client, normal-protection download, multi-user, scaling and real Steam delivery gates are recorded in the [delivery plan](/SteamWrapper/project/design/windows-delivery/). Do not disable Windows protection to run the preview.

## Build a preview

With the documented Windows development tools installed, run from the repository root:

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Install-WinUIInstallerToolchain.ps1
pwsh -NoProfile -File scripts/windows/New-WinUIInstaller.ps1 -Tag v0.2.2-preview.1
```

The last command produces `target/winui/installers/v0.2.2-preview.1/SteamWrapper-v0.2.2-preview.1-win-x64-setup.exe` and inspection metadata for the current `0.2.2` source. The tag must match the numeric source version. It labels a local artifact; the command does not create a Git tag or publish a Release. Do not reuse a public version for changed bytes. The dated `0.2.1` artifacts and verification records remain historical evidence.

Changing only the prerelease suffix does not provide an upgrade path: the deployment manifest changes while the numeric version remains the same, and installation rejects different content at the same base. New installable payloads need a new coordinated three-part source/product version; retry an existing build with its exact immutable files. See [release version rules](/SteamWrapper/development/distribution/#prepare-and-trigger-a-release).

Inno Setup 7.1.0 x64 is downloaded only from the official site, with the pinned SHA-256 and publisher signature verified. It is installed under `target/toolchain`; contributors may also supply a matching verified compiler using `-Compiler`. mise aliases are optional conveniences. Developer SDKs and Inno are build tools, not player requirements.

For disposable acceptance:

```powershell
pwsh -NoProfile -File scripts/windows/Test-WinUIInstallerScripts.ps1
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1
```

The latter runs real setup, compatible maintenance rollback and uninstall processes under a fresh repository `target` root, with a distinct test AppId and shortcuts redirected to a disposable fixture directory. Its default synthetic next-version bundle tests the deployment transaction only; it is not a real next-version build or signing evidence. It never uses the real game library. The script reports the isolated directory containing its logs and `evidence.json`; its path includes Chinese text, spaces and an apostrophe to test path handling.

For genuine numeric-version upgrade acceptance, freeze the complete old portable publication before replacing it, reject reparse/private inputs, and record source/copy hashes. Build the new coordinated source/product version normally; changing the old Runner manifest or PE metadata does not create a new-version binary. With a verified frozen `0.2.1` directory and genuinely compiled `0.2.2` publication, replace `REPLACE_WITH_ID` with the recorded baseline directory name:

```powershell
$baseline = 'target/winui/upgrade-baselines/REPLACE_WITH_ID/v0.2.1'
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1 `
  -PublishDirectory $baseline `
  -UpgradePublishDirectory target/winui/publish `
  -Tag v0.2.1-installertest.1 `
  -UpgradeTag v0.2.2-installertest.1
```

When an upgrade publication is supplied, the script checks all seven own PE product/version fields in both layouts before invoking the compiler or installer. The expected successful evidence includes `numericUpgradeUsesSyntheticMetadataFixture=false` and a compatible rollback executed by the actual maintenance process, followed by reactivation through the real upgraded installer. Inspect the recorded tags, versions, owned-file preservation and user-data hashes. This command uses the isolated test root, not the production installation. Local success still does not establish clean Windows, native wizard/Explorer, multi-user or every interruption/registry/shortcut failure gate. No clean VM was available for the local 2026-10-03 preparation.

## Installation and daily use

Choose English or 简体中文 in setup. Installation is per user, with no routine elevation and a fixed program root:

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
  SteamWrapper.exe
  installation.json
  versions\<tag>\
  maintenance\SteamWrapper.Deployment.exe
```

Setup creates a Start menu shortcut; a desktop shortcut is optional. Both target the stable `SteamWrapper.exe` launcher. The launcher starts Manager only. Steam continues to call `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe`; do not paste a Manager, deployment helper or version-directory path into Steam Launch Options.

Installing Manager does not modify Steam options, games or the stable Runner. Manager's existing Runner install/repair action remains separate. Profiles, UI preferences, backups, logs and caches stay under `%LOCALAPPDATA%\SteamWrapper\`. Portable users can keep their existing data and install Manager without copying game files.

Close all Manager windows normally before install, repair, rollback or uninstall. The deployment lease blocks changes while Manager is running and blocks new Manager starts during activation. Busy operations fail with retry guidance; they do not terminate Manager, Runner or games. A locked launcher is not forcibly replaced at reboot.

## Repair and rollback

Re-run the matching verified setup to restore a missing stable Manager launcher. Alternatively, with Manager closed, use the installed maintenance helper:

```powershell
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --repair --language en
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --rollback --language zh-CN
```

Repair resolves a supported interrupted deployment journal and restores a missing launcher from its verified version. It refuses unknown or altered files rather than overwriting them. It is not a general repair of corrupted runtime files. Rollback selects the retained compatible previous version after verifying its complete manifest; it does not roll back profiles or stable Runner.

If a staging copy is incomplete, repair preserves every uncertain byte in `.recovery-<transaction>` under the program root, with a recovery receipt. This directory is not launched or automatically cleared, and does not prevent use of the restored valid version. Retain it for diagnosis and review it manually before removing it. Uninstall also leaves it intact. Old complete versions currently remain available; automatic pruning and a disk quota are not implemented.

A transaction-bound acknowledgment is written only after Manager initializes. An unhealthy/slow startup does not trigger forced shutdown or unattended rollback. Manual recovery is the current boundary. File-state journal recovery does not promise an atomic transaction across Windows registry, shortcuts and every power-loss point.

## Uninstall

Use Windows installed-app settings or the installed uninstaller, with Manager closed. Uninstall removes manifest-owned Manager versions, stable Manager launcher, setup registration and shortcuts. Unknown or altered installation files reject the operation before ordinary owned-file deletion; preserve the diagnostic and investigate before retrying.

An interrupted removal uses a separate uninstall journal and an isolated `.removal-<transaction>` tree. Deactivated or partly removed files are never treated as a launchable version. After the reported file occupation ends, repeat uninstall or use the same verified installer (or a newer numeric release) to recover. Unknown bytes remain preserved. These file-level recovery tests do not establish recovery of every Windows registry or shortcut failure.

Uninstall retains **profiles, settings, stable Runner, backups, logs, downloaded covers and future update trust state**. Existing Steam options may still reference Runner. There is no “delete everything” option, and automatic Steam option restoration is not implemented. Do not manually remove Runner while Steam options still reference it.

## Signing and updates

The [code-signing policy](/SteamWrapper/project/design/code-signing/) prepares SignPath Foundation review and validates timestamp, publisher, explicit certificate pins and final Runner bytes. Foundation approval and production signing are not connected. Checksums and PE product metadata are not publisher signatures.

Authenticated update validation is developed separately against disposable fixtures. No production update feed, key, background checker, automatic download or confirmed installer invocation is enabled. Daily game launch remains independent of Manager and network access.
