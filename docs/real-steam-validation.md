# Windows 真实 Steam / galgame 验证

更新：2026-09-08。代码基线：`v2`，WinUI 配置预览与独立 Rust Runner。用户明确授权测试本机已安装 galgame，条件是不损坏游戏文件。各轮使用独立文件基线，下面保留 2026-09-07 历史结果，并在文末记录 2026-09-08 分离目录重测。

**当前结论：9-nine Episode 1、Episode 2、Episode 3、Episode 4 和 NewEpisode 均通过 Steam → 稳定 Runner → 独立目录汉化游戏 → 正常退出闭环。** 五部均看到中文开场、Steam 显示时长增加。第一部还通过了真实汉化启动器先退、Runner 继续等待实际游戏的场景；其 Steam 日志只记录启动器和 Runner 退出码 0，未记录实际游戏的退出码。其余四部有游戏与 Runner 退出码 0 的记录。第一部与新章的主菜单英文、顶部菜单日文、退出确认中文，第四部顶部菜单日文，不能写成界面全部汉化。

Episode 1 早先直接运行 `nine_kokoiro.exe` 报产品 ID 检查处理启动失败。查明 Defender 在基线前隔离了汉化入口并按用户要求恢复后，`nine_kokoiro_chs.exe` 的直接及 Steam 启动均成功，详见文末的独立验收阶段。五部 Manager 配置均已保存，Steam 测试启动选项均恢复为空，尚未持久应用汉化启动命令。成就自然触发和汉化存档的 Steam 云同步仍未验证。

## 2026-09-07 历史验证

以下记录至“2026-09-08：官方版与汉化版分离目录重测”之前均为 2026-09-07 的观察，不表示恢复官方版、另放汉化版后的状态。

**当日结论：《不/存在的你，和我》的 Steam → 稳定 Runner → 游戏 → 正常退出闭环通过，Steam 状态、云同步和显示时长均已核对。** 早先的 OS Error 3 来自开发宿主的 AppData 文件视图重定向；从普通资源管理器运行 Manager、安装到 Steam 可见的稳定位置后，同一条产品命令成功。此结果只覆盖下述游戏和本机环境。

当日后续 9-nine 重测中，Episode 2、Episode 3、Episode 4 与 NewEpisode 均在标题前报错，从普通资源管理器直接启动同一中文 EXE 也复现各自错误；这四部当时未通过正常启动验证。Episode 1 当时因中文入口缺失与云存档冲突尚未启动。

## 测试对象与保护措施

主对象为《不/存在的你，和我》（AppID `2873080`），Windows Unity 游戏，原始目标 `TheNOexistenceNofyouANDme.exe`，位于含空格的 Steam 库路径。系统为 Windows 11 build 26200 x64。

通过 Steam 原生属性界面记录原启动选项为空。游戏目录测试前共 35 个文件、2,770,322,086 字节，建立逐文件 SHA-256 基线。首次检查云状态未同步；使用 Steam 正常重试同步成功、未出现进度冲突后，才备份并校验 4 份既有存档。该 Unity 验证始终保持 Steam 云开启，只进入标题画面并选择“退出游戏”，没有进入继续游戏、读取或新建进度。

真实用户配置、存档备份、完整 Steam 配置及原始日志留在本机忽略的 `target` 目录，不进入提交或 CI artifact。测试代理没有修改、替换、修复、卸载任何游戏文件，也没有操作安全软件；游戏运行自身产生的文件变化按阶段单独记录。

## 结果

| 检查 | 实际观察 | 判定 |
| --- | --- | --- |
| WinUI 配置 | 真实库扫描显示 43 个游戏；选中目标、保存新 Windows `job` 配置、安装稳定 Runner、生成启动项成功。首次复制报错，重试后成功；粘贴值在启动前逐字核对 | 通过，记录了复制重试 |
| Manager 独立性 | Steam 启动尝试和直接 Runner 对照时，Manager 已关闭 | 通过 |
| 原始 Steam 启动 | 恢复空启动项后，11:32 从 Steam 打开标题画面；11:33 正常退出，Steam 日志记录游戏退出码 0，状态回到可启动且云已同步 | 原生基线通过 |
| 原始 Steam 时长 | 原生基线后客户端显示从 11.1 小时到 11.2 小时 | 仅证明原生基线，不能归于 Runner |
| 直接 Runner | 11:55 通过稳定 Runner 启动同一配置，子进程环境包含目标 `SteamAppId` / `SteamGameId`；观察 Runner → 游戏 → Unity 辅助进程关系和真实标题画面，12:00 正常退出；Runner 日志记录退出码 0，三个进程均退出 | Runner 与该真实游戏对照通过；不是 Steam 点击启动 |
| 早先 Steam 启动 Runner | 下表五次尝试在 `CreatingProcess` 阶段报 `OS Error 3`，没有创建 Runner | 历史失败；后续定位并解决 |
| 正常桌面配置 | 从资源管理器打开同一 Manager 时，最初显示空配置和未安装 Runner；重新扫描、保存 `job` 配置及安装，生成的命令与失败尝试逐字相同 | 通过；没有改变命令格式 |
| Steam 启动 Runner 闭环 | 12:46:03 点击 Steam 开始，观察 Steam → Runner → 游戏 → Unity 辅助进程；Manager 已关闭，游戏保持标题画面；12:53:33 正常退出，Steam 日志记录三个进程退出码均为 0，进程全部结束 | **该游戏通过** |
| 包装运行状态与时长 | 运行中 Steam 显示“停止”；退出后恢复“开始游戏”、云“已是最新”；显示时长从 11.2 增至 11.4 小时 | 通过；客户端显示有舍入，不能将差值当精确运行时长 |
| 恢复与完整性 | 成功闭环后启动选项恢复为空，云仍开启且已同步；全部 35 个游戏文件与 4 份原存档大小、SHA-256 均与初始基线相同，无游戏文件新增/缺失；存档句柄确认读取真实 LocalLow 路径 | 通过；未恢复或覆盖存档，Unity 正常日志/缓存不等于存档修改 |

