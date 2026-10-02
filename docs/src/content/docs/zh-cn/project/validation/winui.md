---
title: "首个 WinUI 配置切片验收"
description: "WinUI 预览实现及带日期的服务、原生界面和发布证据。"
---

:::note[2026-10-02 退役背景]
下文涉及 Dioxus 和 Rust `manager-core` 的内容属于九月的历史记录。它们的源码、工具和界面发布链已于 2026-10-02 移除；WinUI 是唯一 Manager。原始测量和逐场景证据保留其日期及范围，当前实现见[架构](/SteamWrapper/zh-cn/development/architecture/)。
:::

<a id="首个-winui-配置切片验收"></a>

初始记录日期：2026-09-07。分支：`v2`。范围是 Windows 配置预览和既有 Rust Runner 契约，尚未替换 Dioxus 默认发布链。下文后续观察保留各自范围；2026-09-08 扩大的游戏覆盖见[真实 Steam 验收](/SteamWrapper/zh-cn/project/validation/steam/)。

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

后续在用户授权的真实 galgame 上完成了 WinUI 配置、原生 Steam 启动及直接 Runner 对照，并定位早先 OS Error 3 为开发宿主的 AppData 文件视图重定向。普通资源管理器安装后，**同一条启动命令已完成 Steam → Runner → 游戏 → 正常退出闭环**，运行中显示“停止”，退出后可启动、云最新，显示时长 11.2 → 11.4 小时。原启动项已恢复为空，35 个游戏文件与 4 份既有存档的原哈希不变。新增位置保护后重新通过 43 项 C# 测试和跨语言/Runner 契约（`target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`），发布和两种启动上下文的原生复核也通过。详见 [真实 Steam 验证](/SteamWrapper/zh-cn/project/validation/steam/)。

后续发布回归先证明旧脚本保留唯一哨兵文件，再验证全新目录替换不会残留旧依赖。锁文件用例还捕获 `Move-Item` 创建空目标后失败的问题；改为同父目录 `Directory.Move` 后，已验证旧版字节恢复及候选目录保留。证据：`target/winui-component-study/publish-regression-before.log`、`publish-regression-after.log`、`integrated-publish.json`。

## 运行预览

```powershell
mise run winui:sandbox
```

该命令会创建新的示例 Steam 库和用户目录。发布目录是 `target/winui/publish`，必须保留整个目录。授权的真实库验收从普通资源管理器打开 `SteamWrapper.Manager.exe`；开发宿主的 AppData 重定向及检查方式见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。自动化回归使用沙盒。

