---
title: Configure a game
description: Understand game directories, executable paths, launch arguments, saving and language preferences in the WinUI Manager.
---

Use a profile to associate one Steam AppID with the program you want Runner to launch. Manager edits this configuration; it does not need to remain open during play.

Start with [getting started](/SteamWrapper/guides/getting-started/) for the complete Steam paste-and-launch sequence.

## Pick the right Steam entry

Select **＋ Add game**, choose a locally installed game, and select **Use this game**. If needed, select a Steam folder or use **Enter AppID manually**.

Use the original Steam entry's positive numeric AppID. A new Windows profile explicitly uses the Windows platform. Existing profiles retain their identifiers; the AppID field is read-only when editing an existing entry.

If several profiles resolve to the same AppID, Manager refuses an ambiguous save. Reopening the existing single matching profile is preferable to creating another copy.

## Understand the two game locations

| Field | Meaning |
| --- | --- |
| **Steam installation** | The official installation discovered from Steam's local manifests; read-only |
| **Game runtime folder** | The directory containing the build Runner should actually use; editable |
| **Program to run** | The existing `.exe` that Runner starts, either a game or a launcher |

For a translated build, a typical arrangement is:

```text
G:\SteamLibrary\steamapps\common\Example Game\   official Steam installation
G:\OtherGames\Example Game\                    complete translated build
```

Set **Game runtime folder** to the second directory and choose its correct executable. Keep both builds complete and independent; do not connect their changing game resources with hard links or directory junctions. See [translated games and saves](/SteamWrapper/guides/translated-games/).

An unknown **Steam installation** does not erase or replace your chosen runtime folder. Discovery can be uncertain when manifests are missing or the same AppID appears in multiple libraries. You can still configure a known runtime folder.

Choosing a program fills the runtime folder automatically only when that field is empty. **Choosing a different executable does not reset an already populated runtime folder or working directory.** Review both when moving a game.

## Executable and working-directory paths

The runtime folder must exist and use a full path. The WinUI preview accepts an existing `.exe` as its target.

A target can be an absolute path or a path relative to the runtime folder. For example:

```text
Game runtime folder: G:\OtherGames\Example Game
Program to run:      launcher.exe
Resolved program:    G:\OtherGames\Example Game\launcher.exe
```

Under **Advanced settings**, an empty **Working directory** uses the runtime folder. An absolute working directory is used directly; a relative one is resolved inside the runtime folder.

```text
Working directory: resources
Resolved directory: G:\OtherGames\Example Game\resources
```

Use a different working directory only when the program requires it. A wrong directory can produce missing-resource errors, an unexpected language, or different save behavior even when the EXE exists.

## Add launch arguments

Expand **Advanced settings** and select **Add argument**. Each row is **one argument**, including an empty string if you deliberately leave a row empty.

For a program that documents `--language zh-CN`, use two rows:

```text
--language
zh-CN
```

For one argument containing a path with spaces, enter the whole path in one row:

```text
G:\Game Data\Example Saves
```

Do not add surrounding quotes just to keep a row's spaces together. Quotes typed into the row are part of the argument value. Use only options supported by the selected program; SteamWrapper does not interpret translation settings or invent game-specific switches.

Runner uses these argument rows. It does not automatically append the original Steam command or its arguments.

## Choose how long Runner waits

New Windows profiles default to **Wait for the program and its children (recommended)**, the `job` mode. Existing profiles with an omitted legacy `wait_mode` retain `root` behavior.

Other choices are for specific launch behavior. See [wait modes](/SteamWrapper/guides/wait-modes/) before changing them. **Process name** is required only for the named-process mode.

A profile explicitly marked for another platform can be viewed in WinUI but cannot be edited there. The Linux/SteamOS process-group choice is not a supported Windows wait mode.

## Save without losing your changes

Select **Save and generate launch options**.

Manager validates the paths and AppID, saves the profile, then prepares stable Runner. Profile saving and Runner readiness are separate results. If only the profile succeeds, follow the displayed Runner message; launch options are shown as ready only when Runner is ready.

Editing a field after saving hides the generated launch-options panel until you save again. Switching language alone does not mark the profile dirty or clear a successfully generated command.

When leaving an edited profile, reloading or closing Manager, use **Keep editing** to return to unsaved changes, or **Discard changes** if that is your intent. Cancelling a native folder/program picker leaves the current selection intact.

The editor preserves unedited TOML values and creates configuration backups when replacing an existing file. It rejects conflicting external changes, unsupported versions and layouts that it cannot safely edit. Do not respond to a conflict by overwriting the newer file blindly.

## Copy the generated Steam command

The command always uses the stable Runner:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Use **Copy launch options**, retain the game's previous Steam value, and paste the generated command into **Steam → Properties → General → Launch Options**. Copying does not modify Steam automatically.

Keep `%command%` in its final position after `--`. Current Runner receives and logs Steam's expanded command but launches the profile's target and arguments instead. It does not also launch the official EXE or automatically fall back to it.

## Choose your language

Use the sidebar's **Language** selector for **English** or **简体中文**. A successful change updates application-owned controls, validation and status messages immediately while retaining unsaved names, paths and arguments.

The preference is saved separately in `%LOCALAPPDATA%\SteamWrapper\ui-settings.json`. Both Managers use `en-US` or `zh-CN`; missing or unknown values default to English. `en` and `zh-Hans` are accepted aliases. The language preference never enters `profiles.toml` or changes the Runner CLI.

If saving the preference fails, the current language remains selected and an error is shown. A malformed settings file is preserved. OS-owned picker text and original diagnostic/log content may remain in their own language.

The implementation boundaries are in the [profile store](https://github.com/YangYuS8/SteamWrapper/blob/v2/apps/manager-winui/SteamWrapper.Application/Profiles/ProfileStore.cs) and [Runner profile model](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/profile.rs).