Steam 创建 Runner 的对照保持稳定 Runner 文件与目标配置不变，未据此修改产品命令格式：

| 本机时间 | 启动选项变化 | 结果 |
| --- | --- | --- |
| 11:25 | 原生成格式：`"<stable-runner-path>" --appid "2873080" -- %command%` | OS Error 3 |
| 11:37 | 仅移除无空格 Runner 路径的引号 | OS Error 3 |
| 11:42 | 仅移除数字 AppID 的引号 | OS Error 3 |
| 12:03 | 仅将 Runner 路径改为正斜杠 | OS Error 3 |
| 12:29 | 原生成格式，同时执行短时 ETW 文件访问诊断 | OS Error 3 |
| 12:46 | 原生成格式；改由普通资源管理器打开 Manager 完成安装 | 成功启动并于 12:53 正常退出 |

## 根因与产品修复

早先 shell 的 `File.Exists`、摘要和直接启动都在开发宿主继承的文件视图中成功，并不证明普通 Steam 能看到同一文件。`GetFinalPathNameByHandleW` 揭示：逻辑请求为 `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe`，实际文件却位于 `%LOCALAPPDATA%\Packages\<host-package>\LocalCache\Local\SteamWrapper\bin\SteamWrapperRunner.exe`。两处可见内容摘要相同，但普通桌面 Manager 初次运行看到空配置和缺失 Runner。正常桌面安装后，同一命令立即能被 Steam 执行，确认了本机失败的文件视图原因。

Windows 对受虚拟化影响的桌面应用可能将新 AppData 文件写入私有位置，并向应用呈现合并视图；该视图不保证其他进程可见。[微软 AppData 重定向说明](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)。本机 shell、Steam 和受影响 Manager 的包身份查询都返回无包身份，不能用该查询代替文件句柄检查。它们均为 x64、同用户、中等完整性；未修改 ACL、安全软件或游戏安装位置。

WinUI 配置服务现在检查现存 `profiles.toml`、稳定 Runner 和安装候选的句柄最终路径，发现重定向即返回非就绪、提示从资源管理器重开。合法 junction/symlink 独立解析，大小写及扩展 DOS/UNC 前缀正规化；不会把私有缓存路径写入启动项。原 Runner、TOML/CLI 格式和 `job` 等待实现均未改变。这是位置检查，不是对所有 Steam 权限或启动环境的保证。

新增 9 条位置回归（含 Runner 已存在、新安装/升级候选、仅 profile 重定向、原生句柄及真实 junction），关键缺失行为先观察失败再实现；C# 共 43/43 通过，跨语言配置和真实 Runner 契约通过。重新发布后的原生复核显示：宿主启动会提示重定向，保存后不出现可复制启动项；资源管理器启动正常保存并生成原格式命令，实际父进程也确认为 `explorer.exe`。

## ETW 诊断范围

用户启动的管理员协调器已执行并停止 30 秒捕获，未留下活动会话。观察到 Steam 打开正确的逻辑 Runner 路径，以及成功打开目标游戏目录/EXE。采集时解析器有 7 项状态解析失败，因此原捕获不能提供 Runner 打开失败的精确 NTSTATUS；没有把猜测的状态码写成证据。离线修复了有符号状态值溢出，6 项状态样例通过，未为此重复真实启动。

内核 provider 未按预期限制 PID：共收到 44,569 事件，消费者丢弃 43,979 个非目标 PID 事件，仅保留目标 PID 与 Runner/游戏相关路径，事件丢失计数为 0。没有写全系统 ETL、文件内容或其他进程的命令/环境。不能将这次捕获描述为内核仅采集 Steam PID。工具留在忽略的 `target/steam-etw-diagnostic`，不是产品组件。

## 2026-09-07 历史：9-nine 重测 Ep1 阻塞，其余四部启动失败

用户随后告知已关闭防护，并明确要求重测本机已安装的 9-nine 系列。此处记录该轮测试，不把用户告知的安全软件状态视为已独立核实，也不以改变安全设置作为产品使用步骤。测试代理未恢复隔离项、下载、修复或替换游戏文件。

### 测前基线与存档保护

仅从三个已知 Steam 库读取安装清单，确认已安装 Episode 1（`976390`）、Episode 2（`1033420`）、Episode 3（`1142830`）、Episode 4（`1424660`）及 NewEpisode（`1890120`）。五部游戏共 450 个文件、17,915,335,244 字节，均建立逐文件 SHA-256 基线；另外备份并核对 35 个游戏目录内 `savedata` 文件及 14 个 Steam `userdata/.../remote` 文件。完整游戏目录只计算摘要，没有复制。

每个源文件的只读句柄最终路径均与请求的普通文件路径一致，避免再次把宿主私有文件视图当作 Steam 可见数据。对 Documents、LocalLow、Roaming 的有限目录发现没有找到其他匹配存档位置；这不保证所有可能的存档布局均已覆盖。原始基线和备份始终保留，测试后的结果写入独立证据文件，不覆盖初始快照。账号标识、完整私人路径、存档内容和原始日志均不进入仓库。

### Episode 1：尚未启动

