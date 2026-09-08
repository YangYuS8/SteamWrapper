---
title: Choose a wait mode
description: Decide when Runner should finish, with the actual Windows job, direct-process and named-process boundaries.
---

A wait mode tells Runner when to finish after launching the configured program. This helps Steam track a session even when a short-lived launcher starts the actual game.

The mode does not add achievement logic, enable Overlay, or guarantee a particular Steam playtime result. Verify the actual game and its exit behavior after configuration.

## Start with the Windows default

For a new Windows profile, keep **Wait for the program and its children (recommended)** under **Advanced settings**. Its stored value is `job`.

Older profiles with no explicit `wait_mode` still mean `root`. Loading an old profile does not silently change it to the new default. Review the selection if Steam stops showing the game as running as soon as a launcher closes.

| WinUI choice | Stored value | When it fits |
| --- | --- | --- |
| Wait for the program and its children (recommended) | `job` | Normal starting point for Windows games and launchers |
| Wait only for the launched program | `root` | The selected program itself remains alive for the whole session |
| Wait for a named process | `process_name` | A specific launcher exits and leaves a known, newly started game process |
| Finish immediately after launch | `none` | You intentionally want Runner to stop after starting the target |
| Process group (Linux / SteamOS) | `process_group` | Existing Unix-like platform behavior; not supported for Windows profiles |

Changing only the wait mode does not change the selected executable, working directory or argument rows. See [configuration](/SteamWrapper/guides/configuration/) for those fields.

## Program and children: `job`

On Windows, Runner starts the target suspended, assigns it to a Windows Job Object, then resumes it. Runner waits for the launched program and for the Job to become empty.

This can keep Runner alive after a launcher exits while its game continues. The important boundary is **processes assigned to that Job**. A separate broker, an already running service or a launcher-specific process arrangement must not be assumed to belong to it merely because a game window appeared.

Controlled Windows process tests and one recorded CHS launcher-first-exit scenario passed. These results do not establish every launcher's compatibility. If the behavior differs for your game, check the actual target and process lifecycle before changing modes.

The recorded exit status is the **direct launcher's status**, even when Runner waits longer for Job members. A logged exit code 0 does not prove that every descendant game process exited with code 0.

## Direct program only: `root`

Runner starts the selected program and waits for that direct process to exit.

Use this when the selected EXE is the actual long-running game, or when waiting for that one program is deliberate. If it only starts another process and exits, Runner can finish while the game is still open. That is the expected limitation of `root`.

## Named process: `process_name`

Use this as a deliberate compatibility option for a launcher that exits before a known game process.

Enter the **actual process name**, for example `ExampleGame.exe`, in **Process name**. It is an exact process-name match, not a file path or a window title; use the name and spelling shown for the running program.

The current sequence is:

1. Record matching processes that already exist.
2. Start the configured target and wait for that launcher to exit.
3. Look for a new matching process for up to **30 seconds**.
4. Keep waiting while new matching processes remain, allowing a **500 ms** gap for replacement processes.

Checks run about every **100 ms**. Waiting after discovery has a **24-hour** limit. Reaching a limit reports an error; it does not establish that the game session finished normally.

Processes matching before launch are excluded using process identity, but an unrelated matching process started afterward can still be included. This mode cannot prove ownership by your game. A process that appears and exits before observation may also be missed.

Because discovery starts after the direct launcher exits, choosing the actual game EXE as both the target and the process to wait for is usually not the intended setup: it may already be gone by discovery time. Prefer `job` or `root` for an ordinary direct game launch.

The returned exit status is the launcher's status, not an exit-code report for all matched processes.

## Finish immediately: `none`

Runner reports a successful start and exits without waiting for the game. This is not the normal choice when the goal is to keep Steam's running state aligned with the full session.

A successful launch result in this mode means the process was started, not that gameplay or normal exit was verified.

## Process groups and other platforms

`process_group` is the retained Unix-like implementation. The current Windows Runner rejects it, and WinUI disables it for Windows profiles.

A profile explicitly marked for Linux or SteamOS is viewable but not editable in the Windows preview. This option does not provide Windows process groups or prove Proton/Steam Deck compatibility. New Linux/SteamOS expansion remains deferred.

## Check a changed mode

Save the profile, preserve the previous Steam Launch Options, and use the generated command from the same Steam library entry. Close Manager before the test.

Observe the actual game opening, whether a launcher exits first, and whether Steam returns to its stopped state after normal game exit. If Steam stays running, inspect the remaining processes before ending anything; a launcher may keep a helper alive. Avoid terminating an active game with unsaved progress just to clear a status indicator.

See [troubleshooting](/SteamWrapper/guides/troubleshooting/) for logs and common symptoms, or the [Runner implementation](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/runner/src/platform/mod.rs) and [Windows Job implementation](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/runner/src/platform/windows.rs) for exact behavior.
