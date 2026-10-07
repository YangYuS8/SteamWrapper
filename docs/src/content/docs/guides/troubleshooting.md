---
title: Troubleshooting
description: Diagnose configuration, Runner, Steam status, translation and language problems without overwriting game progress.
---

Start with the message shown by Manager and the most recent Runner log. Configuration saving, Runner readiness, writing a Steam setting, game launch and Steam status are separate results; identify which one failed before changing another part of the setup.

For the expected setup sequence, see [getting started](/SteamWrapper/guides/getting-started/).

## Manager does not open

On Windows 11 24H2 x64, use the same Windows account as Steam with ordinary permissions. For an **installed copy**, open its Start menu or desktop shortcut, or `SteamWrapper.exe` in your chosen installation folder. For a **portable ZIP**, open `SteamWrapper.Manager.exe` from the complete extracted folder in ordinary File Explorer.

For a portable ZIP, do not run it from inside the archive or move the EXE away from its DLLs, native resources, `Assets`, `Runner` and language resources. An old `SteamWrapperManager.exe` belongs to the retired implementation; a test-evidence artifact is not the WinUI application.

If present, inspect:

```text
%LOCALAPPDATA%\SteamWrapper\logs\manager-startup.log
```

Setup and the complete ZIP include the required runtime files. For an installed copy, follow the [repair guidance](/SteamWrapper/guides/installer-preview/#repair-and-rollback). For a portable copy, extract a complete matching ZIP into a new folder. Do not combine unrelated package versions. See [installation](/SteamWrapper/guides/installation/).

## Steam games or installation locations are missing

In **＋ Add game**, choose the actual Steam folder or enter the original game's AppID manually. Discovery uses local installation manifests; it does not query your account online or repair Steam files.

A **Steam installation** shown as unknown can mean discovery failed or the same AppID has multiple installation directories. It does not invalidate an independently chosen **Game runtime folder**, and that folder should not be replaced with a guessed official path.

If a profile already exists, open that profile. A conflict involving multiple profiles for one AppID needs resolution before an unambiguous command can be generated.

<a id="missing-covers"></a>

## A game shows a placeholder instead of its cover

This does not mean the game or its configuration is damaged. Manager first reads custom Steam art and the local library cache, including newer hashed directories. Empty, locked, unreadable or invalid images are skipped. Open the game's library view in Steam if you want Steam itself to populate its normal artwork cache, then reopen **Add Steam game**.

**Download missing covers from Steam** is off by default. Turn it on in that dialog only if you want official image requests. A valid previously downloaded cover can still appear with the option off; **Clear downloaded covers** removes SteamWrapper's copies without changing custom art or Steam files. See [cover settings](/SteamWrapper/guides/configuration/#cover-settings).

Some Steam images have no working AppID-only portrait URL. Offline connections, timeouts, 404/rate-limited responses or malformed images also retain the placeholder; repeated failed requests are briefly suppressed. Selecting, saving and launching remain available. Do not run Steam integrity verification or replace game files just to repair a cover.

## Manager will not save the profile

Check the fields named in the error:

- AppID must be a valid positive numeric Steam AppID.
- Game name, runtime folder and target are required.
- Runtime folder must be an existing full path.
- The WinUI target must be an existing `.exe`.
- An explicit working directory must exist after relative-path resolution.
- Named-process waiting requires a process name.

If Manager reports an external file change, preserve your unsaved values before using **Reload profiles**. Reloading or discarding intentionally abandons the current edits; do not overwrite an external version merely to silence the conflict.

Unsupported profile versions, field values or inline/dotted TOML layouts remain unchanged when the editor cannot safely save them. A profile explicitly marked for another platform is read-only in WinUI. These are not reasons to delete the whole configuration file.

## The profile saved, but Runner is not ready

Profile saving can succeed before Runner installation or verification fails. Follow the specific Runner message; do not assume the game's launch options are ready merely because the profile was saved.

| Message or symptom | Next step |
| --- | --- |
| Bundled files or manifest cannot be verified | Follow the installed-copy repair guidance, or extract a complete matching portable ZIP |
| Runner is in use | Exit the game and its launcher normally, then retry saving |
| Installed version is unknown or same-version contents differ | Keep the existing file and use a matching package; do not force a replacement by deleting metadata |
| A newer compatible Runner is retained | This is expected downgrade protection |
| Shared location cannot be confirmed | Reopen Manager through its installed shortcut or ordinary File Explorer as described below |

WinUI prepares and checks the stable Runner when saving a profile.

<a id="steam-launch-options-were-not-applied-or-restored"></a>

## Steam settings were not applied or restored

The automatic apply and recorded restoration flow is implemented in the **v0.2.9 candidate**; candidate validation, real Steam acceptance and release checks are pending. Public v0.2.8 uses manual copying and cannot recover arguments overwritten by manual pasting.

| Message or situation | What to do |
| --- | --- |
| Configuration saved; Steam settings were not applied | The profile is available. Check the account and Runner message, then review a fresh confirmation or use **Save only → Copy launch options**. |
| Steam is running | Exit Steam normally, then choose **Check again**. Review any changed current value before continuing; Manager will not close Steam or games. |
| No readable account | Open Steam and sign in once, then reload Manager. You can also copy the command manually. |
| Several local accounts | Choose the intended account explicitly. Check the setting in Steam under that same account. |
| Local installation cannot be identified unambiguously | Check the AppID and Steam folder. Keep the manual copy option if the installation remains unknown or ambiguous. |
| Configuration or Runner changed after saving | Save again, prepare Runner and review a new confirmation. |
| Application or restoration could not be confirmed | A Steam change may have occurred. Keep recovery copies and inspect the current setting before retrying or restoring. |
| Current setting or recovery information conflicts | Automatic writes stop to preserve the existing information. Review the current value; do not overwrite it or delete recovery copies to dismiss the message. |
| Recognized command with no previous-value record | **Restore normal Steam launch** can clear the exact command for one selected account. Restore older arguments yourself from the value you kept before manual pasting. |

**Launch Options written** verifies the selected account's disk value. Use **Open Steam** to open the client and check the same game's Properties; it does not launch the game. Successful configuration, copying or a disk write does not establish Steam's in-memory value, playtime or achievement behavior. Reopening Manager or selecting a configuration rereads the current disk setting rather than relying on an old applied label.

Recorded **Restore previous Launch Options** restores only while this game's current value exactly matches the recorded applied command. Later edits to other games are preserved. If this game's value changed, keep it and resolve the conflict before restoring. Configuration backups and Steam recovery copies are not backups of game saves.

## Manager asks you to reopen it from File Explorer

Some development or packaged host environments can redirect literal AppData paths into a private file view. A file existing there does not prove that ordinary Steam can see it.

Close Manager. For an **installed copy**, open its installed shortcut from the normal Windows desktop, or open the chosen installation folder in **ordinary File Explorer** and double-click `SteamWrapper.exe`. For a **portable ZIP**, open its complete extracted folder in ordinary File Explorer and double-click `SteamWrapper.Manager.exe`. Use the same Windows account as Steam, save the profile again, and keep the stable shared Runner path in the newly generated command.

Do not solve this warning by putting a host's private cache path into Steam Launch Options. The application checks final file-handle locations before reporting Runner ready.

## Steam does not start the selected game

First compare Steam's saved Launch Options with Manager's complete generated text:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Check the same AppID, quoted stable Runner path, `--` separator and final `%command%`. Do not point to Manager or the package's bundled Runner.

Then check the profile's runtime folder, target and working directory. A moved game can leave an old directory behind in the profile even after a new EXE was selected. Relative paths are resolved against the runtime folder.

Look for the current session in:

```text
%LOCALAPPDATA%\SteamWrapper\logs\runner-<appid>.log
```

Runner is headless and may not display an error window. Its log records configuration loading, the profile being launched, the expanded original Steam command when supplied, and errors or the reported exit status. Logs append across sessions; inspect the latest entries.

Current Runner launches the profile's target/arguments. It receives the original Steam command but does not execute it alongside the target or automatically forward its arguments. Put required program arguments in the profile itself.

## The wrong language opens or game resources are missing

Confirm that **Program to run** is the translation's intended entry point. A directory can contain both an original executable and a translated launcher. Check the complete resource set and the working directory, not just the filename.

For a direct comparison, navigate **inside the game directory** in ordinary Explorer and double-click the exact same EXE. Starting an absolute path while Explorer remains in a parent directory is not an equivalent working-context check.

If the complete build also fails directly, changing SteamWrapper's wait mode will not repair missing game resources. Preserve the current files and saves before obtaining a matching complete build from its legitimate source.

Keep official and translated copies independent. Steam updates or integrity verification can replace modified files inside its official installation. Do not verify or repair an unprotected mixed directory as the first troubleshooting step. See [translated games and save protection](/SteamWrapper/guides/translated-games/).

## Steam stops too soon or keeps showing Running

If Steam stops showing Running while a launcher-created game is still open, review the wait mode. An old profile may still use `root`, which waits only for the direct launcher. New Windows profiles use `job`.

If Steam remains running after the game window closes, a launcher or helper may still be alive. Identify it and use its normal exit controls where possible. Named-process mode can also include unrelated newly started processes with the same name.

See [wait modes](/SteamWrapper/guides/wait-modes/) before switching settings. A visible window, process ancestry or a launcher's exit code does not by itself prove Job membership or the actual game's exit status.

## Saves, cloud sync or achievements do not behave as expected

Stop if Steam reports a cloud conflict. Determine which progress belongs to the build you want before choosing a copy to keep.

SteamWrapper does not automatically back up game saves, migrate them between builds, change Steam Cloud rules or provide missing achievement logic. A runtime-folder change may expose a different local save location.

A successful launch, increased playtime or working Overlay does not prove achievement compatibility. Normal achievement conditions and the game's Steam integration must both work. Do not interpret a short title-screen test without an unlock condition as an achievement failure. See [translated games](/SteamWrapper/guides/translated-games/).

## Language changes fail or do not persist

Use the sidebar selector. A successful change updates application-owned UI and is stored separately in:

```text
%LOCALAPPDATA%\SteamWrapper\ui-settings.json
```

Without a saved `language` key, Manager follows a supported system UI language and otherwise uses English. A saved manual choice takes priority. Unknown explicit values or unreadable settings fall back to English. Manager uses `en-US` and `zh-CN`; changing the preference does not change profiles, user-entered text or log contents.

If the file is malformed, contains duplicate keys, exceeds the supported size/depth, or cannot be safely written, Manager reports the problem and preserves it. A failed preference write keeps the previous UI language. Keep a copy before manually repairing a settings file; do not delete `profiles.toml` to reset a language preference.

System-owned picker text and raw external diagnostics may follow the Windows/system language. Saved game names and argument values are intentionally not translated.

## Share a useful problem report

Include the Manager variant and revision, Windows version, AppID, selected target, runtime/working directories, wait mode, whether direct launch works, and the relevant latest log entries. Describe whether the failure occurred before the title screen, during play or after normal exit.

Review any paths and logs before sharing them: they can contain user names and original launch arguments. Do not attach credentials, your full Steam account configuration, game files or saves by default.

If you need to undo the test, use the recorded v0.2.9 candidate restoration flow or restore the complete Steam Launch Options value you kept before manual setup. Review conflicts before either action. Keep naturally updated saves unless you have a separate, deliberate recovery plan.
