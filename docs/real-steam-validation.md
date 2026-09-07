# Windows 真实 Steam / galgame 验证

日期：2026-09-07。代码基线：`v2`，WinUI 配置预览与独立 Rust Runner。用户明确授权测试本机已安装 galgame，条件是不损坏游戏文件。

**当前结论：《不/存在的你，和我》的 Steam → 稳定 Runner → 游戏 → 正常退出闭环通过，Steam 状态、云同步和显示时长均已核对。** 早先的 OS Error 3 来自开发宿主的 AppData 文件视图重定向；从普通资源管理器运行 Manager、安装到 Steam 可见的稳定位置后，同一条产品命令成功。此结果只覆盖下述游戏和本机环境。

## 测试对象与保护措施

主对象为《不/存在的你，和我》（AppID `2873080`），Windows Unity 游戏，原始目标 `TheNOexistenceNofyouANDme.exe`，位于含空格的 Steam 库路径。系统为 Windows 11 build 26200 x64。

通过 Steam 原生属性界面记录原启动选项为空。游戏目录测试前共 35 个文件、2,770,322,086 字节，建立逐文件 SHA-256 基线。首次检查云状态未同步；使用 Steam 正常重试同步成功、未出现进度冲突后，才备份并校验 4 份既有存档。测试始终保持 Steam 云开启，只进入标题画面并选择“退出游戏”，没有进入继续游戏、读取或新建进度。

真实用户配置、存档备份、完整 Steam 配置及原始日志留在本机忽略的 `target` 目录，不进入提交或 CI artifact。没有修改、替换、修复、卸载任何游戏文件，也没有关闭安全软件。

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

## 未启动的其他对象

- `ATRI -My Dear Moments-`：完成只读文件基线与原启动项检查；云未同步，未进入实际启动测试。
- `9-nine-:Episode 1`：只读检查期间发现自定义中文启动器被 Windows Defender 隔离，系统记录显示处理成功；未执行该文件、未恢复隔离项、未改变安全设置，跳过这款游戏。

这些对象不能计入兼容性通过数量。首个实际运行对象是 Unity galgame；尚无 KiriKiri、汉化启动器先退或其他真实引擎的通过证据。

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

本次已完成一个 Unity galgame 的日常启动验证；仍须补充真实自定义 launcher/其他引擎、干净 Windows 11 安装、更新/卸载及完整原生可访问性矩阵，才达到 [Windows 可用预览门槛](windows-v2-design.md#8-实施顺序与停止条件)。
