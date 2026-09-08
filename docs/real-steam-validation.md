<a id="windows-真实-steam--galgame-验证"></a>

# Real Steam and galgame validation on Windows

**English** | [简体中文](real-steam-validation.zh-CN.md)

Updated: 2026-09-08. Code baseline: `v2`, WinUI configuration preview and independent Rust Runner. The user explicitly authorized testing installed galgames on this computer without damaging game files. Each round uses a separate file baseline. Historical results from 2026-09-07 remain below; separate-directory retests from 2026-09-08 follow them.

**Current conclusion: 9-nine Episode 1, Episode 2, Episode 3, Episode 4 and NewEpisode all passed Steam → stable Runner → translated game in an independent directory → normal exit.** All five showed a Chinese opening and increased Steam playtime. Episode 1 also passed the real early-exiting translation-launcher case, with Runner continuing to wait for the actual game. Its Steam logs record exit 0 for the launcher and Runner, not the actual game. The other four have exit 0 records for game and Runner. Episode 1 and NewEpisode have English main menus, Japanese top menus and Chinese exit confirmations; Episode 4's top menu is Japanese. These are not fully translated interfaces.

Episode 1's earlier direct `nine_kokoiro.exe` launch failed to start its product ID check. After confirming that Defender quarantined the translated entry point before the baseline and restoring it at the user's request, both direct and Steam launches of `nine_kokoiro_chs.exe` succeeded; the separate acceptance stage is recorded at the end. All five Manager profiles are saved, but test Steam Launch Options were restored to empty. Translated launch commands have not been persistently applied. Natural achievement unlocking and Steam Cloud synchronization of translated saves remain unverified.

<a id="2026-09-07-历史验证"></a>

## Historical validation on 2026-09-07

The records before “Separate official/translated directory retests on 2026-09-08” describe observations from 2026-09-07, not the later restored official and separately stored translated builds.

**That day's conclusion: The NOexistenceN of you AND me passed Steam → stable Runner → game → normal exit, with Steam status, cloud synchronization and displayed playtime checked.** Earlier OS Error 3 failures came from the development host's redirected AppData file view. Running Manager from ordinary Explorer and installing at the stable location visible to Steam made the same product command work. This result covers only the game and local environment described below.

In that day's later 9-nine retests, Episode 2, Episode 3, Episode 4 and NewEpisode failed before the title. Direct launch of the same translated EXEs from ordinary Explorer reproduced the respective errors; those four had not passed normal launch. Episode 1 had not launched because its translated entry point was missing and cloud saves conflicted.

<a id="测试对象与保护措施"></a>

## Scope and protection

The selected game was **The NOexistenceN of you AND me** (`2873080`), a Windows Unity game using original target `TheNOexistenceNofyouANDme.exe` in a Steam library path containing spaces. The system was Windows 11 build 26200 x64.

Steam's native Properties UI confirmed initially empty Launch Options. The game directory contained 35 files totaling 2,770,322,086 bytes; a per-file SHA-256 baseline was created. Cloud was initially out of sync. Only after a normal Steam retry succeeded without a progress conflict were the 4 existing saves backed up and checked. Cloud stayed enabled throughout this Unity validation. Testing reached only the title and selected Exit Game, without continuing, loading or creating progress.

Real user configuration, save backups, complete Steam configuration and raw logs remain in ignored local `target` directories, outside commits and CI artifacts. The test agent did not modify, replace, repair or uninstall game files, or operate security software. Changes naturally produced by the game were recorded separately at each stage.

<a id="结果"></a>

## Results

| Check | Actual observation | Result |
| --- | --- | --- |
| WinUI configuration | Real library scan showed 43 games; selected target, saved a new Windows `job` profile, installed stable Runner and generated Launch Options. First copy failed, retry succeeded; pasted command checked character for character before launch | Passed, with copy retry recorded |
| Manager independence | Manager was closed for Steam attempts and direct Runner comparison | Passed |
| Original Steam launch | With empty options restored, Steam reached the title at 11:32; normal exit at 11:33, game exit 0 in Steam logs, launchable and cloud synchronized | Native baseline passed |
| Original Steam playtime | Client changed from 11.1 to 11.2 hours after the native baseline | Native baseline only; not attributable to Runner |
| Direct Runner | At 11:55, stable Runner launched the same profile with target `SteamAppId` / `SteamGameId` in the child environment; Runner → game → Unity helper chain and real title observed. Normal exit at 12:00; Runner logged exit 0 and all three processes ended | Runner comparison passed for this real game; not a Steam button launch |
| Earlier Steam → Runner attempts | Five attempts below failed with `OS Error 3` during `CreatingProcess`; no Runner created | Historical failure, later diagnosed and resolved |
| Ordinary desktop configuration | Opening the same Manager from Explorer initially showed no profiles or Runner. Rescanned, saved `job` profile and installed Runner; generated command was identical to the failed attempts | Passed without changing command syntax |
| Complete Steam → Runner session | Play clicked at 12:46:03; Steam → Runner → game → Unity helper observed with Manager closed. Game stayed at title; normal exit at 12:53:33, Steam recorded exit 0 for all three and all processes ended | **Passed for this game** |
| Wrapped status and playtime | Steam showed Stop while running, then Play and cloud Up to date; displayed time rose from 11.2 to 11.4 hours | Passed; rounded display difference is not exact session duration |
| Restoration and integrity | Options restored to empty, cloud still enabled/synchronized; all 35 game files and 4 original saves matched original lengths/SHA-256, with no added/missing game files. Save handles confirmed the real LocalLow paths | Passed; no saves restored or overwritten. Normal Unity logs/cache are distinct from save changes |

