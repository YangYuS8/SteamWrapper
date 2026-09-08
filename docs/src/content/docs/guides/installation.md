---
title: Install the Windows preview
description: Get the complete WinUI preview, understand its data locations, and update it without breaking Steam launch options.
---

The WinUI Manager is currently a **self-contained directory preview for Windows 11 24H2 x64**. It bundles .NET and Windows App SDK files alongside the application. Keep the complete directory together.

There is no new WinUI setup wizard, single-file executable, or completed clean-system/update/uninstall guarantee. Dioxus and its existing release workflows remain the retained delivery chain. The WinUI executable is `SteamWrapper.Manager.exe`; the Dioxus executable is `SteamWrapperManager.exe`.

## Get a CI preview

1. Open the repository's [WinUI Windows preview workflow](https://github.com/YangYuS8/SteamWrapper/actions/workflows/winui-windows.yml).
2. Choose a successful run for the intended `v2` revision.
3. If its artifact is available, download **`SteamWrapper-WinUI-preview-windows-x64`**.
4. Extract the entire archive into a directory you intend to keep.

The workflow uploads the published application directory after its tests and publication checks. Artifact availability depends on the run and retention period; if no suitable artifact is available, use the local build below. A green hosted CI run does not by itself prove compatibility with every Windows installation or game.

Download the application artifact, not the separate `WinUI-Windows-contract-evidence` test-results artifact.

## Open the complete application

In ordinary Windows File Explorer, open the extracted directory and double-click **`SteamWrapper.Manager.exe`**.

Retain its supporting DLLs, native `.pri` resources, `Assets`, `Runner` and `zh-CN` resources. Do not run the EXE from inside the ZIP, move it away from its supporting files, or use a contract-test driver as Manager.

The interface defaults to English and provides an **English / 简体中文** language selector. Continue with [getting started](/SteamWrapper/guides/getting-started/) to add a game.

If Windows reports a download or security problem, stop and confirm the package's source and completeness. SteamWrapper does not require globally disabling Windows protection. A checksum confirms consistency with a particular artifact; it is not a publisher signature or a safety verdict for a third-party game.

## Build the preview locally

This is the source-development option, not runtime preparation required from everyone using a downloaded preview.

Use a Windows checkout of branch `v2` with [mise](https://mise.jdx.dev/) installed. From PowerShell at the repository root:

```powershell
mise trust
mise install
mise run windows:setup
mise run windows:doctor
mise run winui:publish
```

Review the repository configuration before trusting it. The setup task uses Microsoft's installer for the declared MSVC/Windows SDK components and may request UAC permission. If it reports that a restart is required, complete that restart before relying on the environment.

The published directory is:

```text
target\winui\publish\
```

Open that full directory in File Explorer and run Manager from there. The source project does not require installing the separate alpha WinUI template.

For a disposable configuration preview that does not use your real Steam/user data, use:

```powershell
mise run winui:sandbox
```

The sandbox contains example manifests and isolated user directories. It does not contain your real library or a playable game; profiles created there are not real Steam setup.

The exact commands and tool pins are maintained in [mise.toml](https://github.com/YangYuS8/SteamWrapper/blob/v2/mise.toml) and the [Windows build script](https://github.com/YangYuS8/SteamWrapper/blob/v2/scripts/windows/Invoke-WinUI.ps1).

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
| `ui-settings.json` | Manager's display-language preference |
| `bin\SteamWrapperRunner.exe` | Stable, independent Runner referenced by Steam |
| `logs` | Runner diagnostics and Manager startup diagnostics when available |
| `backups` | Configuration backups, not automatic game-save protection |
| `cache` | SteamWrapper's cache location |

Game saves may instead be inside the game directory, Windows user folders or Steam storage. Identify and protect them separately.

## Update Manager and prepare Runner

Close Manager and let any active game/Runner session exit normally before replacing application files. Extract a newer complete preview into its own directory, then open that Manager through File Explorer.

Saving a profile checks the bundled Runner and prepares the stable copy. The WinUI service preserves a newer compatible Runner and refuses an unknown version or a same-version file with different contents when it cannot establish a safe update. A busy-file or verification failure is reported; it should not be worked around by deleting user configuration.

If Manager says the profile saved but Runner is not ready, see [Runner troubleshooting](/SteamWrapper/guides/troubleshooting/). The retained Dioxus app has its own Runner installation/repair actions in Settings; those are not an additional WinUI screen.

Steam Launch Options must continue to reference the stable `bin\SteamWrapperRunner.exe`, not the extracted package's `Runner` directory. Moving a complete Manager directory should not require rewriting each game's launch options just to point to the new Manager location.

## Remove a preview

The WinUI directory preview has no tested new uninstaller. Removing its application directory does not remove the separate stable Runner and configuration.

Before removing stable Runner or its data, restore every Steam Launch Options value that still references it and retain any configuration backups you need. Leaving Steam pointing to a deleted Runner prevents those entries from launching correctly.

For the full setup sequence, continue with [getting started](/SteamWrapper/guides/getting-started/).
