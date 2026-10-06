---
title: Install the Windows preview
description: Get the complete WinUI preview, understand its data locations, and update it without breaking Steam launch options.
---

For **Windows 11 24H2 x64**, use the **Setup installer**. It installs the WinUI Manager and its required .NET and Windows App SDK files; you do not need development tools or a separate runtime download.

**[Download Setup — v0.2.6-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/download/v0.2.6-preview.1/SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe)** · [CNB mirror](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.6-preview.1/SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe) · [Release notes and other downloads](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.6-preview.1)

Both sources provide the same verified installer. Manager's download-source options also support CNB; automatic mode tries GitHub first and can use the verified CNB mirror after a network failure.

This is a technical preview without Windows Authenticode signing. Clean-client and broader recovery acceptance remain open. A portable ZIP is available as an alternative. See the [installer guide](/SteamWrapper/guides/installer-preview/) for repair and uninstall details; historical Dioxus packages do not contain the current WinUI Manager.

## Get a versioned preview

1. Open the project's official [v0.2.6-preview.1 release](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.6-preview.1) and read its known limits. Other versions are listed in [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases).
2. Download **`SteamWrapper-<tag>-win-x64-setup.exe`** from that release. Match the version in the filename to the release you selected, then open it in File Explorer.
3. Choose English or 简体中文, an installation directory and shortcuts. The default location is suitable for most players; a different location must be an empty directory on a fixed local drive. The Start menu shortcut is on by default and the desktop shortcut is off.
4. Finish installation and open Manager. Its language follows the supported system language, falling back to English. Continue with [getting started](/SteamWrapper/guides/getting-started/) to configure your game once, then launch it normally from Steam.

Updates and repairs stay at the registered installation directory. To change location later, uninstall Manager while keeping its data, then install at the new location. Setup does not move your games or game saves.

If no WinUI release is available, use a manual workflow preview or the local build below. The release workflow publishes only after its gates and package checks pass; a successful run does not prove compatibility with every Windows installation or game.

## Portable ZIP alternative

If you prefer not to install Manager, download **`SteamWrapper-<tag>-win-x64.zip`** from the same official release and extract the entire archive into a directory you intend to keep. Open `SteamWrapper.Manager.exe` from that directory in File Explorer. Keep all supporting files together; there is no single-file portable WinUI EXE. Portable updates use a new complete ZIP rather than the installer's in-app update path.

## Get an on-demand workflow preview