当前 Manager 直接锁定 `Microsoft.WindowsAppSDK.WinUI` 2.3.6 与 `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6，对应原 Windows App SDK 2.4.0 组件集。位置保护修复后的发布目录为 **171.199 MiB（179,515,507 字节、457 文件）**，包含 .NET/WinUI/Runner，未压缩；这不是安装包下载体积。此前组件精简产物为 179,511,987 字节。

原总包产物为 226.23 MiB（237,216,420 字节、522 文件），[6 轮资源基准](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)测量的是该历史产物。组件精简后没有重测内存和启动时间，也未测量可复现的冷启动时间。发布回归命令为：

```powershell
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
```

## 后续语言支持

2026-09-08 的本地化改动将英语设为默认语言，并加入完整简体中文应用资源。WinUI 提供侧栏语言选择器，与另一套 Manager 共用稳定数据根下的 `ui-settings.json`。`language` 保存 `en-US` 或 `zh-CN`，兼容去除两端空白且不区分大小写的 `en`、`zh-Hans` 别名。缺失或未知语言值回退英语。

语言保存成功后立即更新应用自有静态、动态、状态及服务错误文案，不重新加载表单或丢弃当前输入／协议值。保存失败保留旧语言并报错，不覆盖已有非法 JSON。用户名称、路径、启动命令、日志及操作系统诊断保留原文。最终应用服务套件通过 59/59 项测试，其中包括 10 项新增本地化／偏好测试。嵌套 JSON 重复键用例先失败再修复通过。跨语言／Runner 契约和最终自包含发布也通过，发布目录包含 `zh-CN` 卫星资源。

最终原生界面复核在 Windows 11 build 26200 x64 上使用一次性 Steam／AppData fixture。已验证默认英语、最终发布程序重启后保留中文，以及中文“添加游戏”对话框。语言切换保留未保存的双语名称、路径与参数，已有成功／错误状态、高级 Expander 的可访问名称和已选等待模式显示均双向更新。生成的 Launch Options 控件仍可用，profile 字节完全相同，切换不将表单标记为未保存，正常关闭也不触发未保存提示。应用和窗口均显示新图标。本机记录为 `target/community-i18n-ui/13a3f10fc6164a77886be0d47e7df4aa/native-validation.json`。

原生 Windows 窗口部件和操作系统诊断跟随系统语言。本次隔离复核没有触碰真实 Steam 启动项、profile 或游戏文件，也不证明干净系统安装、真实 Steam 兼容性或完整无障碍矩阵已通过。

## 2026-10-03 封面验收

[PR #10](https://github.com/YangYuS8/SteamWrapper/pull/10)加入本地优先封面、需主动开启的官方 Steam CDN 下载和独立限额缓存。下列结果仅对应封面切片，不替代上文带日期的配置与启动证据。

| 检查 | 结果与边界 |
| --- | --- |
| 本地发现 | 只读扫描为本机 44 款已安装游戏全部找到封面候选，包含 AppID `1091500`、`3548580` 的新版哈希缓存目录。找到候选不代表每张图片均已实际渲染。 |
| Windows 自动化门禁 | 2026-10-02，`a5debf1` 的 [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387662)通过 99 项 Application 测试、9 项真实 Windows 解码测试、C#/Rust 契约、自包含发布和发布回归。用例覆盖默认离线、损坏图片、重定向／下载／解码限制、取消、缓存配额／过期／清理和偏好保留。 |
| 其他 PR 门禁 | [Rust CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387721)在 Windows、Linux 均通过。[双语文档 CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/37006387800)通过，PR 的 Pages 部署按预期跳过。 |
| 恢复后的英语原生复核 | 隔离游戏库实际显示 `1091500`、`3548580` 的本地封面，离线显示 fixture 中的缓存 `480.cover`，并为没有封面的 `9999999` 保留占位图。筛选 Chill with You 后封面仍显示正常。 |
| 简体中文原生复核 | 主窗口、添加游戏对话框、封面设置 Expander、隐私文案、未勾选的主动开启选项和清理提示均显示简体中文，游戏名称保持原文。关闭并重新打开后仍为中文界面。 |
| 设置布局 | 在实际观察的 914 × 714 窗口中，英语和简体中文界面展开封面设置后，游戏列表均缩至 100 像素，控件与提示完整可见。中文折叠检查恢复 310 像素、可见 4 行的列表。此结果不代表完整缩放矩阵。 |
| 原生官方 CDN 主动开启 | 独立 `1091500` fixture 起初没有本地图或缓存：默认关闭时显示占位图，且没有创建封面文件。通过英语界面勾选后保存 `true`，实际下载并显示 54,176 字节的官方竖图。关闭选项保存 `false`；关闭程序、重新启动并再次打开对话框后，选项仍未勾选，缓存竖图继续显示，其 SHA-256 和修改时间保持不变。 |
| 原生缓存清理 | 中文清理移除 fixture 的 `480.cover`，英语清理移除实际下载的 `1091500.cover`，均恢复对应占位图并显示本地化提示。中文检查中的两张本地 Steam 图片仍显示且 SHA-256 不变，两次测试均未写入 profile。 |

原生观察使用一次性 Manager／Steam fixture，未修改真实 Steam 启动项、profile 或游戏文件。未断开操作系统网络、抓包或在原生界面中断正在进行的 HTTP 请求；默认零请求和取消行为由上述服务回归覆盖。P0 的完整界面自动化／无障碍矩阵及干净系统安装器验收仍未完成，见[路线图](/SteamWrapper/zh-cn/project/roadmap/)。

## 尚未完成的验收

最初的 Unity 游戏通过结果，已在 2026-09-08 扩展为五部独立汉化 9-nine，包括本机第一部 CHS 启动器先退的场景。这些观察仅覆盖[真实 Steam 验收](/SteamWrapper/zh-cn/project/validation/steam/)中实际使用的包和场景，不证明所有启动器、引擎或成就兼容。

完整键盘与中文 IME、缩放/高对比度/屏幕阅读器矩阵、干净 Windows 11 VM、安装器、签名、更新与卸载、自动应用/恢复 Steam 启动项尚未完成。当前目标为 Windows 11 24H2（26100）x64，未验证 Windows 10 或 ARM64。

配置编辑支持 Rust 输出的显式 profile 表；内联/点号布局可读取但会拒绝保存。协作写锁和两次字节检查不能消除非协作外部编辑器在最终检查与替换之间的竞态。未知或同版本不同内容的已有 Runner 不会被强制覆盖，需要匹配版本的安装包处理。