The Steam creation comparisons kept the stable Runner file and target profile unchanged; they did not change the product command format:

| Local time | Launch Options variation | Result |
| --- | --- | --- |
| 11:25 | Generated format: `"<stable-runner-path>" --appid "2873080" -- %command%` | OS Error 3 |
| 11:37 | Removed only quotes around the space-free Runner path | OS Error 3 |
| 11:42 | Removed only quotes around the numeric AppID | OS Error 3 |
| 12:03 | Changed only Runner path separators to forward slashes | OS Error 3 |
| 12:29 | Original format, with brief ETW file-access diagnostics | OS Error 3 |
| 12:46 | Original format; installation performed by Manager opened from ordinary Explorer | Launched successfully, normal exit at 12:53 |

<a id="根因与产品修复"></a>

## Root cause and product fix

Earlier shell `File.Exists`, digests and direct launches succeeded inside the development host's inherited file view, without proving ordinary Steam could see the same file. `GetFinalPathNameByHandleW` revealed a logical request for `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe` resolving to `%LOCALAPPDATA%\Packages\<host-package>\LocalCache\Local\SteamWrapper\bin\SteamWrapperRunner.exe`. Visible contents had identical digests, but an ordinary desktop Manager initially saw no profiles and no Runner. The same command worked immediately after ordinary desktop installation, confirming the local file-view cause.

