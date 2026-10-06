---
title: Install SteamWrapper for Windows
description: Install or use the complete Windows release, keep your game configurations, and update safely.
---

For **Windows 11 24H2 x64**, we recommend **Setup**. It includes the files needed to run Manager; you do not need development tools or a separate runtime installation. Other Windows builds are not yet verified.

**[Download Setup — v0.2.8](https://github.com/YangYuS8/SteamWrapper/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe)** · [CNB mirror](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe) · [Release notes and other downloads](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8)

GitHub and CNB provide the same verified installer for **v0.2.8, the latest stable release**. The release has three downloads: Setup, portable ZIP and `SHA256SUMS`. It has no Windows Authenticode signature, so Windows may show an unknown-publisher warning. Use the official downloads above and keep normal Windows protection enabled.

<a id="get-a-versioned-preview"></a>
<a id="open-the-complete-application"></a>

## Install and open Manager

1. Download Setup and open it from **File Explorer**. Choose English or 简体中文 for the installer.
2. Choose an **empty folder on a fixed local drive**. Most players can keep the default, `%LOCALAPPDATA%\Programs\SteamWrapper`. Network shares and removable drives are not supported installation locations.
3. Choose your shortcuts. The **Start menu shortcut is on by default**; the **desktop shortcut is off by default**.
4. Finish installation. You can choose to open Manager immediately, or open it later using a shortcut.

Run Setup and Manager using the **same Windows account you normally use for Steam**. Routine installation and use do not require **Run as administrator** or **Run as different user**.

Without a saved language choice, Manager follows a supported system UI language and otherwise uses English. You can save an **English / 简体中文** choice in its sidebar. Follow [Getting started](/SteamWrapper/guides/getting-started/) to configure a game once, then launch it from Steam as usual. Manager is only needed when changing the configuration.

<a id="portable-zip-alternative"></a>

## Use the portable ZIP

If you prefer not to install Manager, download **`SteamWrapper-v0.2.8-win-x64.zip`** from the [same release page](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8). Extract the **complete ZIP** into a folder you intend to keep, then open `SteamWrapper.Manager.exe` from File Explorer.

Keep all accompanying files together. Do not run the EXE inside the ZIP or copy out just the EXE. Close Manager before moving its complete folder. Your separate game configurations and stable Runner keep their existing locations, so moving Manager does not require changing Steam Launch Options.

To update a portable copy, extract a newer complete ZIP into a new folder, close the old Manager, then open the new copy. The in-app installer does not overwrite portable folders.

<a id="update-manager-and-prepare-runner"></a>

## Update the application

Open **Updates** in Manager and select **Check for updates**. Automatic checks are **off by default**; you can enable **Check when SteamWrapper opens** if you want. Downloading and installing still need your confirmation.

The default **Download source** is **Automatic**, which tries GitHub first and can use a verified CNB mirror after a network failure. You can also choose GitHub or CNB yourself. Update information must pass the project's signature check, and the downloaded installer must match its recorded size and hash. This project signature is separate from a Windows publisher certificate; players do not need to install a certificate.

For an installed copy, select **Download update**, then **Install update** and confirm. Finish or discard unsaved edits first. Manager closes normally for installation and reopens after success. Updates and repairs keep your registered installation folder and preserve separate data. If a connection or verification fails, keep using the current version and retry later.

Updating Manager does not replace the stable Runner used by Steam. A later explicit **Save and generate launch options** checks and prepares Runner when safe. If Runner is busy, let the game finish normally and retry; SteamWrapper does not force-close games. Follow any displayed Runner warning before using a new launch command; see [Runner troubleshooting](/SteamWrapper/guides/troubleshooting/).

<a id="where-manager-and-runner-keep-data"></a>

## Program files and your data

Manager's program folder and your persistent data are separate:

| Location | What it contains |
| --- | --- |
| Your chosen installation folder, normally `%LOCALAPPDATA%\Programs\SteamWrapper` | Installed Manager and its supporting files. |
| Your complete extracted ZIP folder | Portable Manager and its supporting files. |
| `%LOCALAPPDATA%\SteamWrapper\` | Game configurations, Manager preferences, configuration backups, logs and downloaded caches. |
| `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe` | The stable, independent Runner referenced by Steam Launch Options. |

Keep Steam Launch Options pointing to the stable Runner, never a copy inside Manager's program folder. Configuration backups are **not game-save backups**; game saves have their own locations.

<a id="remove-a-preview"></a>

## Uninstall or change the installation folder

Close Manager, then use **Windows Settings → Apps → Installed apps → SteamWrapper → Uninstall**. The default removes owned Manager program files, shortcuts and registration, while **keeping your game configurations, Runner and other separate data**.

The uninstaller also offers [seven optional restoration and cleanup choices](/SteamWrapper/guides/installer-preview/#uninstall), all off by default. Choose only what you want to remove. No choice deletes game files or saves. Exit Steam normally before restoring its launch commands or removing profiles or Runner; keep them if you are unsure.

To change an installed Manager's location, uninstall with every optional cleanup choice left off, then install into the new empty folder. Updates and repairs do not relocate it.

For a portable copy, close Manager and delete its extracted program folder. Its separate data remains. Do not manually delete the stable Runner while Steam Launch Options still reference it.

<a id="get-an-on-demand-workflow-preview"></a>
<a id="optional-manual-download-check"></a>
<a id="build-the-preview-locally"></a>

## More information

Read the [installer guide](/SteamWrapper/guides/installer-preview/) for repair and cleanup details. [Distribution](/SteamWrapper/development/distribution/) covers release files, download integrity and preview workflows. Building from source is covered in [Windows development](/SteamWrapper/development/windows/); those tools are not needed to install or play.
