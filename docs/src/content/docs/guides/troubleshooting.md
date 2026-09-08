---
title: Troubleshooting
description: Diagnose configuration, Runner, Steam status, translation and language problems without overwriting game progress.
---

Start with the message shown by Manager and the most recent Runner log. Configuration saving, Runner readiness, game launch and Steam status are different stages; identify which one failed before changing another part of the setup.

For the expected setup sequence, see [getting started](/SteamWrapper/guides/getting-started/).

## Manager does not open

Confirm that you extracted the **complete WinUI preview** and are running `SteamWrapper.Manager.exe` from ordinary File Explorer on Windows 11 24H2 x64.

Do not run it from inside a ZIP or move the EXE away from its DLLs, native resources, `Assets`, `Runner` and language resources. A Dioxus `SteamWrapperManager.exe` or a test-evidence artifact is a different application/package.

If present, inspect:

```text
%LOCALAPPDATA%\SteamWrapper\logs\manager-startup.log
```

The self-contained directory bundles runtime files, but clean-system acceptance and a new WinUI installer are not complete. Re-extract a complete artifact rather than assembling a working directory from unrelated package versions. See [installation](/SteamWrapper/guides/installation/).

## Steam games or installation locations are missing

In **＋ Add game**, choose the actual Steam folder or enter the original game's AppID manually. Discovery uses local installation manifests; it does not query your account online or repair Steam files.

A **Steam installation** shown as unknown can mean discovery failed or the same AppID has multiple installation directories. It does not invalidate an independently chosen **Game runtime folder**, and that folder should not be replaced with a guessed official path.

If a profile already exists, open that profile. A conflict involving multiple profiles for one AppID needs resolution before an unambiguous command can be generated.

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
| Bundled files or manifest cannot be verified | Re-extract a complete matching preview |
| Runner is in use | Exit the game and its launcher normally, then retry saving |
| Installed version is unknown or same-version contents differ | Keep the existing file and use a matching package; do not force a replacement by deleting metadata |
| A newer compatible Runner is retained | This is expected downgrade protection |
| Shared location cannot be confirmed | Reopen Manager from ordinary File Explorer as described below |

WinUI prepares Runner when saving a profile. The retained Dioxus application's Settings repair action is a separate UI.

## Manager asks you to reopen it from File Explorer

Some development or packaged host environments can redirect literal AppData paths into a private file view. A file existing there does not prove that ordinary Steam can see it.

Close Manager. Open the complete preview directory through **ordinary Windows File Explorer**, then double-click Manager and save the profile again. Use the stable shared Runner path in the newly generated command.

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

English is the default for a missing or unknown language value. Both Managers use `en-US` and `zh-CN`. Changing this preference does not change profiles, user-entered text or log contents.

If the file is malformed, contains duplicate keys, exceeds the supported size/depth, or cannot be safely written, Manager reports the problem and preserves it. A failed preference write keeps the previous UI language. Keep a copy before manually repairing a settings file; do not delete `profiles.toml` to reset a language preference.

System-owned picker text and raw external diagnostics may follow the Windows/system language. Saved game names and argument values are intentionally not translated.

## Share a useful problem report

Include the Manager variant and revision, Windows version, AppID, selected target, runtime/working directories, wait mode, whether direct launch works, and the relevant latest log entries. Describe whether the failure occurred before the title screen, during play or after normal exit.

Review any paths and logs before sharing them: they can contain user names and original launch arguments. Do not attach credentials, your full Steam account configuration, game files or saves by default.

Restore the Steam Launch Options value you kept before setup if you need to undo the test. Keep naturally updated saves unless you have a separate, deliberate recovery plan.
