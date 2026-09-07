# Windows 真实 Steam / galgame 验证

日期：2026-09-07。代码基线：`v2`，WinUI 配置预览与独立 Rust Runner。用户明确授权测试本机已安装 galgame，条件是不损坏游戏文件。

**当前结论：WinUI 配置流程、游戏原生 Steam 启动、直接 Runner 启动通过；Steam 从启动选项创建 Runner 失败，完整日常启动闭环尚未通过。** 不能用受控进程测试或 CI 成功替代这项结果。

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
| Steam 启动 Runner | 下表四次单变量尝试均在 `CreatingProcess` 阶段报 `OS Error 3`，没有创建 Runner，也没有新增该次 Runner 日志 | **失败，阻塞完整闭环** |
| 恢复与完整性 | 最终启动选项恢复为空；云仍开启且已同步。直接 Runner 结束后复查全部 35 个游戏文件与 4 份既有存档，大小与 SHA-256 均与基线相同，无游戏文件新增/缺失 | 通过；Unity 正常生成的日志/缓存不等于存档修改 |

Steam 创建 Runner 的对照保持稳定 Runner 文件与目标配置不变，未据此修改产品命令格式：

| 本机时间 | 启动选项变化 | 结果 |
| --- | --- | --- |
| 11:25 | 原生成格式：`"<stable-runner-path>" --appid "2873080" -- %command%` | OS Error 3 |
| 11:37 | 仅移除无空格 Runner 路径的引号 | OS Error 3 |
| 11:42 | 仅移除数字 AppID 的引号 | OS Error 3 |
| 12:03 | 仅将 Runner 路径改为正斜杠 | OS Error 3 |

现有日志中的展开命令与实际文件路径一致；路径和父目录存在，稳定 Runner 与随包 Runner 摘要一致，`--help` 及直接启动成功。Steam 原生启动也成功。由此可将观察到的失败限定在 Steam 创建包装进程这一环，但**尚未确定哪个路径或工作目录解析失败**，不能归因于 WinUI、.NET 或 Runner 的 Job 等待实现。

## 未启动的其他对象

- `ATRI -My Dear Moments-`：完成只读文件基线与原启动项检查；云未同步，未进入实际启动测试。
- `9-nine-:Episode 1`：只读检查期间发现自定义中文启动器被 Windows Defender 隔离，系统记录显示处理成功；未执行该文件、未恢复隔离项、未改变安全设置，跳过这款游戏。

这些对象不能计入兼容性通过数量。首个实际运行对象是 Unity galgame；尚无 KiriKiri、汉化启动器先退或其他真实引擎的通过证据。

## 下一项诊断与证据位置

下一步是记录一次 Steam 创建包装进程时实际访问的相关路径，再决定是否修改启动项生成或启动流程。已准备本机独立的窄 ETW 工具：限 Steam PID、文件创建/结束事件、30 秒、Runner/目标游戏路径，不写全系统 ETL。编译和预检通过；当前 token 没有运行该跟踪所需权限，**跟踪未执行，根因未确认**。工具位于 `target/steam-etw-diagnostic`，不是产品组件。

本机证据根目录：`target/real-steam-validation/417fe25d10a54f4b83b02893c0e59489`。

- `2873080-before.json`、`2873080-after-direct.json`、`2873080-after-direct-files.json`：游戏完整性。
- `save-backups/`、`save-hash-after-direct.json`：既有存档备份和哈希复查。
- `2873080-direct-start.json`、`2873080-direct-observed-exit.json`、`processes-after-direct.json`：直接 Runner 对照。初始 shell 等待在 UI 正常退出前超时；退出码证据来自 Runner/Steam 日志，不冒充该 shell 的进程句柄返回值。
- `2873080-steam-before.json`、`2873080-steam-restored.json`、`2873080-slash-test-and-restored.json`：启动选项记录、失败对照与最终恢复。
- `target/real-steam-inventory/unity-launch-log-excerpts.json`：限定 AppID 的首次失败日志；后续失败记录保留在本机 Steam 日志与对照结果中。

这项阻塞解决并完成 Steam 状态/时长验证后，仍须完成干净 Windows 11 安装、更新/卸载及完整原生可访问性矩阵，才达到 [Windows 可用预览门槛](windows-v2-design.md#8-实施顺序与停止条件)。
