<a id="官方安装与汉化版分开存放"></a>

# Keep official installations and translated games separate

**English** | [简体中文](translated-games.zh-CN.md)

Initial record: 2026-09-07; series acceptance update: 2026-09-08. Applies to the Windows WinUI preview and independent Runner. Testing expanded from 9-nine Episode 2 to the rest of the series, with launch, Chinese content and exit results recorded separately for each game.

<a id="两个位置分别负责什么"></a>

## What the two locations mean

| Location | Purpose |
| --- | --- |
| Steam installation | The official game directory managed through Steam's local installation manifest; receives official updates and integrity verification |
| Actual game folder | The complete translated build or custom launcher selected by the player; may be outside all Steam libraries |

Steam verification and updates maintain the publisher's build. Translated changes to official programs or resources cannot also remain identical to the official version. Two independent copies prevent verification/updates and translations from overwriting each other. Official updates construct new files and replace old ones; see [SteamPipe's file update mechanism](https://partner.steamgames.com/doc/sdk/uploading#content_structure). This explains the risk of mixed builds, but does not prove that verification overwrote files in the earlier local incident.

The actual game folder must contain the complete resources matching its translated entry point. Do not share updatable executables or resources between the two locations through hard links or directory junctions. Running outside the library cannot repair missing or mixed files. The main cost is the extra disk space for an official copy.

<a id="配置与迁移顺序"></a>

## Configuration and migration order

1. Preserve a complete copy of the current build and independently back up confirmed saves in the game directory, user directories and Steam remote storage. Record launchability separately from backup completeness.
2. Prepare a complete, directly runnable translated build in an independent directory outside the library. For the direct baseline, navigate into that game folder in ordinary Explorer and double-click the same EXE that Runner will launch; check the title, Chinese content and normal exit. Executing an absolute EXE path from Explorer's address bar while it remains in the parent directory is not an equivalent baseline: the launch context may differ. A copy of a previously failing directory is not a repaired build.
3. Once the translated copy and saves are protected, restore the original Steam directory to a complete official installation and verify it. Do not repair an unprotected mixed directory, or automatically resolve a cloud conflict by restoring old saves.
4. Keep the original AppID in Manager. Set **Actual game folder** to the external directory and choose its EXE. An empty working directory uses the actual game folder; review and change an explicitly configured working directory in an older profile. Changing only the EXE does not change an already populated directory.
5. Record Steam's previous Launch Options, paste Manager's generated command, close Manager, then launch and exit normally through the original Steam library entry. Check the actual entry point, working directory, Steam status and playtime separately; restore the previous options when appropriate.

Launch Options remain:

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

Runner reads the profile's `game_dir`, `target`, `working_dir` and arguments by AppID. The original Steam command is received and logged; the official EXE is not launched alongside the selected target. Directory separation requires no Runner or TOML protocol change.

Manager obtains the Steam installation location from read-only local discovery. Displaying it does not establish that the official files passed verification. The actual game location remains in the existing `game_dir` field, and scan results must not overwrite the player's configuration. If the official directory is undiscovered, the translated directory must not be presented as its substitute.

<a id="汉化版能否正常触发成就"></a>

## Can translated builds unlock achievements normally?

Potentially, if that Steam AppID has achievements and the translated build retains both the corresponding progress triggers and Steamworks integration.

| Translation approach or failure | Assessment |
| --- | --- |
| Steam-based build changing only text/resources while retaining achievement logic | Most promising; requires the author's compatibility information and real progress testing, not just a patch name |
| Steam interfaces remain, but AppID, working directory, dependencies or launch context are wrong | Correcting configuration may restore existing capabilities; successful initialization and submission need evidence |
| Complete package based on another release without Steam integration | Launching from Steam, setting an AppID or adding a DLL cannot supply the missing story-event mappings and achievement calls |
| No confirmed achievement set for the AppID | Lack of unlockable achievements cannot be blamed on the translation or Runner |

Steamworks must initialize successfully before the game can use its interfaces. The Steam client, current user, game license, AppID and runtime libraries affect initialization; [Valve's API overview](https://partner.steamgames.com/doc/sdk/api#SteamAPI_Init) lists these conditions. An external path does not inherently mean initialization fails, but some games may restart the version in Steam's installation directory, so observe the actual processes.

Games call `SetAchievement`, or update associated statistics, when conditions are reached. `StoreStats` submits to the server; callbacks and Steam's achievement state can confirm the result. The client may also submit when the game exits, so lack of an explicit submission call does not prove unlocking is impossible. Increased playtime or a working Overlay is not evidence of achievement success. See [ISteamUserStats](https://partner.steamgames.com/doc/api/ISteamUserStats#SetAchievement). Its documentation currently marks `RequestCurrentStats` deprecated; an old tutorial's sequence is not a universal requirement for current versions. The interface version actually used by an older game still needs separate assessment.

A `steam_api.dll`, exported functions or `SetAchievement` bytes establish at most the presence of relevant components or markers. They do not prove the translated entry point loads them, scripts trigger calls, initialization succeeds or the server accepts a submission. Conversely, a negative static scan cannot exclude dynamic loading or scripts inside resources.

SteamWrapper configures and waits for games. It adds no achievement-writing API, fabricated progress, DLL injection or game binary modifications. The most useful next step is to find a translated build retaining the original Steam achievement logic and verify it through normal gameplay.

<a id="9-nine-的具体证据"></a>

### Specific evidence for 9-nine

On 2026-09-07, the official stores, public global achievement pages and keyless `GetGlobalAchievementPercentagesForApp/v0002` endpoint were queried without looking up a player's account:

| Game / AppID | Public evidence | Conclusion |
| --- | --- | --- |
| Episode 1 / 976390 | Store lists achievements; official global page shows 4; public endpoint returns HTTP 200 with 4 | Four official achievements confirmed for investigation |
| Episode 2 / 1033420 | Store does not list achievements; endpoint returns HTTP 403 | Achievement set unconfirmed; 403 does not mean zero |
| Episode 3 / 1142830 | Store does not list achievements; endpoint returns HTTP 403 | Achievement set unconfirmed; 403 does not mean zero |
| Episode 4 / 1424660 | Store does not list achievements; endpoint returns HTTP 403 | Achievement set unconfirmed; 403 does not mean zero |
| NewEpisode / 1890120 | Store does not list achievements; endpoint returns HTTP 403 | Achievement set unconfirmed; 403 does not mean zero |

Sources: [Episode 1 global achievements](https://steamcommunity.com/stats/976390/achievements/), [Episode 1 store](https://store.steampowered.com/app/976390/), [Episode 2 store](https://store.steampowered.com/app/1033420/), [Episode 3 store](https://store.steampowered.com/app/1142830/), [Episode 4 store](https://store.steampowered.com/app/1424660/), [NewEpisode store](https://store.steampowered.com/app/1890120/).

All five mixed local directories inspected on 2026-09-07 contained `steam_api.dll`, `plugin/krkrsteam.dll` and `plugin/SteamDrawDevice.dll`. The first two contained limited initialization, user-statistics and achievement byte markers, but loading or execution by the translated entry point was unconfirmed. All 148 existing DLL/TPM/selected EXE files checked read-only matched the earlier baseline; Episode 1's translated entry point was still missing. No game resources were unpacked, achievement calls executed or user achievements changed. These may have been leftover components in mixed directories; they establish neither compatibility nor provenance.

On 2026-09-08, Episode 1's independent translated package outside the Steam library on drive G was inspected separately. Normal and delay import tables parsed successfully for all 26 selected files: `nine_kokoiro.exe`, `kokoiro_chs.dll`, `version.dll` and plugins. No explicit Steam dependency or selected Steam API/achievement text marker was found. This directory contained no `steam_api.dll`, `steam.xp3`, `plugin/krkrsteam.dll` or `plugin/SteamDrawDevice.dll`; components from the previous day's mixed directory are not evidence for this package. The game EXE explicitly depends only on Windows libraries, the translation DLL only on `kernel32/comctl32`, and `version.dll` exports compatible version-query functions.

This static inspection found no positive evidence that the independent package retained achievement logic. The translation DLL could still contain packed or dynamic logic; scripts inside resources, actual API initialization and story-event calls were not tested, so the result does not establish absolute incompatibility. No game was run, save contents read or achievement API called in this inspection. Raw results remain in the ignored `target/real-steam-validation/nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf/entry-audit/episode1-steam-static.json`, separate from the preceding mixed-directory records.

The [original Yingkong Episode 1 release post](https://bbs2.kdays.net/read/64426) and [Episode 3 v1.1 release post](https://bbs2.kdays.net/read/74486) were found, but no promise of original Steam achievement compatibility was found. The Episode 3 post explicitly excludes the DL edition, illustrating the need to match a patch to its base build; this does not identify the local package's edition. [Denpasoft's official Episode 1 DLC instructions](https://support.denpasoft.com/portal/en/kb/articles/installing-9-nine-episode1-dlc) assume an installed Steam edition, but likewise make no promise about third-party translations.

Directory separation and launch testing expanded to all five games; results follow below. After its translated entry point was restored, Episode 1 passed direct launch and Steam → Runner verification through the Chinese opening. Steam displayed 0/4 achievements, but the test stopped at the first story line before any achievement condition, so this is not an achievement compatibility failure. Subsequent testing must reach conditions through normal gameplay and observe the outcome while checking current cloud status. Do not edit saves to fabricate progress or choose between local and cloud progress for the player.

<a id="存档与云同步需要分别核验"></a>

## Verify saves and cloud synchronization separately

Steam Auto-Cloud uses publisher-defined paths and matching rules, which may include the official installation directory. Redirecting Runner does not necessarily redirect synchronization to the external translated folder. Games using the Remote Storage API behave differently; see [Steam Cloud paths and integration](https://partner.steamgames.com/doc/features/cloud). Official and translated builds may also use incompatible save formats.

Keep independent backups until formats, actual read/write locations and conflict handling are verified; do not automatically merge the two sets of saves. Episode 1 showed a cloud conflict during testing on 2026-09-07. During acceptance after restoring the translated entry point on 2026-09-08, cloud synchronization remained enabled and up to date, with no conflict. This does not prove Steam synchronized the external translated saves. Any new conflict requires the player's choice of version; neither reuse the previous day's conflict state nor automatically overwrite progress.

<a id="2026-09-07-本机实施与研究记录"></a>

## Local implementation and research on 2026-09-07

A complete copy of Episode 2's then-failing build was made in a newly created backup directory outside the library: 90 files, 6 subdirectories and 3,108,545,018 bytes. Per-file SHA-256 matched for the source before/after reading and the copy; file/directory sets were unchanged. Source and destination handles confirmed ordinary physical paths; links were not followed and no existing destination was overwritten. This protected the failing build; it was not a repaired or officially verified version.

As of that date, the location of a complete runnable Episode 2 translation/backup was still missing and had been requested from the user. The original directory was not moved, Steam repair/official restoration was not performed, and real profiles and achievements were not changed. Migration depended on a usable translated source. Read-only raw evidence remains under the ignored `target/real-steam-validation/nine-20260907T054031Z-8615e539097a4cc18efedeb38dd2f0f5`:

- `episode2-complete-backup-20260907T072842Z-2743e53469bf4232a12e37c7d04e89df/`: complete copy and source before/after digest checks; exact private paths remain local.
- `steam-interface-static-20260907T073052Z-2a9e83ee/`: components, narrowly matched markers and static-evidence limitations.

UI verification used disposable `STEAM_DIR`, `LOCALAPPDATA`, `XDG_DATA_HOME` and `STEAMWRAPPER_E2E_ROOT` fixtures. Passing a sample configuration was not presented as real achievement or migration success.

WinUI now displays a read-only Steam installation location and an independently editable actual game folder. Associated tests ran red before green. A real duplicate AppID across two Steam libraries exposed early scan deduplication; the fix marks installation ambiguity and does not prefill an arbitrary location for a new profile. This marker exists only in discovery results, not profiles/TOML.

- `mise run winui:test`: 49/49 passed, including 6 new directory-association/conflict regressions. Red/green records are ignored under `target/steam-installation-tests/`.
- `mise run winui:publish`: final self-contained Release publish passed.
- Native isolated verification: official and external locations displayed separately; saving preserved `game_dir`, target and unknown fields and generated the existing Launch Options format. After adding a duplicate manifest and reloading, the installation location showed unknown and profile bytes were unchanged. A new ambiguous profile had an empty actual game folder. The sample was discarded through the normal prompt and Manager exited. Evidence: `target/translation-isolation/ui-40a48037fdf04ae195f311c8b57c87c0/native-validation.json`.

This round changed neither the TOML/Runner contract nor Runner distribution. The full local cross-language/process gates were not repeated; CI retained its existing checks. No player achievement was triggered or modified.

<a id="2026-09-08-系列隔离验收补充"></a>

## Series acceptance update on 2026-09-08

Each game has separate results. Chinese content, normal exit and achievement integration are distinct acceptance criteria:

| Game / AppID | Current launch verification |
| --- | --- |
| Episode 1 / 976390 | Restored translated entry point reached the Chinese opening and exited normally through both direct launch and Steam → Runner; CHS launcher exited first while Runner waited for the actual game |
| Episode 2 / 1033420 | Steam → Runner reached the Chinese opening and exited normally; passed |
| Episode 3 / 1142830 | Steam → Runner reached the Chinese opening and exited normally; passed |
| Episode 4 / 1424660 | Steam → Runner reached the Chinese opening and exited normally; passed |
| NewEpisode / 1890120 | Steam → Runner reached the Chinese opening and exited normally; passed |

The user placed translated builds in independent directories outside Steam libraries and reported restoring the official installations. Episode 2 (1033420) used its translated EXE from the original Steam entry through stable Runner; the Chinese title, menu and first story line were confirmed. Game and Runner exited normally, and displayed playtime rose from 7 to 8 minutes. Episode 3, Episode 4 and NewEpisode also completed their Chinese-opening and normal-exit checks. None of these results verifies achievements.

Episode 1's follow-up after restoration also completed, as detailed below. All five shared profiles were saved through normal Manager operations. All test Steam Launch Options were restored to empty. Episode 1 originally lacked the field and ended with an empty string, restoring equivalent launch behavior. Saved profiles alone therefore do not make Steam launch the translated builds.

Episode 2 initially launched from an absolute EXE path entered in Explorer's address bar while Explorer remained in the parent directory; the game ran but story text was Japanese. Navigating into the translated package and double-clicking the same EXE then showed the Chinese title and menu. Runner also showed Chinese when launched in the correct actual game folder. The context difference was reproduced, but the first process's working directory was not directly measured; the underlying cause remains an inference. Correcting the actual game folder and acceptance procedure resolved this case without modifying game files, Runner or the TOML protocol.

Local evidence remains under the ignored `target/real-steam-validation/nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf/`: `1033420/observation.json` records Steam playtime, processes and exits; `entry-audit/episode2-language-assessment.md` records the direct-launch comparison and limits. The failed-build records from 2026-09-07 remain separate from these new-directory results.

<a id="第一部原始入口的早期直接启动故障"></a>

### Earlier direct-launch failure of Episode 1's original entry point

At 11:36:20 on 2026-09-08 (Asia/Shanghai), launching the existing `nine_kokoiro.exe` from the actual game folder in ordinary Explorer produced PID 528. It never reached the title and showed only an Information error. Encoding the garbled text as CP936 and decoding as CP932 recovered “プロダクトIDチェック処理の起動に失敗しました”, meaning “Failed to start the product ID check process.” After ordinary confirmation, the process was observed gone at 11:37:49. Its exit code was unconfirmed; this was a launch failure.

The directory inspection, including hidden files, then found no other translated entry point or launch script; the other two EXEs were an updater and uninstaller. Included instructions did not identify a specific missing launch dependency. Neither the [original translation post](https://bbs2.kdays.net/read/64426) nor the [publisher support page](https://www.clearrave.co.jp/support/) provided a clear explanation for the complete error. It localized the failure only to starting the game's product ID check, not to an invalid license, particular missing DLL or incompatible Windows version. Reproduction without Runner also did not establish a Runner defect.

The same ignored evidence root contains `976390/direct-resumed-observation.json` and `entry-audit/episode1-product-id-assessment.md`. The original entry point's specific failing dependency was not confirmed. This stage ran no updater/installer, changed no product check, and neither unpacked nor patched game files.

A later Defender-record query confirmed that another entry point, `nine_kokoiro_chs.exe`, had been quarantined before the file baseline. Under new user authorization, that entry point and two included patch files were exported from quarantine and restored only to missing locations, overwriting neither existing programs nor saves. Restoration itself did not execute the entry point and is not launch or achievement acceptance. Detection labels and static loader characteristics also do not establish a false positive. See [quarantine records and restoration](real-steam-validation.md#episode1-quarantine-restoration) for the scope; subsequent runtime results are separate below.

<a id="第一部恢复后的-chs-启动与等待验收"></a>

### Episode 1 restored CHS launch and waiting acceptance

At 14:06:56–14:08:31 on 2026-09-08 (Asia/Shanghai), double-clicking restored `nine_kokoiro_chs.exe` in the actual translated folder launched a CHS process that exited first while the actual game kept running. The title and first story line were Chinese; the main menu was English, top menu Japanese and exit confirmation Chinese. This opening check does not claim complete UI translation. No save was manually written or loaded.

The Steam path at 14:15:53–14:18:15 showed `Runner 14212 → CHS 18876 → game 16512`. After CHS exited at 14:15:55, the game and Runner continued for roughly 2 minutes 21 seconds until normal exit. Manager confirmed `job`. Independent observation recorded no sampling errors, no metadata failures and no final leftovers. This verifies this local early-exiting CHS launcher, not all launchers, and is not direct Job membership inspection. Logs confirm exit 0 only for CHS and Runner; the current [Windows job implementation](../crates/runner/src/platform/windows.rs) returns the launcher's status, and the actual game's exit code was not recorded.

Displayed Steam playtime rose from 36 to 38 minutes and returned to Play on exit. Cloud remained enabled and current, without conflicts. Achievements remained 0/4 and no trigger condition was reached; achievement compatibility and translated-save cloud synchronization remain unverified.

Four pre-existing save changes were recorded and checkpointed before launch. Relative to each preceding snapshot, direct and Steam launch stages each naturally updated only five `savedata` files. Other files and the 68 official files were unchanged; all three restored hashes matched, with no added or missing files. All 24 original/checkpoint backup copies were intact and current game writes were retained. See [real Steam validation](real-steam-validation.md) for the full record. Ignored local evidence includes `976390/restored-chs-steam-observation.json` and `976390/after-recovered-chs-steam-20260908T061902Z-integrity-summary.json`.