`nine_kokoiro_chs.exe` 仍实际缺失：只读打开返回 `FileNotFoundException` / Win32 错误 2，父游戏目录的句柄路径已确认正常；原始 `nine_kokoiro.exe` 存在，但没有擅自改用该入口。Steam 同时显示云与本地存档冲突，正在等待用户决定保留哪份数据；尚未选择、同步或启动。因此本集仍为阻塞，不能计入通过或运行失败。

### Episode 2：Runner 与普通桌面直接启动的对照

目标为本机已有中文入口 `9-nine-天色天歌天籁音.exe`，使用新的 Windows `job` 配置。先从 Steam 调用稳定 Runner，再恢复空启动选项，从普通资源管理器直接打开同一个 EXE；两次实际启动均未到达标题画面。

| 阶段 | 实际观察 | 判定 |
| --- | --- | --- |
| Steam → Runner → 中文入口 | Manager 已关闭，启动选项通过 Steam 原生属性界面核对；游戏报 `Cannot convert given narrow string to wide string`。确认错误后游戏与 Runner 结束；本次此前不存在的 Runner 日志记录目标退出码 1 | 目标运行失败；不是 Steam 创建 Runner 失败，也不是标题画面通过 |
| 普通资源管理器直接启动 | 14:06:56 打开同一中文 EXE，实际父进程为 `explorer.exe`，无 Manager/Runner；出现相同字符串转换错误，确认后进程退出 | 对照同样失败；当前证据不能把错误归因于 Runner |
| Steam 状态与恢复 | 第一轮结束后启动选项恢复为空，Steam 云显示已是最新；客户端显示 7 分钟 | 仅记录状态；报错期间的显示时长不能代替正常游玩验证 |
| Runner 后中间完整性 | 原 89 个游戏文件、其中 7 个原 `savedata` 文件均与基线 SHA-256 相同；无缺失，仅新增 `savedata/krkr.console.log`，24,434 字节；外部原 3 个 remote 文件不变 | 原程序、资源及既有存档未变化，新增错误日志单独记录 |
| 直接启动后最终完整性 | 原 89 个文件及 7 个原本地存档仍不变、无缺失；只有上述日志增长至 48,866 字节，无其他新增文件；外部原 3 个 remote 文件仍全部不变、无新增或缺失，原始备份完整 | 完整性对照通过；不改变本集启动失败的结论 |

两次错误有界面观察和日志中的对应技术错误行支持。尚未诊断字符串转换失败的具体原因，也未执行原版入口或改变区域/语言设置来扩大对照；不能由此宣称所有中文入口或 KiriKiri 游戏都不兼容。

### Episode 3：相同中文入口的两种启动均失败

目标为 `nine_haruiro_CHS.exe`，同样使用 `job` 配置。实际观察到 Steam → 稳定 Runner → 中文入口；目标创建后在标题前报相同的字符串转换错误，确认错误后游戏与 Runner 结束，本次 Runner 日志记录目标退出码 1。随后恢复空启动选项，14:14:34 从普通资源管理器打开同一 EXE，父进程确认为 `explorer.exe`，无 Manager/Runner；同样报错且未到标题，点击确定后进程退出。

Steam 显示时长从 1 分钟增至 2 分钟、云已是最新，原空启动选项已恢复。这仅记录报错期间的跟踪和最终状态，不算正常游玩通过。两种启动都失败，现有证据不能将字符串错误归因于 Runner；也没有观察到“汉化启动器先退出、另一个真实游戏继续”的成功场景。

Runner 后和直接启动后的两次完整对照中，原 89 个游戏文件、其中 7 个既有本地存档及 3 个外部 remote 存档均与初始 SHA-256 相同，无缺失，原备份完整。唯一新增文件是 `savedata/krkr.console.log`，由 24,450 增至 48,898 字节，无其他新增；源文件最终路径均正常。

### Episode 4：同样未到标题，直接启动复现

目标为 `nine_yukiiro_DL_chs.exe`。从 Steam 经稳定 Runner 创建中文入口后，出现相同的窄字符串转宽字符串错误；点击确定后游戏与 Runner 退出，CIM 确认无剩余，本次 Runner 日志记录目标退出码 1。14:30:09 从普通资源管理器直接打开同一 EXE，无 Manager/Runner，同样报错且未到标题；正常确认错误后进程结束。

原空启动选项已恢复，Steam 云已是最新，显示时长从 1 分钟变为 2 分钟。这仍是目标失败与直接对照复现，不计为正常游玩或 launcher 先退场景通过。

两阶段完整摘要对照均确认原 94 个游戏文件、其中 7 个既有本地存档和 3 个外部 remote 存档不变，无缺失，原始备份完整。相对初始基线只新增 `savedata/krkr.console.log`，从 Runner 后的 24,122 字节增长为直接对照后的 48,242 字节，无其他新增；源句柄最终路径均正常。

### NewEpisode：找不到 startup.tjs 的错误在直接启动中复现

目标为 `nine_new_chs.exe`。Steam → 稳定 Runner → 中文入口实际创建成功，但在标题前报 `Script exception raised` / `Cannot find storage startup.tjs`，与前面三部的字符串转换错误不同。正常确认错误后游戏与 Runner 退出，本次 Runner 日志记录目标退出码 1。14:41:30 从普通资源管理器直接打开同一 EXE，实际父进程为 `explorer.exe`、无 Manager/Runner；出现相同的 `startup.tjs` 错误，仍未到标题，确认后进程全部结束。

原空启动选项已恢复，Steam 云保持开启且显示已是最新，时长显示从 1 分钟增至 2 分钟。没有据报错补放脚本、修复文件或改变目标入口；该错误不证明磁盘上物理缺失同名文件，存储对象加载失败的具体原因尚未诊断，直接启动复现不能支持将其归因于 Runner。

