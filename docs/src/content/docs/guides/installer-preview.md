---
title: "Windows installer"
description: "Choose an installation folder, update or repair Manager, and remove only the data you select."
---

## Current boundary

SteamWrapper **v0.2.7** is the first stable Windows release, verified for **Windows 11 24H2 x64**. Other Windows builds are not yet verified. It installs for the current Windows user and includes the files needed to run Manager; you do not need a developer SDK or a separate .NET installation. Use the same Windows account you normally use for Steam.

See the [installation guide](/SteamWrapper/guides/installation/) for published downloads. This release does not have Windows Authenticode signing. Project signatures used by the update feature are explained [below](#signing-and-updates); they do not provide a Windows publisher certificate.

## Installation and daily use

1. Download the Setup executable linked in the installation guide, then open it from File Explorer.
2. Choose English or 简体中文.
3. Choose an **empty folder on a fixed local drive**. The default is `%LOCALAPPDATA%\Programs\SteamWrapper`. A network share, removable drive or an existing folder containing other files is not supported.
4. Choose your shortcuts. The **Start menu shortcut is selected by default**; the **desktop shortcut is off by default**.
5. Finish installation. You can choose to open Manager immediately.

Setup normally does not require administrator elevation. Close all Manager windows normally before installing, updating, repairing or uninstalling. If files are in use, close the reported program and retry; the installer does not force-close Manager, Runner or a game.

Open Manager to configure a game, then close it and launch the game from Steam as usual. Steam's launch command uses the independent Runner at `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe`. Manager's installation folder and shortcuts are only for opening its configuration interface.

The following data stays separate from the Manager program folder, under `%LOCALAPPDATA%\SteamWrapper\`:

- Saved game configurations and Manager settings.
- The stable Runner used by Steam.
- Configuration backups, diagnostic logs and downloaded caches.

Installing Manager does not change Steam Launch Options, game files or the stable Runner. Saving a profile in Manager prepares or updates Runner separately when safe. If Manager reports that Runner needs attention, follow the message before using the generated Steam launch command.

Updates and repairs keep the registered installation location. To move an installed Manager to another drive or folder, **uninstall Manager with all optional cleanup choices left off**, then install into the new empty folder. Your separate data and stable Runner remain available; there is no need to copy your games.

## Repair and rollback

If Manager's launcher is missing or installation was interrupted, close Manager and run the matching verified Setup again. Repair uses the registered folder and preserves your separate game configurations and Runner.

If repair reports unknown or changed files, keep those files and the diagnostic message for investigation. Repair does not overwrite uncertain files or provide a general repair of arbitrary damaged application files. Recovery folders left by an interrupted operation are retained for review rather than deleted automatically.

Returning to a retained, compatible previous Manager is a maintenance operation. It does not roll back profiles or the stable Runner, and it is not an automatic response to a slow startup. Technical recovery and rollback details are in [Distribution](/SteamWrapper/development/distribution/#windows).

## Uninstall

Close Manager, then use **Windows Settings → Apps → Installed apps → SteamWrapper → Uninstall**, or the installed uninstaller. The default removes Manager's owned program files, shortcuts and installation registration. **Your game configurations, Runner and other separate data are kept.**

The uninstaller offers seven independent choices, all **off by default**:

| Choice | What it removes |
| --- | --- |
| Restore normal game launches from Steam | Exact recognized SteamWrapper commands in Steam Launch Options, after backing up the affected account files. |
| Delete saved game configurations | SteamWrapper's `profiles.toml`; these are launch configurations, not game saves. |
| Delete game configuration backups | Recognized SteamWrapper profile backups; Steam restoration backups are kept. |
| Remove Runner | The verified stable Runner and its matching metadata. |
| Reset Manager settings | Manager preferences, including the saved language choice. |
| Delete downloaded covers and update installers | Recognized files in SteamWrapper's downloaded-cover and update caches; custom Steam art and Steam's own cache are kept. |
| Delete diagnostic logs | Recognized Manager, Runner and update-installation logs. |

**No choice deletes game files or saves.** Choose only the categories you want to remove. For a temporary removal or a change of installation location, leave every choice off.

Before removing Steam launch commands, game configurations or Runner, **exit Steam normally**. The uninstaller clears only the exact generated command for this data folder's stable Runner and matching AppID. It preserves customized commands and every other part of the account file. Earlier manually overwritten arguments were not recorded, so it cannot reconstruct an unknown historical value.

Deleting profiles or Runner also requires a complete scan of the local Steam accounts with no remaining Runner references or unresolved restoration backups. If a customized launch command still uses Runner, review it in Steam before retrying. Keeping profiles and Runner is safe when you are unsure.

If restoration is interrupted, a backup may remain beside Steam's account file as `localconfig.vdf.steamwrapper-backup-<guid>`. Keep Steam closed and preserve both the current file and the backup for review. Do not overwrite the current file or delete the backup blindly. Steam restoration backups and update verification history are always kept, even if you select every cleanup choice.

Busy, unknown or unverified files are preserved. The uninstaller does not follow filesystem links or recursively empty a data folder. A message saying that some files were kept means those files need your review. If Manager itself could not be removed safely, resolve the reported occupation or file problem and retry uninstall; do not manually clear the installation folder.

## Signing and updates

Windows Authenticode signing is optional and is not present in the current release. Windows may therefore show an unknown-publisher warning. Download only from the sources linked in the [installation guide](/SteamWrapper/guides/installation/), and keep normal Windows protection enabled.

Manager's update feature uses a separate **project signature** to verify update information, then checks the exact installer size and hash before offering installation. It does not require players to install a certificate or create a signing key.

Use **Check for updates** in Manager, download an offered version, then confirm installation. Automatic checks are off by default. Installed copies update at their registered location; your profiles and stable Runner remain separate. A version without the update interface needs one manual Setup installation first. The published stable and preview update channels both offer v0.2.8.

For a **portable ZIP**, download a newer complete ZIP and extract it into a new folder. Close the old Manager, then open the new copy from File Explorer. The update feature does not install over an arbitrary portable folder. Your existing profiles and stable Runner stay in the same Windows data folder, so moving Manager does not require changing Steam Launch Options. Removing the old portable application folder does not remove that separate data.

## Build a preview

Contributors can find build and release instructions in [Distribution](/SteamWrapper/development/distribution/) and the verification commands and recorded limits in [Testing](/SteamWrapper/development/testing/). Those development tools are not needed to install or use SteamWrapper.
