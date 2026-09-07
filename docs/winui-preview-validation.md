# 首个 WinUI 配置切片验收

日期：2026-09-07。分支：`v2`。范围是 Windows 配置预览和既有 Rust Runner 契约，尚未替换 Dioxus 默认发布链。

## 已实现

- 原生 WinUI 窗口、已配置游戏列表、添加/中文搜索/手动 AppID、手动 Steam 路径。
- 本地 Steam 库与封面发现、缺失封面占位；没有网络封面请求。
- Windows 原生文件/文件夹选择器、基本字段与高级参数、工作目录、等待模式。
- TOML 局部字段修改、未知文本保留、原子替换与备份、外部修改冲突检测。
- 稳定 Rust Runner 安装、摘要/版本保护、精确启动项生成和剪贴板复制。
- 已复制与已应用状态分开；引导玩家保存 Steam 原启动选项以便恢复。
- mise 构建/测试/发布/沙盒任务，以及新增独立 Windows CI；旧工作流保留。
- Windows App SDK 按需组件引用；全新目录发布、完整性检查和替换失败恢复，避免已移除依赖残留。
- 配置、稳定 Runner 和安装候选的实际文件位置检查；识别开发宿主的 AppData 私有重定向并引导从资源管理器重新打开。

## 实际验证

下表完整原生交互记录对应依赖精简前的预览。组件精简后的最终产物另行完成了沙盒窗口、已有配置读取、原生文件选择器打开/取消、保存和稳定 Runner 就绪复核；没有用旧产物的交互结果替代本次复核。

| 检查 | 结果与边界 |
| --- | --- |
| 重启后工具链 | .NET 10.0.400、Rust 1.98.1、MSVC/SDK 与项目工具可用 |
| `mise run winui:test` | 43 项通过、0 失败、0 跳过；原 34 项配置/服务回归加 9 项实际位置检查，含只重定向 profile、真实原生句柄与合法 junction 升级 |
| `mise run winui:contracts` | 通过；完整历史 TOML/C# 单字段编辑/Rust 比较；真实 Runner 的 argv、cwd、job/root 等待差别、退出码和缺失目标日志 |
| `mise run winui:publish` / `winui:sandbox` | 自包含发布成功，应用 PRI、.NET、WinUI、Runner 和清单齐全；沙盒窗口实际启动 |
| 原生界面 | 隔离示例库扫描、中文搜索、添加游戏、文件选择器打开/取消、选择含中文与空格的 exe、保存和安装稳定 Runner 均完成 |
| 复制 | 点击复制后，剪贴板与稳定 Runner 启动命令逐字一致，包含 `--appid "480" -- %command%` |
| UI 错误保存 | 输入不存在的 exe 后保存被拒绝，旧配置 SHA-256 不变；显示可理解的错误提示 |
| 重新读取 | 未保存修改弹出离开保护；放弃本次错误输入后重新加载，已保存游戏仍在列表中 |
| 远程 CI | 已推送至 `v2`；`3d322db` 的 [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718)通过 C#、跨语言/Runner、发布及 5 项目录回归并上传预览。Server 2025 构建不是 Windows 11 干净系统验收 |
| 组件精简后的发布 | locked restore / Release self-contained publish 通过；保留依赖版本和摘要不变，PRI、WinUI、.NET、picker 投影和 Runner 齐全 |
| `Test-WinUIPublish.ps1` | 5 项通过：旧文件无残留、缺失资源保留旧版、锁住候选时回滚、成功替换仅含新文件、越界拒绝 |
| 精简产物原生复核 | 实际打开中文配置，原生 picker 打开/取消成功；保存后显示成功，生成的命令仍指向沙盒稳定 Runner。证据目录：`target/ui-comparison-5523059ad7ac4b60a91e86f7ee931cee` |
| 实际位置保护原生复核 | 宿主直接启动时显示重定向提示，保存不生成可复制启动项；资源管理器打开新版后正常读取、保存并生成原格式命令，进程父级为 Explorer |