Ordinary pull requests and merges into `main` run CI without uploading an application package. A maintainer can open the [WinUI version release workflow](https://github.com/YangYuS8/SteamWrapper/actions/workflows/winui-release.yml), select the intended branch or ref under **Run workflow**, and request a build. A manual run performs the full build and gates but never publishes a public release.

From a successful manual run, download **`SteamWrapper-WinUI-preview-windows-x64`** and extract every file. Do not use the separate test-evidence artifact as the application. Workflow artifact downloads may require GitHub sign-in and expire with the retention period. Maintainers should provide the selected source revision with the preview.

The separate **`SteamWrapper-WinUI-installer-preview-windows-x64`** artifact contains a setup preview without Windows Authenticode signing and its inspection metadata. Read the [installer guide](/SteamWrapper/guides/installer-preview/) before using it; clean-client acceptance remains open.

## Open the complete application

For an installed copy, use its Start menu or desktop shortcut. For the portable ZIP, open the extracted directory in ordinary File Explorer and double-click **`SteamWrapper.Manager.exe`**.

Retain its supporting DLLs, native `.pri` resources, `Assets`, `Runner` and `zh-CN` resources. Do not run the EXE from inside the ZIP, move it away from its supporting files, or use a contract-test driver as Manager.

With no saved preference, the interface follows the supported system UI language and falls back to English. The **English / 简体中文** selector saves a manual override. Continue with [getting started](/SteamWrapper/guides/getting-started/) to add a game.

If Windows reports a download or security problem, stop and confirm the package's source and completeness. SteamWrapper does not require globally disabling Windows protection. A checksum confirms consistency with a particular artifact; it is not a publisher signature or a safety verdict for a third-party game.

## Optional manual download check

For a manual integrity check, download `SHA256SUMS` from the same release and compare the downloaded Setup or ZIP with its matching line. PowerShell's `Get-FileHash -Algorithm SHA256 -LiteralPath '.\SteamWrapper-<tag>-win-x64-setup.exe'` displays the digest; replace `<tag>` with your downloaded version. Releases also include `release.json` and English/Simplified Chinese notes. A matching checksum checks the file against that release's recorded bytes; it does not provide a Windows publisher certificate.

## Build the preview locally

This is the source-development option, not runtime preparation required from everyone using a downloaded preview.

Use a Windows checkout of branch `main`. Install PowerShell 7, the .NET SDK selected by `global.json`, and Rust with an MSVC host using your preferred method. Make `pwsh`, `dotnet` and `cargo` available on PATH; mise is optional. From the repository root:

```powershell
pwsh -NoProfile -File scripts/windows/Install-BuildTools.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

The setup script uses Microsoft's installer for the declared MSVC/Windows SDK components and may request UAC permission. If it reports that a restart is required, complete that restart before relying on the environment.

The published directory is:

```text
target\winui\publish\
```

Open that full directory in File Explorer and run Manager from there. The source project does not require installing the separate alpha WinUI template.

For a disposable configuration preview that does not use your real Steam/user data, use:

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

The sandbox contains example manifests and isolated user directories. It does not contain your real library or a playable game; profiles created there are not real Steam setup.

See [Windows development](/SteamWrapper/development/windows/) for authoritative manifests, optional mise aliases and the complete tool list. The [Windows build script](https://github.com/YangYuS8/SteamWrapper/blob/main/scripts/windows/Invoke-WinUI.ps1) implements the direct commands. A WinUI-only publish does not require Node, pnpm, Dioxus CLI or just.

## Where Manager and Runner keep data

The extracted Manager directory holds application files. Persistent Windows data lives separately:

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

| Location | Purpose |
| --- | --- |
| `profiles.toml` | Game profiles used by Runner |
| `ui-settings.json` | Manager language and optional Steam-cover download preferences |
| `bin\SteamWrapperRunner.exe` | Stable, independent Runner referenced by Steam |
| `logs` | Runner diagnostics and Manager startup diagnostics when available |
| `backups` | Configuration backups, not automatic game-save protection |
| `cache\covers` | Bounded downloaded-cover cache; clearing it retains Steam/custom art |

Game saves may instead be inside the game directory, Windows user folders or Steam storage. Identify and protect them separately.

## Update Manager and prepare Runner

Close Manager and let any active game/Runner session exit normally before replacing application files. Extract a newer complete preview into its own directory, then open that Manager through File Explorer.

Saving a profile checks the bundled Runner and prepares the stable copy. The WinUI service preserves a newer compatible Runner and refuses an unknown version or a same-version file with different contents when it cannot establish a safe update. A busy-file or verification failure is reported; it should not be worked around by deleting user configuration.

If Manager says the profile saved but Runner is not ready, see [Runner troubleshooting](/SteamWrapper/guides/troubleshooting/).

Steam Launch Options must continue to reference the stable `bin\SteamWrapperRunner.exe`, not the extracted package's `Runner` directory. Moving a complete Manager directory should not require rewriting each game's launch options just to point to the new Manager location.

## Remove a preview

For the portable ZIP, removing its extracted application directory does not remove the separate stable Runner and configuration. If you used Setup, use Windows installed-app settings or its uninstaller. Default uninstall keeps user data; its seven optional restoration/cleanup choices are described in the [installer guide](/SteamWrapper/guides/installer-preview/), with scoped local results and remaining gates recorded separately.

Before removing stable Runner or its data, restore every Steam Launch Options value that still references it and retain any configuration backups you need. Leaving Steam pointing to a deleted Runner prevents those entries from launching correctly.

For the full setup sequence, continue with [getting started](/SteamWrapper/guides/getting-started/).