原 84 个游戏文件、其中 7 个既有本地存档及 3 个外部 remote 存档在两阶段对照中均不变、无缺失，原备份完整。唯一新增 `savedata/krkr.console.log`，从 23,866 增至 47,730 字节，无其他新增；源句柄实际路径均正常。

### 四部实际测试的最终汇总

| 游戏 | 原始游戏文件 | 其中本地存档 | 外部 remote 存档 | 新增错误日志最终字节数 | Runner / 直接对照 |
| --- | ---: | ---: | ---: | ---: | --- |
| Episode 2 | 89 | 7 | 3 | 48,866 | 均字符串转换错误，未到标题 |
| Episode 3 | 89 | 7 | 3 | 48,898 | 均字符串转换错误，未到标题 |
| Episode 4 | 94 | 7 | 3 | 48,242 | 均字符串转换错误，未到标题 |
| NewEpisode | 84 | 7 | 3 | 47,730 | 均报找不到 `startup.tjs`，未到标题 |
| 合计 | **356** | **28** | **12** | 4 个日志文件 | **四部均未通过正常启动** |

356 个原始游戏文件共 14,821,596,814 字节，全部与各自初始 SHA-256 一致，无修改或缺失；28 个本地存档是这些文件的子集，12 个 remote 存档位于游戏目录外。四部各新增一个错误日志，最终游戏目录文件总数为 360。28 份本地存档备份重新计算摘要通过；四部 12 个 remote 源文件在最终汇总时再次只读核验，摘要不变、无新增缺失，12 份备份也完整。

每部的游戏目录最终摘要均在其直接启动退出后分别采集，不是四个目录的同一时刻原子快照。四部原启动选项最终均恢复为空，游戏与 Runner 均已退出，Steam 云显示开启且已是最新。最初五部共 450 个文件的基线包含未启动的 Episode 1，不能写成五部都已启动或通过；本轮也未证明真实“launcher 先退、游戏继续”的等待场景。

进程记录采用定期采样，可能漏掉短暂进程，也不是 Job 成员查询。Ep2 旧观察器存在映像路径字段异常，实际链路另有实时 CIM 记录核对；不能把该旧字段当作准确路径证据。四部 Runner 日志中的目标退出码均为 1，与无标题的现场观察一致。

本轮忽略的本机证据根为 `target/real-steam-validation/nine-20260907T054031Z-8615e539097a4cc18efedeb38dd2f0f5`：

- `game-baseline-summary.json`、各 AppID 下的 `game-files-before.json`、`savedata-backup-manifest.json` 及 `external-saves/*-manifest.json`：测前基线和备份校验。
- `976390-chs-readonly-open.json`：缺失中文入口的只读打开结果。
- `1033420-before-play.json`、`1033420-steam-after-runner.json`、`1033420-direct-result.json`：配置、恢复与直接启动观察。
- `1033420/runner-exit-evidence.json`：本次 Runner 退出码、来源边界及筛选后的技术错误行。
- `1033420/after-runner-20260907T060208Z/`、`1033420/after-direct-20260907T060959Z-d4a88db6/`：两阶段完整文件摘要与差异。
- `external-saves/1033420-after-runner.json`、`external-saves/1033420-after-direct.json`：外部存档两阶段对照。
- `1142830/runner-exit-evidence.json`、`1142830/direct-explorer-control.json`、`1142830-direct-result.json`、`1142830-steam-after-runner.json`：Ep3 的进程、错误、对照及恢复记录。
- `1142830/after-runner-20260907T061308Z-f09216ba/`、`1142830/after-direct-20260907T061556Z-164f36c6/` 及 `external-saves/1142830-after-*.json`：Ep3 完整文件与外部存档两阶段对照。
- `1424660/runner-exit-evidence.json`、`1424660/direct-explorer-control.json`：Ep4 的目标退出码与直接启动对照；`1424660/after-runner-20260907T062750Z-2aa9f641/`、`1424660/after-direct-20260907T063138Z-e7dc216c/` 及 `external-saves/1424660-after-*.json`：两阶段完整性。
- `1890120/runner-exit-evidence.json`、`1890120/direct-explorer-control.json`：NewEpisode 的不同错误及直接启动对照；`1890120/after-runner-20260907T063705Z-e6d49a73/`、`1890120/after-direct-20260907T064305Z-46413362/` 及 `external-saves/1890120-after-*.json`：两阶段完整性。
- `four-tested-games-final-integrity-summary.json`、`external-saves/four-games-final-summary.json`：仅四部实际测试的合计、最终外部存档与原备份复核，不包含未启动的 Episode 1。
- `four-episode-process-exit-audit.json`：四部 Runner 日志、观察器结束和最终进程残留检查，保留采样及 Ep2 旧路径字段的限制。
- `final-process-cleanup.json`：最终目标进程列表为空，四个观察器均已请求停止、完成且进程不存在。

## 2026-09-07 历史：其他尚未通过的对象

- `ATRI -My Dear Moments-`：完成只读文件基线与原启动项检查；云未同步，未进入实际启动测试。
- `9-nine-:Episode 1`：初次只读检查发现中文入口被 Windows Defender 隔离；后续重测仍缺失，且有云存档冲突，见上节。

这些对象当时不能计入兼容性通过数量。首个实际运行对象是 Unity galgame；截至 2026-09-07，尚无 KiriKiri、汉化启动器先退或其他真实引擎的通过证据。

## 本机证据位置

本机证据根目录：`target/real-steam-validation/417fe25d10a54f4b83b02893c0e59489`。

