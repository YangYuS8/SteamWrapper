---
title: Getting started
description: Configure a Windows game once, then launch it from its normal Steam library entry.
---

SteamWrapper lets Steam launch the game executable or launcher you choose. **Manager is for configuration; the independent Runner handles daily launches.** Once setup is complete, Manager can stay closed.

This guide uses the **WinUI Windows Manager** for Windows 11 24H2 x64. Start with [installation](/SteamWrapper/guides/installation/) to get Setup or the complete portable ZIP. Windows packages do not have an Authenticode publisher certificate; the official release identifies their version and known limits.

**The apply and original-value restoration steps describe the v0.2.9 candidate.** Candidate validation, real Steam acceptance and release checks are still pending; no v0.2.9 public download is claimed here. With public v0.2.8, use its save action and the manual copy alternative below.

## Before configuring a game

Have the game installed in Steam and identify the executable you actually want to run. For a translation or alternate build, first confirm that its complete directory launches correctly through ordinary File Explorer.

Keep the official Steam installation and a complete third-party translation in separate directories. Back up the game's actual saves before moving or testing a build. SteamWrapper's configuration backups are **not game-save backups**. See [translated games and saves](/SteamWrapper/guides/translated-games/) before changing a mixed official/translated installation.

## 1. Open Manager

For an installed copy, use the Start menu or desktop shortcut. For the portable copy, extract the entire ZIP and double-click **`SteamWrapper.Manager.exe` in File Explorer**. Do not copy the EXE out of its directory or run it inside the downloaded ZIP.

With no saved language preference, the interface follows the supported system UI language. Simplified Chinese systems use Chinese; unsupported languages use English. The sidebar's **Language** selector offers **English / 简体中文**. A successful manual selection is saved and takes priority on later launches.

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

<a id="4-save-and-prepare-runner"></a>

## 4. Save and apply to Steam

Select **Save and apply to Steam** in the v0.2.9 candidate. Manager saves the profile and prepares or verifies Runner in its stable user-data directory before showing the proposed Steam change.

1. Review the game name, AppID, Steam account, current Launch Options and new command. A sole readable account is displayed; multiple accounts require an explicit choice.
2. If Steam is running, exit it normally and select **Check again**. Manager rereads the setting, so review any changed value before continuing.
3. Select **Apply to Steam**. Nonempty previous options are replaced and retained for restoration. Canceling keeps your saved configuration and makes no Steam change.

A profile-save success does not establish Runner readiness or a Steam write. Follow the displayed Runner message if preparation failed. If the AppID does not match one unambiguous local installation, or no readable account is available, use manual copying below. For a missing account, open Steam and sign in once, then reload Manager.

<a id="5-copy-the-launch-options-into-steam"></a>

## 5. Check Steam, or copy manually

After **Configuration saved; Launch Options written**, choose **Open Steam** and check the same game's **Properties → General → Launch Options** under the account shown in the confirmation. Open Steam opens the client; it does not start the game. Manager has checked the disk value, so confirm the setting in Steam itself before playing.

If application could not be confirmed or a conflict needs review, preserve the current setting and recovery copies. Check [troubleshooting](/SteamWrapper/guides/troubleshooting/#steam-launch-options-were-not-applied-or-restored) before retrying.

For manual setup, use **Save only**, then the separate **Copy launch options** button. Public v0.2.8 calls its save action **Save and generate launch options**. Continue after Runner is ready:

1. In Steam, use the intended account, right-click the same game and open **Properties → General → Launch Options**.
2. Copy and keep the complete previous value somewhere you can retrieve it. Record an empty value as empty.
3. In Manager, select **Copy launch options**.
4. Paste the generated text into Steam's Launch Options.

The generated command has this shape; use Manager's actual output rather than this example:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

Keep the quotes, `--appid`, the separate `--`, and final `%command%` exactly as generated. Do not replace Runner with the Manager EXE or a file inside a temporary extraction directory.

**Saving alone and copying do not apply settings to Steam.** Manual pasting does not create a previous-value record in Manager. Runner receives and logs Steam's expanded original command, but currently launches the profile's own target and arguments; it does not automatically append the original command to the game.

## 6. Launch and exit normally

Close Manager, then select **Play** on the original Steam library entry.

Confirm that the expected game or translation opens. Exit through the game's normal controls and check that Steam returns to its stopped state. Running state, displayed playtime, Overlay and achievements are separate observations; success in one does not prove the others.

For subsequent play, use Steam normally. Open Manager again only when changing configuration or addressing a Runner issue.

## Undo a game's setup

For an application recorded by the v0.2.9 candidate, choose **Restore Steam launch**, select the same account and review **Restore previous Launch Options**. Exit Steam normally and use **Check again** when prompted. Restoration proceeds only while the current options still match the applied command; later edits to that game's options require review.

For a manually pasted command with no recorded original, **Restore normal Steam launch** clears only the selected account's exact recognized command. To recover earlier arguments, paste back the complete value you kept yourself; Manager cannot reconstruct it. If that value was empty, clear the field. These operations keep your configuration and do not move game files or restore game progress. See [configuration](/SteamWrapper/guides/configuration/#revert-restore-or-remove-a-configuration) for the boundaries.

If you were only testing, restore the previous options afterward and keep any naturally updated saves unless you deliberately choose a separate save-recovery plan. Stop on a cloud-save conflict instead of guessing which progress to overwrite.

Continue with [detailed configuration](/SteamWrapper/guides/configuration/) or [troubleshooting](/SteamWrapper/guides/troubleshooting/).
