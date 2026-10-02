# <tag> — WinUI Windows x64 preview

SteamWrapper's WinUI 3/C# Manager is an **unsigned prerelease for Windows 11 24H2 x64**. It includes the complete self-contained Manager layout and independent Rust Runner. It is not a setup installer or a stable Windows delivery claim.

## Changes

- <Describe the changes in this version and their player-visible result.>

## Known limits

- <Describe version-specific unresolved issues and the scope of verification.>
- Publisher signing, a WinUI installer, clean-system/update/uninstall acceptance and the optional application updater remain unfinished.
- Configure games in Manager, then launch through Steam with Manager closed. Steam Launch Options are copied manually; automatic apply/restore is not included.
- Game, launcher, Overlay and achievement observations apply only to the recorded tested scenarios.

## Install, update and recover

Download `SteamWrapper-<tag>-win-x64.zip` and `SHA256SUMS` from the same release. Verify the ZIP's SHA-256, extract every file and open `SteamWrapper.Manager.exe` through ordinary File Explorer. Keep all supporting resources and `Runner/` files together. No developer SDK installation is required to use the downloaded complete application.

Close Manager and let active game/Runner sessions finish normally before replacing application files. Extract an update into its own directory. Profiles, preferences, backups, logs and stable Runner remain under `%LOCALAPPDATA%\SteamWrapper\`; Steam must keep referencing the stable `bin\SteamWrapperRunner.exe`, not the ZIP's bundled Runner. If installation/repair reports a busy file or unknown Runner version, retain the working copy and configuration and follow the reported recovery instructions.

See [installation and recovery](https://yangyus8.top/SteamWrapper/guides/installation/) and [troubleshooting](https://yangyus8.top/SteamWrapper/guides/troubleshooting/). Checksums establish consistency with the listed assets, not publisher identity. Removing the extracted Manager directory does not restore Steam Launch Options or remove the separate stable Runner/data.