- `2873080-before.json`、`2873080-after-direct.json`、`2873080-after-direct-files.json`：游戏完整性。
- `save-backups/`、`save-hash-after-direct.json`：既有存档备份和哈希复查。
- `2873080-direct-start.json`、`2873080-direct-observed-exit.json`、`processes-after-direct.json`：直接 Runner 对照。初始 shell 等待在 UI 正常退出前超时；退出码证据来自 Runner/Steam 日志，不冒充该 shell 的进程句柄返回值。
- `2873080-steam-before.json`、`2873080-steam-restored.json`、`2873080-slash-test-and-restored.json`：启动选项记录、失败对照与最终恢复。
- `target/real-steam-inventory/unity-launch-log-excerpts.json`：限定 AppID 的首次失败日志；后续失败记录保留在本机 Steam 日志与对照结果中。
- `path-view-check-20260907T044426Z/path-view.json`：逻辑路径与句柄最终路径、架构和包身份检查。
- `etw-coordinated-20260907T042510Z-d681b2a3c6364f76a154739dc4e3d086/`：协调器状态和原捕获结果，保留上述解析/过滤限制。
- `2873080-steam-runner-live-chain.json`：成功会话实际进程父子关系。
- `after-steam-runner-success-20260907T045708Z/result.json`、`game-files.json`：成功会话的 Steam 跟踪/退出记录、35 个游戏文件及 4 份原存档最终完整性。
- `final-native-context-validation.json`：原生 UI 状态、启动项恢复、两种 Manager 启动上下文和最终发布检查。
- `target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`：本次位置保护后的跨语言及 Runner 契约。