Windows may redirect new AppData files for affected desktop applications into private storage and present a merged view that is not visible to other processes. See [Microsoft's AppData redirection documentation](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes). Package-identity queries for the local shell, Steam and affected Manager all returned no package identity; that query cannot replace file-handle checks. All were x64, same user and medium integrity. ACLs, security software and game installation locations were not changed.

WinUI configuration services now check final handle paths for existing `profiles.toml`, stable Runner and installation candidates. Redirection yields a not-ready result and a prompt to reopen from Explorer. Legitimate junctions/symlinks are resolved separately, and case and extended DOS/UNC prefixes normalized. Private cache paths are never written into Launch Options. Runner, TOML/CLI and `job` waiting behavior were unchanged. This is a location check, not a guarantee about all Steam permissions or launch environments.

Nine location regressions were added, covering existing Runner, new installation/upgrade candidates, profile-only redirection, native handles and real junctions. Key missing behaviors were observed failing before implementation. All 43 C# tests passed, as did cross-language configuration and real Runner contracts. Native verification after republishing showed the host-launched Manager reporting redirection and withholding copyable options after save. Explorer-launched Manager saved and generated the original command normally; its actual parent was confirmed as `explorer.exe`.

<a id="etw-诊断范围"></a>

## ETW diagnostic scope

The user-started elevated coordinator completed and stopped a 30-second capture, leaving no active session. Steam was observed opening the correct logical Runner path and successfully opening the target game directory/EXE. Seven status-parser failures mean the original capture cannot establish the precise failure NTSTATUS for opening Runner; guessed status codes were not reported as evidence. Signed-status overflow was fixed offline and six status examples passed, without another real launch.

The kernel provider did not restrict PIDs as intended: 44,569 events arrived, and the consumer discarded 43,979 non-target-PID events, retaining only target-PID Runner/game-related paths. Lost event count was zero. No system-wide ETL, file contents or other-process commands/environments were written. This was not a kernel capture limited to Steam's PID. Tools remain ignored in `target/steam-etw-diagnostic`, outside the product.

<a id="2026-09-07-历史9-nine-重测-ep1-阻塞其余四部启动失败"></a>

## Historical 9-nine retests on 2026-09-07: Episode 1 blocked, four launch failures

The user then reported disabling protection and explicitly requested retesting installed 9-nine games. This section records that round without treating the reported security state as independently verified or recommending security changes as a product setup step. The test agent did not restore quarantine, download, repair or replace game files.

<a id="测前基线与存档保护"></a>

### Baseline and save protection

Only manifests in three known Steam libraries were read, confirming Episode 1 (`976390`), Episode 2 (`1033420`), Episode 3 (`1142830`), Episode 4 (`1424660`) and NewEpisode (`1890120`). Per-file SHA-256 baselines covered 450 files totaling 17,915,335,244 bytes across all five games. Another 35 in-game `savedata` files and 14 Steam `userdata/.../remote` files were backed up and verified. Complete game directories were hashed, not copied.

Each read-only source handle's final path matched its requested ordinary path, avoiding another mistaken assumption that host-private files were Steam-visible. Limited discovery under Documents, LocalLow and Roaming found no additional matching save locations; this does not cover every possible layout. Original baselines/backups were retained and later results written separately. Account identifiers, full private paths, save contents and raw logs remain outside the repository.

<a id="episode-1尚未启动"></a>

### Episode 1: not launched

`nine_kokoiro_chs.exe` was still physically missing: read-only open returned `FileNotFoundException` / Win32 error 2 and the parent directory's handle path was normal. Original `nine_kokoiro.exe` existed, but was not substituted without authorization. Steam also showed a cloud/local save conflict awaiting the user's choice. No selection, synchronization or launch had occurred, so this episode remained blocked rather than passed or failed at runtime.

<a id="episode-2runner-与普通桌面直接启动的对照"></a>

### Episode 2: Runner versus ordinary desktop launch

The target was the existing translated entry point `9-nine-天色天歌天籁音.exe` with a new Windows `job` profile. Steam invoked stable Runner first; after restoring empty options, ordinary Explorer directly opened the same EXE. Neither launch reached the title.

| Stage | Observation | Result |
| --- | --- | --- |
| Steam → Runner → translated entry | Manager closed and options checked in Steam Properties; game reported `Cannot convert given narrow string to wide string`. After confirmation, game/Runner ended; a newly created Runner log recorded target exit 1 | Target runtime failure, not Steam failing to create Runner or a title-screen pass |
| Ordinary Explorer direct launch | Same EXE opened at 14:06:56 with confirmed `explorer.exe` parent, no Manager/Runner; same conversion error, then exit after confirmation | Same failure; current evidence cannot attribute it to Runner |
| Steam status and restoration | Empty options restored after first run, cloud current, client displayed 7 minutes | Status only; time during an error is not normal-play acceptance |
| Intermediate integrity after Runner | All 89 original game files, including 7 original `savedata` files, matched SHA-256 with none missing. Only new file: `savedata/krkr.console.log`, 24,434 bytes. Three original external remote files unchanged | Existing programs, resources and saves unchanged; error log recorded separately |
| Final integrity after direct launch | Same 89 files and 7 local saves unchanged, none missing. Only that log grew to 48,866 bytes. Three remote files unchanged with no additions/deletions; original backups intact | Integrity comparison passed; launch remained failed |

Both errors were supported by UI observations and matching technical log lines. The specific conversion cause was not diagnosed; no original EXE or region/language changes were tested. This does not establish incompatibility for all translated entry points or KiriKiri games.

<a id="episode-3相同中文入口的两种启动均失败"></a>

### Episode 3: both paths fail for the same translated entry point

Target `nine_haruiro_CHS.exe` also used `job`. Steam → stable Runner → translated entry was observed, followed by the same conversion error before the title. Game/Runner ended after confirmation and the new Runner log recorded target exit 1. With empty options restored, direct Explorer launch at 14:14:34 confirmed `explorer.exe` parent and no Manager/Runner; the same error occurred before the title and the process exited after OK.

Steam time rose from 1 to 2 minutes, cloud was current and original empty options restored. This records tracking during failure, not successful gameplay. Both launch paths failed, so the conversion error cannot be attributed to Runner, and no successful early-exiting translation launcher with a continuing game was observed.

Full comparisons after Runner and direct launch confirmed all 89 original game files, including 7 existing local saves, and 3 external remote saves unchanged by SHA-256, none missing, backups intact. Only `savedata/krkr.console.log` was added, growing from 24,450 to 48,898 bytes. All source final paths were normal.

<a id="episode-4同样未到标题直接启动复现"></a>

### Episode 4: no title; direct launch reproduces the error

Target `nine_yukiiro_DL_chs.exe` was created through Steam and stable Runner, then reported the same narrow-to-wide-string conversion error. After OK, game/Runner exited, CIM confirmed no leftovers and the new Runner log recorded target exit 1. At 14:30:09, direct Explorer launch of the same EXE without Manager/Runner failed identically before the title and ended after ordinary confirmation.

Original empty options were restored, cloud current, displayed time changed from 1 to 2 minutes. This remains a target failure reproduced directly, not normal gameplay or early-launcher-exit acceptance.

Both full digest comparisons confirmed all 94 original game files, including 7 local saves, plus 3 external remote saves unchanged, none missing and backups intact. Only `savedata/krkr.console.log` was new, growing from 24,122 bytes after Runner to 48,242 after direct launch. Source handle paths were normal.

<a id="newepisode找不到-startuptjs-的错误在直接启动中复现"></a>

### NewEpisode: missing startup.tjs storage error reproduced directly

Steam → stable Runner → `nine_new_chs.exe` was created successfully but reported `Script exception raised` / `Cannot find storage startup.tjs` before the title, distinct from the other three conversion errors. Game/Runner exited after ordinary confirmation and the new Runner log recorded target exit 1. At 14:41:30, direct Explorer launch of the same EXE with confirmed `explorer.exe` parent and no Manager/Runner reproduced the same `startup.tjs` error before the title; all processes ended after confirmation.

Original empty options were restored, cloud stayed enabled/current and displayed time rose from 1 to 2 minutes. No script was supplied, files repaired or entry point changed in response. The error does not prove a same-named physical file was absent; the storage-load failure's specific cause was undiagnosed, and direct reproduction does not support blaming Runner.

All 84 original game files, including 7 existing local saves, plus 3 external remote saves were unchanged in both comparisons, none missing and backups intact. Only `savedata/krkr.console.log` was added, growing from 23,866 to 47,730 bytes; no other additions and normal source handle paths.

<a id="四部实际测试的最终汇总"></a>

### Final summary for the four tested games

| Game | Original game files | Included local saves | External remote saves | Final new error-log bytes | Runner / direct comparison |
| --- | ---: | ---: | ---: | ---: | --- |
| Episode 2 | 89 | 7 | 3 | 48,866 | Both conversion errors, no title |
| Episode 3 | 89 | 7 | 3 | 48,898 | Both conversion errors, no title |
| Episode 4 | 94 | 7 | 3 | 48,242 | Both conversion errors, no title |
| NewEpisode | 84 | 7 | 3 | 47,730 | Both missing `startup.tjs` errors, no title |
| Total | **356** | **28** | **12** | 4 log files | **All four failed normal launch** |

The 356 original game files totaled 14,821,596,814 bytes and all matched their initial SHA-256 with no modifications or missing files. The 28 local saves are a subset; the 12 remote saves are outside the game directories. Each game added one error log, giving 360 final game-directory files. All 28 local-save backups were rehashed successfully. The 12 remote source files were checked again read-only for the final summary, unchanged with no additions/deletions, and their 12 backups remained intact.

Each game's final digests were collected after its own direct-launch exit, not as an atomic snapshot of all four directories. Original options were empty again, games/Runner ended, and cloud enabled/current. The initial five-game 450-file baseline included unlaunched Episode 1; it cannot be described as five games launched or passed. This round did not verify a real launcher exiting before its continuing game.

Process records use periodic sampling that may miss brief processes and are not Job membership queries. Episode 2's older observer had an image-path field problem; separate live CIM records verified the chain. That old field is not reliable path evidence. All four Runner logs recorded target exit 1, consistent with the observed absence of a title screen.

Ignored local evidence root: `target/real-steam-validation/nine-20260907T054031Z-8615e539097a4cc18efedeb38dd2f0f5`:

- `game-baseline-summary.json`, each AppID's `game-files-before.json`, `savedata-backup-manifest.json` and `external-saves/*-manifest.json`: initial baselines/backups.
- `976390-chs-readonly-open.json`: read-only missing-entry open result.
- `1033420-before-play.json`, `1033420-steam-after-runner.json`, `1033420-direct-result.json`: configuration, restoration and direct observations.
- `1033420/runner-exit-evidence.json`: this session's Runner exit code, source limits and filtered technical error lines.
- `1033420/after-runner-20260907T060208Z/`, `1033420/after-direct-20260907T060959Z-d4a88db6/`: full two-stage file digests/differences.
- `external-saves/1033420-after-runner.json`, `external-saves/1033420-after-direct.json`: two-stage external-save comparisons.
- `1142830/runner-exit-evidence.json`, `1142830/direct-explorer-control.json`, `1142830-direct-result.json`, `1142830-steam-after-runner.json`: Episode 3 processes, errors, comparison/restoration.
- `1142830/after-runner-20260907T061308Z-f09216ba/`, `1142830/after-direct-20260907T061556Z-164f36c6/` and `external-saves/1142830-after-*.json`: Episode 3 full file/external-save comparisons.
- `1424660/runner-exit-evidence.json`, `1424660/direct-explorer-control.json`: Episode 4 target exit/direct comparison; `1424660/after-runner-20260907T062750Z-2aa9f641/`, `1424660/after-direct-20260907T063138Z-e7dc216c/` and `external-saves/1424660-after-*.json`: two-stage integrity.
- `1890120/runner-exit-evidence.json`, `1890120/direct-explorer-control.json`: NewEpisode's different error/direct comparison; `1890120/after-runner-20260907T063705Z-e6d49a73/`, `1890120/after-direct-20260907T064305Z-46413362/` and `external-saves/1890120-after-*.json`: two-stage integrity.
- `four-tested-games-final-integrity-summary.json`, `external-saves/four-games-final-summary.json`: only four tested games' totals, final external-save and original-backup checks; excludes unlaunched Episode 1.
- `four-episode-process-exit-audit.json`: four Runner logs, observer completion and final process audit; retains sampling/Episode 2 old-path limitations.
- `final-process-cleanup.json`: no final target processes; all four observers requested stopped, completed and no longer running.

<a id="2026-09-07-历史其他尚未通过的对象"></a>

## Historical other unpassed targets on 2026-09-07

- `ATRI -My Dear Moments-`: read-only baseline and original options checked; cloud unsynchronized, no launch test.
- `9-nine-:Episode 1`: initial read-only inspection found the translated entry quarantined by Windows Defender; it remained missing in the retest with a cloud-save conflict, as above.

These targets could not then count as compatible. The first actually run target was a Unity galgame; as of 2026-09-07, there was no passing evidence for KiriKiri, an early-exiting translation launcher or another real engine.

<a id="本机证据位置"></a>

## Local evidence locations

Local evidence root: `target/real-steam-validation/417fe25d10a54f4b83b02893c0e59489`.

- `2873080-before.json`, `2873080-after-direct.json`, `2873080-after-direct-files.json`: game integrity.
- `save-backups/`, `save-hash-after-direct.json`: existing-save backups and hash rechecks.
- `2873080-direct-start.json`, `2873080-direct-observed-exit.json`, `processes-after-direct.json`: direct Runner comparison. The initial shell wait timed out before normal UI exit; exit evidence comes from Runner/Steam logs, not that shell's process-handle result.
- `2873080-steam-before.json`, `2873080-steam-restored.json`, `2873080-slash-test-and-restored.json`: options records, failed comparisons and restoration.
- `target/real-steam-inventory/unity-launch-log-excerpts.json`: first-failure logs limited to the AppID; later failures remain in local Steam logs/comparison results.
- `path-view-check-20260907T044426Z/path-view.json`: logical/final handle paths, architecture and package-identity checks.
- `etw-coordinated-20260907T042510Z-d681b2a3c6364f76a154739dc4e3d086/`: coordinator status/original capture, with parsing/filtering limits above.
- `2873080-steam-runner-live-chain.json`: successful session's actual process ancestry.
- `after-steam-runner-success-20260907T045708Z/result.json`, `game-files.json`: successful session's Steam tracking/exits and final integrity of 35 game files/4 original saves.
- `final-native-context-validation.json`: native UI, options restoration, both Manager launch contexts and final publish check.
- `target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`: cross-language/Runner contracts after the location guard.

As of 2026-09-07, daily launch was verified for one Unity galgame. That day's four 9-nine tests and direct comparisons failed and added no passes. The round did not establish real custom-launcher compatibility, clean Windows 11 installation, update/uninstall or the full native accessibility matrix, and did not satisfy all [Windows usable-preview gates](windows-v2-design.md#8-实施顺序与停止条件).

<a id="2026-09-08官方版与汉化版分离目录重测"></a>

## Separate official/translated directory retests on 2026-09-08

This section retains the stage before 12:07, when four games had passed and Episode 1's original entry point had failed. The launch/file tables also include afternoon results after restoring the CHS entry point, detailed at the end.

The user placed all five third-party translations in a separate unofficial-games directory and replaced the Steam-library copies with official builds. Current Steam manifests were rescanned and `<SteamLibrary>\steamapps\common\<game>` recorded separately from `<other-games-root>\<game>`. Episode 2 was configured first. After resuming tests, Manager opened from ordinary Explorer saved shared profiles for Episode 3, Episode 4 and NewEpisode. All four actual game folders point to their independent translated directories, keeping original relative target EXEs, empty working directory/arguments/process name and `job` wait mode. Each save and Runner-ready status was confirmed in the UI. Read-only Steam locations still point to the official directories. Stable Runner and `%command%` contracts are unchanged. Manager backed up the real configuration before saving, avoiding the host-private AppData view. Each of the four tests restored original empty options. Episode 1 had no profile at this stage. This round corrected real configuration paths without changing product source or game binaries.

<a id="新基线与隔离检查"></a>

### New baselines and separation checks

Official and translated copies comprised 10 installation directories, 694 files and 33,455,828,870 bytes (about 33.46 GB), all rehashed with SHA-256. Handle paths and file identities revealed no reparse points, multiply linked files or shared file identities between the two builds. Eleven in-installation save candidates, including bundled save resources, totaled 64,745 bytes and were backed up, alongside 15 Steam remote files totaling 10,926 bytes. Source-handle checks and backup digests passed. Unknown custom save locations are not excluded by this inspection.

This baseline protects the files actually present for this round. No Steam integrity repair was run, and hashes alone do not prove every file came from an official release. The September 7 baselines/error logs remained untouched and were not used to judge the new directories as damaged.

<a id="当前启动结果"></a>

### Current launch results

| Game / AppID | Direct ordinary Explorer launch | This round's Steam → Runner | Current result |
| --- | --- | --- | --- |
| Episode 2 / `1033420` | Chinese title/menu, normal exit | Chinese title/menu/first story line; Steam recorded exit 0 for game and Runner, time 7 → 8 minutes | **Basic launch cycle passed** |
| Episode 3 / `1142830` | Chinese title/menu, normal exit | Chinese title/menu/first story line; game and Runner exit 0, time 2 → 4 minutes | **Basic launch cycle passed** |
| Episode 4 / `1424660` | Translated title/Chinese exit confirmation, normal exit; top menu still Japanese | Chinese first story line; game and Runner exit 0, final refreshed time 2 → 10 minutes | **Basic launch cycle passed**, not complete UI translation |
| NewEpisode / `1890120` | Title and normal exit after user handled security prompt; no story entered in this stage | Chinese first story line after NewGame; game and Runner exit 0, time 2 → 4 minutes | **Basic launch cycle passed**; main menu English, top menu Japanese |
| Episode 1 / `976390` | Original EXE failed earlier; restored `nine_kokoiro_chs.exe` showed Chinese title/first line and exited normally | Runner kept waiting after translation launcher exited; Chinese first line/normal exit passed, time 36 → 38 minutes | **Basic cycle and local early-exiting launcher case passed**, details below |

Episode 2's Steam session tracked stable Runner at 10:41:37 local time and the translated EXE in its independent directory at 10:41:40. Steam logged exit 0 for both at 10:43:32. An independent observer recorded Runner/target ancestry and no remaining target processes after normal exit. Increased displayed time confirms client tracking for this session, not exact duration or achievement compatibility.

The three resumed Steam sessions ran with Manager closed and targets in independent translated directories. Steam recorded game/Runner exit 0 for Episode 3 at 11:45:43, Episode 4 at 11:59:31 and NewEpisode at 12:04:56. UI observations confirmed normal exits, Steam returning to Play and cloud enabled/current. Episode 4 first showed 9 minutes after exit, later refreshed to 10; the final display is recorded. Episode 3's observer had one metadata-query failure, but retained correct target paths, ancestry and exit observations, with independent Steam exit logs. That round was not free of metadata errors.

Original empty options for all four were restored through Steam's native Properties UI and reconfirmed by a read-only extraction of only the selected AppIDs' localconfig fields; no other account fields were copied or printed. **Saving a Manager profile does not persistently apply Steam Launch Options.** At this round's end, ordinary Steam entries still launched official builds with empty options. Daily translated launches require applying the verified stable Runner command.

NewEpisode's security-prompt/resumption sequence had two stages. A 10:54 SmartScreen page caused the first pause. After the user reported disabling SmartScreen themselves, a resumed attempt at 11:17 showed a different Open File – Security Warning with unknown publisher, Run/Cancel and Always ask before opening this file. The user handled it, and at 11:20:38 the target process and translation-group title window were observed. Normal exit via Chinese confirmation occurred at 11:22:17. This direct comparison did not enter NewGame; the later Steam session verified Chinese story content. The test agent did not operate those prompts or change protection settings. The first resumed observer ended while the target still ran because a stop request overlapped user action. A supplemental observer reacquired the same process identity and recorded its exit; the first observer's end was not game exit.

Episode 1's 11:30 security prompt is also a historical checkpoint. After the user handled it, `nine_kokoiro.exe` started at 11:36:20 but showed an Information error rather than the title. Re-encoding UIA's garbled text as CP936 bytes and decoding as CP932 reproduced `プロダクトIDチェック処理の起動に失敗しました` (“Failed to start the product ID check process”), without establishing the underlying cause. After ordinary OK, the continuation observer saw exit at 11:37:49. This was direct ordinary Explorer launch with no Runner; the check mechanism was not modified.

<a id="文件与存档复核"></a>

### File and save rechecks

| Game | Original official files | Original translated files | New files in translated folder this round | External Steam remote |
| --- | ---: | ---: | --- | --- |
| Episode 2 | All 68 unchanged, none added/missing | All 68 unchanged, none missing | 7 under `savedata`; later runs update these new files | All 3 original files unchanged after Steam test |
| Episode 3 | All 68 unchanged, none added/missing | All 69 unchanged, none missing | 7 under `savedata` | All 3 original files unchanged after Steam test |
| Episode 4 | All 68 unchanged, none added/missing | All 74 unchanged, none missing | 7 under `savedata` | All 3 original files unchanged after Steam test |
| NewEpisode | All 68 unchanged, none added/missing | All 64 unchanged, none missing | 7 under `savedata` | All 3 original files unchanged after Steam test |
| Episode 1 | All 68 unchanged, none added/missing | 74 unchanged, 5 `savedata` files updated by game runs; none missing | 3 files restored at user's request, subsequent hashes unchanged | All 3 original files unchanged after CHS Steam test |

The table uses each game's latest completed full digest: Episode 2 after Steam and subsequent folder comparison; Episode 3/Episode 4/NewEpisode after their resumed Steam sessions; Episode 1 after restored-CHS Steam acceptance. Programs, resources and official files were unchanged. The first four games' new `savedata` files and Episode 1's five existing saves were updated by the games. Episode 1 had an extra immediate checkpoint to separate pre-existing differences from this run's writes. No files were cleared, old progress restored or data written back to official directories.

At the 11:02 local-time pause awaiting system-prompt handling, all 15 external remote files across five games were independently rechecked: initial digests matched, none added/missing and backups intact. A concurrent read-only Launch Options snapshot confirmed empty strings for Episode 2/Episode 3/Episode 4/NewEpisode and no field for Episode 1. This is a pause-point file state, not launch or save-synchronization acceptance for unrun games.

The 11:02 summary reused Episode 2/Episode 3/Episode 4's latest successful digests and added before/after hashes for then-unlaunched Episode 1/NewEpisode: all 694 originals unchanged, none missing, with only 21 new `savedata` files from three games. All six read-only observers had completed, with no test game, Runner or observer processes left at that point. That summary does not describe later resumed-test file/process states.

Before resumption, 558 original files across both builds of Episode 1, Episode 3, Episode 4 and NewEpisode were compared again, all unchanged with none missing. The retained additions were still the preceding Episode 3/Episode 4's 14 `savedata` files. At 11:14, all 15 original remote files remained unchanged, with four empty options and no Episode 1 field. After NewEpisode's resumed direct launch, all its 132 original files were unchanged; only 7 local `savedata` files were added, all 3 external remote files unchanged and backups intact. These are separate staged comparisons, not overwritten or merged into one simultaneous result.

The 12:07 summary remains separate in `resumed-final-scope-summary.json`: all 340 official and 354 translated original files (694 total) retained SHA-256, none missing. Additions were only 7 local `savedata` files for each of Episode 2/Episode 3/Episode 4/NewEpisode, totaling 28. The 12:07 read-only check confirmed all 15 original remote files unchanged, none added/missing and backups intact. Four options were empty and Episode 1 had no field. Directory hashes came from each latest test stage, not a simultaneous atomic disk snapshot. The old summary remains unchanged and does not describe the later Episode 1 CHS state.

As of 12:07, real Steam launches had succeeded for these four translated installations. This does not generalize to every translation package or prove natural achievements, Auto-Cloud coverage of external translated saves, Job membership or a launcher exiting before its continuing game. The last case was subsequently verified in the afternoon Episode 1 CHS test. Sampling may miss brief processes. Security-prompt assessments came from actual Windows UI, not merely a lack of sampled processes.

This round's evidence remains ignored under `target/real-steam-validation/nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf`, outside commits and CI artifacts:

- `baseline-summary.json`, each AppID's `*-before.json`, `file-identity.json`: new-directory baselines, final paths and identities.
- `1033420/observation.json`, `1033420/steam-gameprocess-scoped.txt`, `observer-ep2-*`: Episode 2 windows, scoped process logs and normal exit.
- Tested AppIDs' `compare-after-folder-summary.json`, Episode 2's `compare-after-steam-summary.json`: staged official/translated directory integrity.
- `external-saves/*-manifest.json`, `1033420-after-steam.json`, `1142830-after-folder.json`, `1424660-after-folder.json`: external-save backups/staged checks; `launch-options-ep2-restored.json`: exact restored options.
- `external-saves/*-final-scope.json`, `launch-options-final-scope.json`: five-game read-only save/options checks at the 11:02 pause.
- `observer-ep3-folder-*`, `observer-ep4-folder-*`, `observer-new-folder-*`, `OBSERVATIONS.md`: direct launches and system-prompt blocking observations/limits.
- `final-scope-summary.json`, `final-process-audit.json`: pause-point original-file, known external-save and process-cleanup summary; not later resumed state.
- Four games' `compare-resumed-before-summary.json`, `1890120/compare-resumed-after-folder-summary.json`, `external-saves/*-resumed-before.json`, `1890120-resumed-after-folder.json`: independent pre-resumption files/saves and post-direct-NewEpisode comparisons.
- `1890120/direct-resumed-observation.json`, `observer-new-resumed-folder-*`, `OBSERVATIONS.md`: the two Windows prompts, user handling, title language and segmented observation through normal exit.
- Episode 3/Episode 4/NewEpisode's `steam-resumed-observation.json`, `steam-gameprocess-resumed-scoped.txt`, `compare-resumed-after-steam-summary.json`: Chinese story, Steam exits and file comparisons; Episode 1's `direct-resumed-observation.json`: direct error/exit.
- `external-saves/*-final-resumed.json`, `launch-options-final-resumed.json`, `resumed-final-scope-summary.json`: resumed final saves, restored empty options and each game's latest digests, separate from 11:02.

<a id="episode1-quarantine-restoration"></a>
<a id="2026-09-08第一部-defender-隔离记录与文件恢复"></a>

## Episode 1 Defender quarantine records and restoration on 2026-09-08

This section records file restoration before the recovered entry point was run. Subsequent launch acceptance is in the next section.

The user explicitly requested restoring Episode 1 files handled by Defender. Read-only detections confirmed quarantine of `nine_kokoiro_chs.exe` at 09:32, followed at 09:33 by included `nine_kokoiro_Patch.exe` and translation patch `Setup.exe`. The historical source drive differed from the current translated directory. These events preceded the 10:29 file baseline, so unchanged originals during testing did not establish a complete translated package at baseline time. Evidence confirms quarantine of the missing entry, but not that it caused every launch problem.

Using valid Microsoft-signed `MpCmdRun.exe`, three exact original paths were exported to separate fresh recovery directories, all calls exiting 0. The specified `-Path` retained quarantine copies. At the user's request, the three missing locations in the current independent translated directory were filled by creating new files without overwriting existing contents. Destination SHA-256 matched exported copies. No official-directory files were written and no recovered entry, patch or installer was run.

An independent full comparison found all 147 original files across Episode 1's official/translated directories unchanged, with only the three recorded additions and matching paths, sizes and hashes. Existing `savedata`, backups and checkpoints remained intact. This verifies restoration scope and protection of originals, not successful launch.

Defender's detection labels for the three files included Trojan or ransomware classifications. Labels alone do not prove harm, and successful restoration does not prove a false positive. The 12 KB translated entry's static structure included original-game/translation-DLL names and process-memory/thread APIs. No trusted publisher signature or prior baseline for that exact file was available for authentication, so it was not reported as passing a safety assessment. The previously run entry was original `nine_kokoiro.exe`; recovered `nine_kokoiro_chs.exe` had not yet been retested at this stage.

Private local evidence remains ignored under `target/defender-recovery/ep1-20260908-130532/`: scoped detections, export results, hashes of the three restored files and static inspection. Recovered files, logs and local security-policy tools are not committed.

<a id="2026-09-08恢复后的第一部-chs-入口与启动器先退验收"></a>

## Restored Episode 1 CHS entry and early-exiting launcher acceptance on 2026-09-08

After the user requested the remaining validation, a fresh 150-file Episode 1 snapshot was made (68 official, 82 translated), with all three restored hashes matching. Four local `savedata` files had already changed at 13:57 before this launch. Current contents were preserved, 8 save candidates backed up and stability checked twice, without restoring old progress. An initial derived check compared JSON time strings directly with PowerShell-converted `DateTime` values and falsely reported instability. Normalizing to UTC ticks confirmed stable hashes, lengths and modification times. Both original records and independently corrected results were retained.

| Check | Actual observation | Result |
| --- | --- | --- |
| Direct folder launch | At 14:06:56, ordinary Explorer double-clicked `nine_kokoiro_chs.exe` in the actual translated folder. Launcher PID 3904 created actual game PID 4160 and exited first. Title and Chinese first line after New Game appeared; normal exit via Chinese confirmation at 14:08:31 | Direct comparison passed |
| Shared configuration | Published Manager opened from ordinary Explorer; added AppID `976390`, external Episode 1 folder, target `nine_kokoiro_chs.exe`, `job`, empty arguments/explicit working directory/process name. Save showed Runner ready and generated the existing stable-path command; Manager then closed | Configuration passed |
| Steam launch | Original Steam entry's Play clicked at 14:15:53. Actual chain: Steam PID 9028 → stable Runner PID 14212 → CHS PID 18876 → actual game PID 16512; both game entries outside the library | Passed, no simultaneous official EXE |
| Launcher exits first | CHS gone at 14:15:55; actual game and Runner continued for about 141 seconds, Chinese first line visible and Steam showing Stop | **Real local early-exiting launcher case passed** |
| Normal completion | Game's own exit confirmation used; game and Runner observed ended at 14:18:15. Steam later recorded CHS and Runner exit 0; actual game exit code not separately recorded | Normal exit observed; launcher exit code is not the game's exit code |
| Steam status | Cloud current and 36 minutes before launch; Play/cloud current/38 minutes after exit. Cloud stayed enabled, no conflict | Status/displayed time passed, not exact duration or translated-save cloud synchronization |
| Restoration and cleanup | Empty options restored in Steam Properties and checked read-only. Previously absent field ended as empty string, restoring equivalent behavior. All five test options empty; Manager, game, Runner and both observers ended | Passed; saved profiles do not mean daily Launch Options are applied |

Both read-only sampling runs had zero snapshot/metadata errors. At 100 ms intervals, sampling observed the launcher and actual game it created, but did not query Job Object members. The real shared `runner-976390.log` final handle path was checked and recorded this profile launch/exit 0. Windows `job` waits for Job completion then returns the launcher's status; that log likewise cannot establish PID 16512's exit code. These observations validate this local launcher case, not all third-party launchers.

Full hashes were collected after direct exit and after Steam exit. Relative to the pre-CHS checkpoint and then the post-direct snapshot, each stage updated only five game-managed saves: `savedata/data_anchor.ksd`, `datasc.ksd`, `datasc~.ksd`, `datasu.ksd`, `datasu~.ksd`. Nothing was added/missing; programs/resources, all 68 official files and the 3 restored files were unchanged. All 24 small backups across the original, pre-restoration and pre-launch batches were intact. Natural game writes were retained, without manual saves, old-slot loading, progress overwrites or rerunning patches/installers. The 3 original external remote files stayed unchanged, which does not establish Steam Cloud coverage of the external translated saves.

Episode 1's main menu was English and top menu Japanese; the title, opening text and exit confirmation included Chinese. Steam showed achievements 0/4 before and after. Testing reached only the first line, before any story achievement condition, so natural achievement success or failure cannot be determined. Runtime acceptance also provides no file-safety or Defender false-positive determination.

Evidence remains in the ignored `nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf` directory above:

- `976390/preflight-before-recovered-chs-20260908T060253Z-validated.json`: pre-existing differences, new checkpoint and stability checks.
- `976390/after-recovered-chs-steam-20260908T061902Z-integrity-summary.json`: integrity of both runtime stages and all 24 backups.
- `observer-ep1-restored-folder-20260908T060345Z-4df8d474c4a84ae7bea6f88b87712c00/`, `observer-ep1-restored-steam-20260908T061333Z-e1a298368a6e4d59acf37cd096607644/`: process identity, early exit and completion.
- `976390/restored-chs-steam-observation.json`, `976390/steam-gameprocess-restored-chs-scoped.txt` and new-stage results under `external-saves/`: scoped logs, external saves and options rechecks.

No product source changed in this round, so already passing full cross-language/process regressions were not repeated. Real-game validation and documentation review were the relevant checks. These five passing games do not automatically satisfy clean-system installation, update/uninstall or other unperformed Windows delivery gates.