回归过程先观察到缺失行为，再修复：最初 C# 服务抛出未实现异常；Rust 断言捕获未进行的单字段编辑；另修复显式 root、Windows 无效 process_group、沙盒库越界及带括号 VDF 名称问题。实际启动发现缺少 PRI 资源索引，修复 SDK 构建开关后窗口正常加载；发布检查也加入应用 PRI，避免只检查 EXE 的假通过。

契约证据目录：`target/winui-contracts/bec08e11a3bc44bfbe8ce050e82dbd4a/results`。本轮原生测试目录：`target/winui/sandbox/9373d81fc50e4c8f97e1fd3fc17f93ac`。上述配置、契约及沙盒原生测试均使用隔离 `STEAM_DIR`、`LOCALAPPDATA`、`XDG_DATA_HOME`、`STEAMWRAPPER_E2E_ROOT`；未操作真实 Steam 库。

后续在用户授权的真实 galgame 上完成了 WinUI 配置、原生 Steam 启动及直接 Runner 对照，并定位早先 OS Error 3 为开发宿主的 AppData 文件视图重定向。普通资源管理器安装后，**同一条启动命令已完成 Steam → Runner → 游戏 → 正常退出闭环**，运行中显示“停止”，退出后可启动、云最新，显示时长 11.2 → 11.4 小时。原启动项已恢复为空，35 个游戏文件与 4 份既有存档的原哈希不变。新增位置保护后重新通过 43 项 C# 测试和跨语言/Runner 契约（`target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`），发布和两种启动上下文的原生复核也通过。详见 [真实 Steam 验证](real-steam-validation.md)。

后续发布回归先证明旧脚本保留唯一哨兵文件，再验证全新目录替换不会残留旧依赖。锁文件用例还捕获 `Move-Item` 创建空目标后失败的问题；改为同父目录 `Directory.Move` 后，已验证旧版字节恢复及候选目录保留。证据：`target/winui-component-study/publish-regression-before.log`、`publish-regression-after.log`、`integrated-publish.json`。

## 运行预览

```powershell
mise run winui:sandbox
```

该命令会创建新的示例 Steam 库和用户目录。发布目录是 `target/winui/publish`，必须保留整个目录。授权的真实库验收从普通资源管理器打开 `SteamWrapper.Manager.exe`；开发宿主的 AppData 重定向及检查方式见 [Windows 开发环境](windows-development.md)。自动化回归使用沙盒。

当前 Manager 直接锁定 `Microsoft.WindowsAppSDK.WinUI` 2.3.6 与 `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6，对应原 Windows App SDK 2.4.0 组件集。位置保护修复后的发布目录为 **171.199 MiB（179,515,507 字节、457 文件）**，包含 .NET/WinUI/Runner，未压缩；这不是安装包下载体积。此前组件精简产物为 179,511,987 字节。

原总包产物为 226.23 MiB（237,216,420 字节、522 文件），[6 轮资源基准](windows-manager-comparison.md)测量的是该历史产物。组件精简后没有重测内存和启动时间，也未测量可复现的冷启动时间。发布回归命令为：

```powershell
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
```

## 尚未完成的验收

真实 Steam→Runner 链路已在一个 Unity galgame 上通过，尚无真实汉化 launcher 先退、KiriKiri 等其他引擎的通过证据。完整键盘与中文 IME、缩放/高对比度/屏幕阅读器矩阵、干净 Windows 11 VM、安装器、签名、更新与卸载、自动应用/恢复 Steam 启动项尚未完成。当前目标为 Windows 11 24H2（26100）x64，未验证 Windows 10 或 ARM64。

配置编辑支持 Rust 输出的显式 profile 表；内联/点号布局可读取但会拒绝保存。协作写锁和两次字节检查不能消除非协作外部编辑器在最终检查与替换之间的竞态。未知或同版本不同内容的已有 Runner 不会被强制覆盖，需要匹配版本的安装包处理。