截至 2026-09-07，已完成一个 Unity galgame 的日常启动验证；当日 9-nine 的四部实际测试及各自的直接启动对照均失败，未增加通过数量。该轮没有证明真实自定义 launcher、干净 Windows 11 安装、更新/卸载及完整原生可访问性矩阵，不能据此宣称达到 [Windows 可用预览门槛](windows-v2-design.md#8-实施顺序与停止条件)。

## 2026-09-08：官方版与汉化版分离目录重测

本节先保留 12:07 前四部通过、第一部原始入口失败的阶段记录；启动结果表和文件表已补入下午恢复 CHS 入口后的结果，详细过程在文末。

用户已将五部第三方汉化版放到独立的非官方游戏目录，并将 Steam 库内版本换回官方版。本轮从当前 Steam 清单重新发现安装位置，分别记录 `<SteamLibrary>\steamapps\common\<game>` 与 `<other-games-root>\<game>`。先完成 Episode 2 的路径配置；恢复测试后，又通过普通资源管理器打开的 Manager 分别保存 Episode 3、Episode 4 和 NewEpisode 的共享配置。四部实际运行文件夹现均指向各自的独立汉化目录，原相对目标 EXE 不变，工作目录和参数留空、等待模式为 `job`、进程名留空，每次界面均确认保存成功及 Runner 就绪。只读的 Steam 安装位置继续关联官方目录，稳定 Runner 和原有 `%command%` 契约不变。Manager 完成保存前的真实配置备份，避免将宿主私有 AppData 视图当作共享配置。四部各自完成 Steam 测试后恢复原空启动选项；Episode 1 未创建配置。本轮修正真实配置路径，未修改产品源码或游戏二进制。

### 新基线与隔离检查

五部的官方、汉化版本合计 10 个安装目录、694 个文件、33,455,828,870 字节（约 33.46 GB），均重新建立 SHA-256 基线。句柄路径与文件身份检查没有发现重解析点、多链接文件或两个版本共用的文件身份。另备份 11 个安装目录内的存档候选文件（含附带存档资源，共 64,745 字节），以及五部共 15 个 Steam remote 文件（10,926 字节）；源句柄检查和备份摘要均通过。未知自定义存档位置不因此被排除。

这是对本轮实际文件建立的保护基线，没有执行 Steam 完整性修复，也不能单凭哈希清单证明所有文件都来自官方发行包。9 月 7 日的基线与错误日志保持原样，未用于判定本轮目录是否损坏。

### 当前启动结果

| 游戏 / AppID | 普通资源管理器直接启动 | 本轮 Steam → Runner | 当前判定 |
| --- | --- | --- | --- |
| Episode 2 / `1033420` | 中文标题、菜单可见，正常退出 | 中文标题、菜单及首句剧情可见；Steam 记录游戏和 Runner 均退出码 0，显示时长 7 → 8 分钟 | **基本启动闭环通过** |
| Episode 3 / `1142830` | 中文标题、菜单可见，正常退出 | 中文标题、菜单及首句剧情可见；游戏和 Runner 均退出码 0，时长 2 → 4 分钟 | **基本启动闭环通过** |
| Episode 4 / `1424660` | 汉化标题及中文退出确认可见，正常退出；顶部菜单仍为日语 | 中文首句剧情可见；游戏和 Runner 均退出码 0，最终刷新时长 2 → 10 分钟 | **基本启动闭环通过**，不代表界面全部汉化 |
| NewEpisode / `1890120` | 用户处理安全提示后到达标题并正常退出；本阶段未进入剧情 | NewGame 后中文首句剧情可见；游戏和 Runner 均退出码 0，时长 2 → 4 分钟 | **基本启动闭环通过**；主菜单英文、顶部菜单日文 |
| Episode 1 / `976390` | 原始 EXE 早先失败；恢复后的 `nine_kokoiro_chs.exe` 中文标题和首句正常，正常退出 | 汉化启动器先退后 Runner 持续等待实际游戏，中文首句和正常退出通过；时长 36 → 38 分钟 | **基本启动闭环及本机启动器先退场景通过**，详见文末 |

Episode 2 的 Steam 会话中，10:41:37 本机时间跟踪到稳定 Runner，10:41:40 跟踪到独立目录中的中文 EXE；10:43:32 Steam 记录两者退出码均为 0。独立进程观察器记录了 Runner 与目标的父子关系，正常退出后没有剩余目标进程。Steam 显示时长增加证明本次会话被计入客户端显示，不是精确运行时长或成就兼容证据。

恢复后的三次 Steam 会话均在 Manager 关闭时进行，实际目标位于独立汉化目录。Episode 3 的游戏与 Runner 在 11:45:43、Episode 4 在 11:59:31、NewEpisode 在 12:04:56 被 Steam 记录为退出码 0；界面确认正常退出，Steam 恢复可启动、云开启且显示最新。Ep4 退出后先显示 9 分钟，稍后刷新为 10 分钟，以最终显示为准。Ep3 观察器有一次元数据查询失败，但保留了正确目标路径、父子关系和退出观察，另有独立 Steam 退出日志；不能把该轮描述为零元数据错误。

四部原始空启动选项均通过 Steam 原生属性界面恢复，后续只读提取指定 AppID 的 localconfig 字段再次确认；没有复制或输出其他账户配置字段。**保存 Manager 配置不等于已持久应用 Steam 启动选项**：本轮结束时常规 Steam 入口仍按空启动选项运行官方版本，日常从 Steam 启动汉化版需应用已验证的稳定 Runner 命令。

NewEpisode 的安全提示与恢复分为两段：10:54 的 SmartScreen 页面导致首次暂停；用户告知自行关闭 SmartScreen 后，恢复尝试在 11:17 出现另一种“打开文件－安全警告”，显示未知发布者、“运行／取消”和“打开此文件前总是询问”。用户随后自行处理该提示，11:20:38 观察到目标进程及汉化组标题窗口；11:22:17 按中文退出确认正常退出，这次直接对照未进入 NewGame，后续 Steam 会话才验证中文剧情。测试代理未操作这些安全提示或改变保护设置。第一只恢复观察器因停止请求与用户操作交错，在目标仍运行时结束；补充观察器重新观察同一进程身份并记录其退出，不能将第一只观察器结束当作游戏退出。

Episode 1 的 11:30 安全提示也是历史检查点：用户处理后，11:36:20 创建 `nine_kokoiro.exe`，出现 `Information` 错误框而未到标题。UIA 乱码按 CP936 字节重新解码为 CP932，可还原为 `プロダクトIDチェック処理の起動に失敗しました`（产品 ID 检查处理启动失败）；这一还原已复现，但不证明底层检查失败的具体原因。点击普通“确定”后，续观察器于 11:37:49 观察到进程退出。此失败发生在普通资源管理器直接路径，没有 Runner，也未尝试修改该检查机制。

### 文件与存档复核

| 游戏 | 官方原文件 | 汉化原文件 | 本轮汉化目录新增文件 | 外部 Steam remote |
| --- | ---: | ---: | --- | --- |
| Episode 2 | 68 个全部未变，无新增或缺失 | 68 个全部未变，无缺失 | `savedata` 下 7 个；后续运行会更新这些本轮新文件 | Steam 测试后 3 个原文件全部未变 |
| Episode 3 | 68 个全部未变，无新增或缺失 | 69 个全部未变，无缺失 | `savedata` 下 7 个 | Steam 测试后 3 个原文件全部未变 |
| Episode 4 | 68 个全部未变，无新增或缺失 | 74 个全部未变，无缺失 | `savedata` 下 7 个 | Steam 测试后 3 个原文件全部未变 |
| NewEpisode | 68 个全部未变，无新增或缺失 | 64 个全部未变，无缺失 | `savedata` 下 7 个 | Steam 测试后 3 个原文件全部未变 |
| Episode 1 | 68 个全部未变，无新增或缺失 | 74 个未变，5 个 `savedata` 文件随游戏运行更新；无缺失 | 按用户要求恢复的 3 个文件，后续哈希不变 | CHS Steam 测试后 3 个原文件全部未变 |

上表复用各部最新完成的完整摘要：Ep2 是 Steam 测试及后续文件夹对照后，Ep3/Ep4/NewEpisode 是各自恢复后的 Steam 会话后，Ep1 是恢复 CHS 入口并完成 Steam 验收后。各部程序、资源和官方文件未变；前四部新增的 `savedata` 及第一部已有的 5 个存档文件由游戏自行更新。第一部另建即时检查点，区分运行前已有差异与此次运行写入。没有清除这些文件、恢复旧进度或反向写回官方目录。

在等待系统提示处理的 11:02 本机时间暂停点，另对五部全部 15 个外部 remote 文件逐部复核，均与本轮初始摘要相同、无新增或缺失，备份完整。同期只读启动选项快照确认 Episode 2、Episode 3、Episode 4、NewEpisode 均为空，Episode 1 没有该字段。这是暂停点的文件状态，不表示未运行的游戏已经通过启动或存档同步测试。

11:02 暂停点汇总复用当时 Episode 2、Episode 3、Episode 4 的最后成功摘要，并补充当时未启动的 Episode 1 和 NewEpisode 前后哈希：全部 694 个原始文件未变，无缺失；当时新增仅为三部的 21 个 `savedata` 文件。六个只读观察器均已完成，该暂停点没有测试游戏、Runner 或观察器进程残留。这份汇总不代表后续恢复测试的文件和进程状态。

恢复前另对 Episode 1、Episode 3、Episode 4、NewEpisode 的两个版本合计 558 个原始文件重新比较，全部未变、无缺失；保留的新增文件仍是先前 Ep3/Ep4 的 14 个 `savedata` 文件。11:14 的五部外部存档快照确认 15 个原文件仍未变，启动选项仍为四部空字符串、Episode 1 无字段。NewEpisode 恢复后的直接启动对照再次确认其 132 个原始文件未变，新增仅为 7 个本地 `savedata` 文件；外部 3 个 remote 文件未变，原备份完整。这些是各阶段独立对照，没有把恢复前后快照覆盖或合并成同一时刻的结果。

12:07 阶段汇总独立保存在 `resumed-final-scope-summary.json`：官方 340 个、汉化 354 个，共 694 个原始文件 SHA-256 均不变，无缺失；当时新增仅为 Ep2/Ep3/Ep4/NewEpisode 各 7 个、合计 28 个本地 `savedata` 文件。12:07 只读核验确认五部 15 个外部 remote 原文件全部不变、无新增或缺失，原备份完整；四部启动选项为空，Ep1 无该字段。各目录摘要按其最后测试阶段采集，不是同一时刻的全盘原子快照；旧汇总保持原样，不代表后续第一部 CHS 验收后的状态。

截至 12:07，当时已有这四份汉化安装的实际 Steam 启动成功证据。它们不能推及所有汉化包，也没有证明自然成就触发、Steam Auto-Cloud 会同步独立目录中的汉化存档、Job 成员关系或“启动器先退出而真实游戏继续”的场景；后一个场景于下午第一部 CHS 验收中补上，见文末。进程采样可能漏掉短暂进程；安全提示的判断依据是实际 Windows 界面，不能只凭采样中没有进程下结论。

本轮本机证据保存在忽略的 `target/real-steam-validation/nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf`，不进入提交或 CI artifact：

- `baseline-summary.json`、各 AppID 的 `*-before.json`、`file-identity.json`：新目录基线、最终路径及文件身份检查。
- `1033420/observation.json`、`1033420/steam-gameprocess-scoped.txt` 与 `observer-ep2-*`：Episode 2 的窗口观察、限定进程日志和正常退出。
- 各已测 AppID 的 `compare-after-folder-summary.json`、Episode 2 的 `compare-after-steam-summary.json`：官方与汉化目录各阶段完整性。
- `external-saves/*-manifest.json`、`1033420-after-steam.json`、`1142830-after-folder.json`、`1424660-after-folder.json`：外部存档备份和阶段核验；`launch-options-ep2-restored.json`：恢复后的精确启动选项。
- `external-saves/*-final-scope.json`、`launch-options-final-scope.json`：11:02 暂停点五部外部存档和启动选项的只读复核。
- `observer-ep3-folder-*`、`observer-ep4-folder-*`、`observer-new-folder-*` 与 `OBSERVATIONS.md`：直接启动及系统提示阻塞的当前观察和限制。
- `final-scope-summary.json`、`final-process-audit.json`：五部原始文件、已知外部存档及当前进程清理的暂停点汇总；不代表后续恢复测试的状态。
- 四部的 `compare-resumed-before-summary.json`、`1890120/compare-resumed-after-folder-summary.json`、`external-saves/*-resumed-before.json` 与 `1890120-resumed-after-folder.json`：恢复前原始文件和外部存档、新章直接启动后的独立对照。
- `1890120/direct-resumed-observation.json`、`observer-new-resumed-folder-*` 与 `OBSERVATIONS.md`：两种 Windows 提示、用户处理、标题语言以及分段观察到正常退出的证据。
- Ep3/Ep4/NewEpisode 的 `steam-resumed-observation.json`、`steam-gameprocess-resumed-scoped.txt`、`compare-resumed-after-steam-summary.json`：各自的中文剧情、Steam 退出码和文件对照；Ep1 的 `direct-resumed-observation.json`：直接启动错误与退出。
- `external-saves/*-final-resumed.json`、`launch-options-final-resumed.json`、`resumed-final-scope-summary.json`：恢复后最终外部存档、原空启动选项和各部最新文件摘要汇总，区别于 11:02 暂停点。

## 2026-09-08：第一部 Defender 隔离记录与文件恢复

本节记录文件恢复阶段，当时尚未运行恢复的入口；后续启动验收见下一节。

用户随后明确要求恢复第一部被 Defender 处理的文件。只读检测记录确认，当日 09:32 已隔离 `nine_kokoiro_chs.exe`，09:33 还处理了随包的 `nine_kokoiro_Patch.exe` 和汉化补丁 `Setup.exe`；旧路径所在盘符与当前汉化目录不同。这些事件早于 10:29 的文件基线，因此“测试期间原文件未变”不证明基线建立时汉化包已完整。该证据确认了缺失入口被 Defender 隔离，尚不能证明它是所有启动问题的唯一原因。

通过有效微软签名的 `MpCmdRun.exe`，使用三个精确原路径和各自的新恢复目录导出文件，三个调用均退出码 0；指定 `-Path` 保留隔离区副本。再按用户要求补回当前独立汉化目录的三个缺失位置，创建新文件、不覆盖已有内容；目的 SHA-256 均与导出副本相同。未向官方目录写入文件，未运行恢复的入口、补丁或安装器。

恢复后的独立全量比较确认：第一部官方与汉化目录合计 147 个原文件全部未变，仅新增上述三个文件，其路径、大小和摘要全部匹配恢复记录；原 `savedata`、存档备份及检查点仍完整。这项结果证明恢复范围和原文件保护，不代表恢复后的游戏已成功启动。

Defender 对这三项的检测标签分别涉及木马或勒索软件。标签不能单独证明有害，恢复成功也不能证明误报。12 KB 汉化入口的静态结构包含原游戏与汉化 DLL 名称，以及进程内存、线程操作 API；没有可信发布者签名或旧同文件基线可用于认证，因此未将它写成安全性检查通过。之前运行的是原始 `nine_kokoiro.exe`，恢复后的 `nine_kokoiro_chs.exe` 尚未重新验收。

本机私有证据位于忽略目录 `target/defender-recovery/ep1-20260908-130532/`，包含限定检测记录、导出结果、三个实际恢复文件的摘要和静态检查结果；恢复文件、日志及本机安全策略工具不进入提交。

## 2026-09-08：恢复后的第一部 CHS 入口与启动器先退验收

用户要求完成剩余验证后，先为当前第一部建立新的 150 文件快照（官方 68、汉化 82），三个恢复文件均匹配恢复摘要。发现 4 个本地 `savedata` 文件在本次启动前的 13:57 已更新；保留当前内容、备份 8 个存档候选并做两次稳定性核对，没有恢复旧进度。初版派生检查把 JSON 时间字符串与 PowerShell 自动转换的 `DateTime` 直接比较，造成误判；按 UTC ticks 正规化后，哈希、长度和修改时间均稳定。原始记录与更正后的独立结果同时保留。

| 检查 | 实际观察 | 判定 |
| --- | --- | --- |
| 文件夹直接启动 | 14:06:56 从普通资源管理器在实际汉化目录双击 `nine_kokoiro_chs.exe`；启动器 PID 3904 创建实际游戏 PID 4160 后先退；到达标题、New Game 后中文首句可见，14:08:31 通过中文确认正常退出 | 直接对照通过 |
| 共享配置 | 从普通资源管理器打开已发布 Manager，添加 AppID `976390`，实际目录设为库外第一部，目标 `nine_kokoiro_chs.exe`，`job` 等待；参数、显式工作目录、进程名均空。保存后显示 Runner 就绪并生成既有稳定路径命令，随后关闭 Manager | 配置通过 |
| Steam 启动 | 14:15:53 点击原 Steam 条目的开始按钮；实际链为 Steam PID 9028 → 稳定 Runner PID 14212 → CHS PID 18876 → 实际游戏 PID 16512，两个游戏入口均位于库外目录 | 启动通过，未同时启动官方 EXE |
| 启动器先退 | CHS 在 14:15:55 已退出；实际游戏与 Runner 继续存在约 141 秒，期间中文首句可见，Steam 显示“停止” | **本机真实启动器先退场景通过** |
| 正常结束 | 通过游戏自身的退出确认，14:18:15 观察实际游戏与 Runner 均结束。Steam 稍后记录 CHS 与 Runner 退出码 0；实际游戏退出码未单独记录 | 正常退出观察通过，不把启动器退出码当实际游戏退出码 |
| Steam 状态 | 运行前云最新、36 分钟；退出后恢复可启动、云最新、38 分钟，云保持开启，未出现冲突 | 状态与显示时长通过，不代表精确时长或汉化存档云同步 |
| 恢复与清理 | Steam 属性中还原空启动项，并由只读配置快照复核；原先无字段，最终为空字符串，语义恢复。五部测试启动项均空，Manager、游戏、Runner 和本轮两个观察器已结束 | 通过；已保存配置不等于日常已应用启动项 |

两次只读进程采样均无快照或元数据错误；100 ms 采样观察到启动器身份及其创建的实际游戏，但没有查询 Job Object 成员。真实共享 `runner-976390.log` 的文件句柄最终路径已核对，记录本次 profile 启动和退出 0。Runner 的 Windows `job` 实现在等待 Job 完成后返回启动器状态，因此此日志同样不能证明实际游戏 PID 16512 的退出码。上述现场结果验证的是本机此启动器场景，不泛化为所有第三方 launcher 的保证。

直接退出后和 Steam 退出后各做一次完整哈希。相对本次 CHS 前检查点、相对直接启动后，两阶段均只有 `savedata/data_anchor.ksd`、`datasc.ksd`、`datasc~.ksd`、`datasu.ksd`、`datasu~.ksd` 五个游戏管理的存档文件更新；没有新增或缺失，全部程序和资源不变，官方 68 个文件及 3 个恢复文件不变。原始、恢复前与本次启动前三批共 24 份小备份全部完整。游戏自然写入保留原样，没有手动存档、读取旧槽位、覆盖进度或再次运行补丁/安装器。外部 Steam remote 原 3 文件仍不变；这不能证明库外汉化存档受 Steam 云覆盖。

第一部主菜单英文、顶部菜单日文，标题、开场文字及退出确认含中文。Steam 成就前后显示 0/4，本次只到首句，没有达到剧情成就条件，不能判定自然成就成功或失败。此运行验收也不提供文件安全性或 Defender 误报鉴定。

证据仍位于上文的 `nine-isolated-20260908T102930-79d125b2936745b0a96c16566dbcebaf` 忽略目录：

- `976390/preflight-before-recovered-chs-20260908T060253Z-validated.json`：测前已有差异、新检查点与稳定性复核。
- `976390/after-recovered-chs-steam-20260908T061902Z-integrity-summary.json`：两个运行阶段完整性及 24 份备份校验。
- `observer-ep1-restored-folder-20260908T060345Z-4df8d474c4a84ae7bea6f88b87712c00/`、`observer-ep1-restored-steam-20260908T061333Z-e1a298368a6e4d59acf37cd096607644/`：进程身份、先退与完成记录。
- `976390/restored-chs-steam-observation.json`、`976390/steam-gameprocess-restored-chs-scoped.txt` 及 `external-saves/` 的新阶段结果：限定日志、外部存档和启动项复核。

本次未修改产品源码，不重复已经通过的跨语言或进程回归全门禁；实际游戏验证和文档审查是本次适用检查。干净系统安装、更新/卸载及其他未实施的 Windows 交付门槛不因这五部通过而自动完成。
