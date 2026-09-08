---
title: Getting started
description: Configure a Windows game once, then launch it from its normal Steam library entry.
---

SteamWrapper lets Steam launch the game executable or launcher you choose. **Manager is for configuration; the independent Runner handles daily launches.** Once setup is complete, Manager can stay closed.

This guide uses the **WinUI Windows preview**. It currently targets Windows 11 24H2 x64. The retained Dioxus application and release chain are separate; a new WinUI installer has not been delivered. Start with [installation](/SteamWrapper/guides/installation/) if you do not yet have the complete preview directory.

## Before configuring a game

Have the game installed in Steam and identify the executable you actually want to run. For a translation or alternate build, first confirm that its complete directory launches correctly through ordinary File Explorer.

Keep the official Steam installation and a complete third-party translation in separate directories. Back up the game's actual saves before moving or testing a build. SteamWrapper's configuration backups are **not game-save backups**. See [translated games and saves](/SteamWrapper/guides/translated-games/) before changing a mixed official/translated installation.

## 1. Open Manager

Extract the entire preview and double-click **`SteamWrapper.Manager.exe` in File Explorer**. Do not copy the EXE out of its directory or run it inside the downloaded ZIP.

With no saved language preference, the interface starts in English. Choose **简体中文** from the sidebar's **Language** selector if preferred. A successful language change is saved for the next launch.

## 2. Add your Steam game

1. Select **＋ Add game**.
2. Choose the game from the locally discovered Steam library. Search by name or AppID.
3. Select **Use this game**.

If discovery cannot find Steam, use **Choose Steam folder…**. You can also choose **Enter AppID manually** and enter the original game's positive numeric Steam AppID. Use the AppID of the Steam library entry you intend to launch.

If that game already has one matching profile, Manager opens it for editing. Multiple profiles matching the same AppID must be resolved before saving.

## 3. Choose the actual program

Check these fields:

| Field | What to choose |
| --- | --- |
| Game name | A name you recognize |
| Steam installation | Read-only information about the official Steam-managed location |
| Game runtime folder | The complete directory containing the build you want to play |
| Program to run | That build's actual game or launcher `.exe` |

For example, the official installation may stay inside a Steam library while **Game runtime folder** points to `G:\OtherGames\Example Game` and **Program to run** points to its translated launcher.

Leave the advanced working directory empty unless the game or launcher needs a different one. New Windows profiles use **Wait for the program and its children (recommended)**. See [configuration](/SteamWrapper/guides/configuration/) and [wait modes](/SteamWrapper/guides/wait-modes/) for exceptions.

## 4. Save and prepare Runner

Select **Save and generate launch options**. Manager saves the profile, checks the bundled Runner, and installs or updates it in SteamWrapper's stable user-data directory when possible.

Continue when the success message says Runner is ready and the launch-options text is visible. A message that the profile was saved but Runner is not ready means configuration succeeded while runtime preparation still needs attention. Follow [troubleshooting](/SteamWrapper/guides/troubleshooting/) before changing Steam.

## 5. Copy the launch options into Steam

1. In Steam, right-click the same game and open **Properties → General → Launch Options**.
2. Copy and keep the complete previous value somewhere you can retrieve it. Record an empty value as empty.
3. In Manager, select **Copy launch options**.
4. Paste the generated text into Steam's Launch Options.

The generated command has this shape; use Manager's actual output rather than this example:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

Keep the quotes, `--appid`, the separate `--`, and final `%command%` exactly as generated. Do not replace Runner with the Manager EXE or a file inside a temporary extraction directory.

**Copying does not apply settings to Steam.** The preview uses this manual paste step. Runner receives and logs Steam's expanded original command, but currently launches the profile's own target and arguments; it does not automatically append the original command to the game.

## 6. Launch and exit normally

Close Manager, then select **Play** on the original Steam library entry.

Confirm that the expected game or translation opens. Exit through the game's normal controls and check that Steam returns to its stopped state. Running state, displayed playtime, Overlay and achievements are separate observations; success in one does not prove the others.

For subsequent play, use Steam normally. Open Manager again only when changing configuration or addressing a Runner issue.

## Undo a game's setup

Restore the launch-options value you recorded before setup. If it was empty, clear the field. This removes that Steam entry's reference to Runner; it does not move game files or restore game progress.

If you were only testing, restore the previous options afterward and keep any naturally updated saves unless you deliberately choose a separate save-recovery plan. Stop on a cloud-save conflict instead of guessing which progress to overwrite.

Continue with [detailed configuration](/SteamWrapper/guides/configuration/) or [troubleshooting](/SteamWrapper/guides/troubleshooting/).
