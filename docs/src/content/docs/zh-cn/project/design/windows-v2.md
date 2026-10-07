---
title: "Windows v2 产品与架构重设计"
description: "Windows 产品需求、配置保真、架构与实施阶段。"
---

<a id="windows-v2-产品与架构重设计"></a>

日期：2026-09-08。状态：用户授权实施后，WinUI 配置预览、C# 配置安全服务和跨语言/真实 Runner 契约已落地，实现基线的远程 WinUI CI 通过。[真实 galgame 测试](/SteamWrapper/zh-cn/project/validation/steam/)已完成一个 Unity 游戏及库外独立汉化版 9-nine 五部的 Steam → Runner → 游戏闭环，包含正常退出、Steam 状态和时长更新；五部均验证了中文开场。第一部恢复 CHS 入口后，另验证了本机该启动器先退、实际游戏与 Runner 继续等待的场景；原始入口早先的产品 ID 检查失败记录保留。

早先 OS Error 3 已定位为开发宿主的 AppData 重定向，新增实际文件位置检查。更广泛的启动器兼容性、安装器和干净系统验收尚未完成。本文是 Windows 实施的主方案，取代上一版评估中的 `manager-ffi` 默认路线。

**2026-10-02 实现更新：**WinUI 现为唯一 Manager。按用户要求，已移除 Dioxus 应用、Rust `manager-core`、Dioxus Native E2E 和旧 UI 发布链，历史源码仍可在 `ca6a09e` 查阅。这取代最初的分阶段退役决定，不改写九月的测量结果，也不完成剩余 Windows 验收门槛。主线集成仍是预览，不是稳定发布。当前优先级见[路线图](/SteamWrapper/zh-cn/project/roadmap/)。

<a id="当前验收2026-10-06"></a>

## 当前验收（2026-10-07）

上方九月状态保留为历史记录。首个 Windows 稳定版本现为 **[v0.2.7](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.7)**，提供相同的 [CNB 附件](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.7)，有界核心范围为 **Windows 11 24H2 x64、当前 Windows／Steam 账户**。[运行 37500459000](https://github.com/YangYuS8/SteamWrapper/actions/runs/37500459000) 全部九个 job 通过，发布标签提交 `0987802b86460eff711c6cf694015cdbf086bbb2`。两个来源的全部七附件通过独立匿名长度／摘要、标签提交及第 2 版清单核验。两站稳定与预览更新源均通过项目签名、时效及准确安装器验证，同一频道的两站字节一致。此公开核验没有执行 Setup；未来发布仍须通过准确标签的 CI 和实际交付核验。

发布前记录的源码通过 178 项 Application、37 项 Windows、160 项 Deployment 测试，有一项条件式跨卷跳过，Runner 契约通过。真实隔离 0.2.6 → 0.2.7 安装／回滚／再升级通过 13 个结果。私有便携候选通过十项无 SDK、构建 26100 步骤，包含中文目录配置、Manager 移动及独立 Runner 使用；五项实际 NativeAOT Host 语言用例另行通过。已记录的 16 项双语原生用例、物理拼音输入及活动显示器 DPI 切片建立核心 UI 范围，同时保留对应实际载荷与夹具／客体边界。私有无 SDK 生命周期载荷早于最后 Runner 进程名修复，不是后来公开的 v0.2.7 字节；这些检查也不代表所有账户／硬件组合通过。

真实 CNB 公开 0.2.5 → 0.2.6 手动更新通过全部 12 项原生／安装器步骤：签名更新源、未映射目标 Setup 的准确网络下载、旧 Manager 正常退出、实际 Setup、自动健康重启、配置／偏好／信任状态保持原字节、明确保存配置以安装修正 Runner、独立运行及默认卸载保留。Manager 替换期间保留旧 Runner，没有运行它。另一次明确选择 GitHub 的下载按未改变的产品策略超时，未执行目标安装器，原安装／数据保持不变；其失败记录继续记为失败。两个结果都不覆盖启用启动检查或所有网络。

实际生产安装身份的私有 0.2.7 Setup（SHA-256 `5c9ab6482f67711bc61813563e687cf13c2f10b79f47a1930127502e3b4a6b5f`）在全新离线、构建 26100 客体通过全部 **14 项产品生命周期步骤**，没有 SDK 或预先准备的运行时。当前主 SID 的新 Users／Medium 主令牌没有 Administrators SID 或启用的关键管理员特权。Manager 加载自己的 .NET／XAML 模块、保存配置并安装 Runner；修复、默认卸载、中文目录重装及卸载／移动后的独立 Runner 通过。两次 Manager、三次 Runner 退出均实际观察为 0，临时 WinSta0／Default 安全描述符及原始 544／545／555 组成员关系精确还原。这是真实普通权限产品执行，`freshStandardAccount=false`、`primaryStandardSignInTested=false`、`twoUserGuiTested=false`，不是控制器单独通过。

先前新 SwAcc 跨用户二次登录试验安装 Setup 后，在 WinUI `Application.Start` 发生 `0x8000FFFF`；同 SDK 空控件也在回调前失败。未精确确定原因，失败记录保留。在其他账户的既有桌面上跨用户 RunAs 不属于首个版本的当前账户流程。同 SID 通过不证明其根因、新普通账户主登录或双用户 GUI 使用通过。

实际 NativeAOT 0.2.5 → 0.2.7 复制／恢复在自有 512 MiB 客体 VHD 通过，使用本地重建清单，`actualInno=false`。辅助程序写入安装事务日志及 26,424 字节部分载荷，在剩余 4,096 字节时退出 11；原安装与数据保持不变。只移除自有填充文件后，修复退出 0，VHD 正常分离。先前测试工具失败继续保留。此结果证明该复制中途磁盘满／恢复流程，不代表 Inno 故障、系统盘耗尽或断电恢复通过。

先前微软拼音组合／提交／取消及保留其他字节的保存通过；修正候选窗口在活动显示器以 96／144／192 DPI 实测，宿主还原 125%，28 项放置回归通过。这些观察不证明多屏硬件或后续载荷的所有对话框／语言／缩放组合通过。[测试](/SteamWrapper/zh-cn/development/testing/#当前验收2026-10-06)记录准确产物及保留的失败；[路线图](/SteamWrapper/zh-cn/project/roadmap/)分别记录核心验收、核验后的公开交付与后续扩展。

## 1. 回到最初要解决的问题

**让 Windows 玩家通过 Steam 启动汉化版游戏或自定义启动器，尽可能让 Steam 的游玩状态和时长跟随真实游戏生命周期。配置一次，平时只在 Steam 点击开始。**

需求依据是仓库历史，而非推测未取得的早期对话：

| 仓库材料 | 可确认的需求 |
| --- | --- |
| `f95770b:README.md`（历史 v1 基线） | Windows 小工具，解决汉化版/自定义启动器 galgame 的 Steam 游玩时长问题 |
| `6cb8835:README.md`（首个 v2 设计） | 配置一次；Manager/Runner 分离；Windows first；无需玩家安装 .NET Runtime、默认无需 SteamEdit、不再逐游戏复制完整 wrapper |
| `e244269:docs/architecture.md` | Steam Launch Options 调用独立 Runner；按 AppID 读配置；无注入、客户端修改、DRM 绕过或常驻服务 |
| `c871c21:docs/roadmap.md` | Windows 基础闭环 → Windows 安全一键应用 → Windows 兼容性，Linux/SteamOS 排在后续大版本 |
| `bf8929a:docs/distribution.md` | 普通玩家优先每用户安装器；Runner 放在稳定用户目录；portable 是备选 |

后来的 `d0ae626:docs/roadmap.md` 将 Linux/SteamOS/Proton 提前、一键应用与 Windows 分发延后。这是路线顺序的改变，不能反过来证明跨平台始终是 Windows 首发的前提。技术上先后采用过 C#、Rust、egui、Tauri 和 Dioxus；语言统一不是原始产品需求。

本次将“无需安装 .NET Runtime”解释为**玩家无需手动准备运行环境**。C# 自包含安装包可以满足这一体验目标，但必须在干净系统上验证，不能只看项目属性。支持矩阵先定为受支持的 Windows 11 x64；Windows 10 和 ARM64 暂不承诺。这里是实施取舍，不是声称原始需求禁止其他系统。

## 2. 产品范围与玩家流程

Manager 是一个配置工具。首页以“已配置游戏”和“添加游戏”为核心，不再以完整游戏库浏览器或跨平台发行器的规模牵引首版。

1. 安装并打开 Manager；检查配置和随包 Runner。Runner 暂不可用时仍可查看、编辑配置，相关错误就近说明。
2. 添加游戏：发现本机 Steam 和已安装游戏，支持搜索；自定义 Steam 安装位置可手动选择，部分库不可读时保留其他结果。手动建立 Steam 配置需明确 AppID。
3. 查看只读的 Steam 安装位置，另外选择实际运行文件夹及其中的汉化 exe 或 launcher；实际文件夹可位于 Steam 库外，扫描不得覆盖它。参数、工作目录和等待方式放在“高级设置”，现有值必须完整保留。官方安装、汉化副本、存档与成就的关系见 [目录分离说明](/SteamWrapper/zh-cn/guides/translated-games/)。
4. 候选 `0.2.9` 保存配置并验证稳定 Runner，再预览明确单账号的应用与原值备份；Steam 必须正常退出。保留仅保存和手动复制，手动粘贴须另外保留旧启动项。验收状态见[应用／恢复设计](/SteamWrapper/zh-cn/project/design/steam-launch-options/)。
5. 关闭 Manager，从 Steam 启动并退出游戏；遇到问题可回到该游戏查看本次错误和日志位置。

状态分别表达“配置已保存”“启动项已复制”“磁盘已写入并验证”和“已在 Steam 客户端核验”。不以按钮点击、TOML 保存或 Runner 退出码推断 Steam 时长正确。

WinUI 封面保持本地优先、默认离线：自定义 Steam 图片优先于本地库缓存，并支持带哈希的文件名及嵌套哈希目录。需要明确启用、可随时关闭的偏好，为本地已发现 AppID 的缺失图片提供官方 Steam CDN 回退，限制请求并使用小型 SteamWrapper 缓存。缺失、不可读或不可获取的图片保留友好占位，不影响保存和启动。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)及尚未完成的 [P0 验收门槛](/SteamWrapper/zh-cn/project/roadmap/)。默认跟随已支持的系统语言、回退英语及完整简体中文支持、键盘操作、原生文件选择、缩放及可恢复错误仍属于基本体验。

Manager 初始窗口使用 1160 × 900 有效像素，按真实 XAML 缩放换算，并限制在当前显示器工作区内。尺寸与屏幕位置都限幅；放置前先把相对显示器的工作区偏移换算为屏幕坐标。只在首次加载时执行，不覆盖用户后续调整的尺寸。[微软的工作区定义](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.displayarea.workarea)和[窗口放置坐标](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindow.moveandresize)说明原生接口边界；真实缩放观察记录在[测试](/SteamWrapper/zh-cn/development/testing/)中。

暂不做账号登录、在线游戏资料、通用 mod 管理、多目标切换、常驻托盘、后台更新服务、Linux/SteamOS 新 GUI、Proton 或商店分发。Steam Overlay、成就和所有第三方 launcher 的兼容性不是默认承诺。

## 3. 技术决定

采用 **C# / XAML WinUI 3 Manager + 独立 Rust Runner**。WinUI 是唯一 Manager 实现，其 Windows 配置服务在 C# 内实现，通过已有文件格式与 Runner 配合：

```text
WinUI 3 Manager
  Views / ViewModels
          ↓
  C# 应用服务：配置读改写、Steam 发现、启动项、Runner 安装、日志
          ↓
  %LOCALAPPDATA%\SteamWrapper\profiles.toml
  %LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe

Steam → 既有 Launch Options → Rust Runner → 读取 profile → 启动并等待目标
```

Manager 不需要调用 Runner 的内部函数。TOML、CLI 和稳定路径已经提供了持久边界；再增加 C ABI 会带来 DLL 架构、字符串/缓冲区所有权、错误与 panic 传递、发布版本同步。当前没有同时维护第二种新 GUI 的需求，因此不选 `manager-ffi`。这不意味着配置双语言实现没有成本；下一节的兼容验证是采用本方案的前提。[Microsoft 原生互操作建议](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)

全 C# Runner + NativeAOT 也可行，NativeAOT 可不依赖预装 .NET；但会同时重做 Job Object、挂起启动和进程回归验证。先保留 Rust Runner，避免把 UI 迁移与生命周期重写绑在一起。没有实测前，不以语言推断启动速度、内存或包体。[NativeAOT 官方说明](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

已建立的目录：

```text
apps/manager-winui/
  SteamWrapper.Manager/           # WinUI 窗口、ViewModel、平台接线
  SteamWrapper.Application/       # 可独立测试的配置和文件服务
  SteamWrapper.Application.Tests/
tests/contracts/                 # C# / Rust 共用的脱敏配置与进程 fixture
```

服务保持少量具名操作，文件和扫描工作可取消且不阻塞 UI。不引入通用 RPC、后台 helper、DI 插件平台或多层 transport DTO。C# 的配置模型实现既有协议，不创建第二种配置格式。

`crates/core` 与独立 Rust Runner 保留协议和进程职责；Windows 配置服务位于 C#。原 [Dioxus 应用](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus)、[Rust 管理层](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core)及 [UI 发布工作流](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/.github/workflows/release.yml)仅作历史参考，已于 2026-10-02 移除，不再保留第二套 Manager 或未来退役任务。C#/Rust 文件契约验证仍不可省略。

## 4. 配置保真是第一个门槛

以下契约不变：`profiles.toml` 的 v2 格式、字段和枚举语义；Windows 的 `%LOCALAPPDATA%\SteamWrapper\`；Runner 的 `bin\SteamWrapperRunner.exe`；原 CLI：

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

`ca6a09e` 中历史管理／配置代码的两个行为促成了以下要求。它们不是对当前 C# 配置服务的描述：

- [Manager 保存](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/crates/manager-core/src/lib.rs)当时重建 Profile，重置 `args`、`working_dir`、`wait_mode` 和 `process_name`。改一个目标路径不应丢失这些设置。
- [配置保存](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/crates/core/src/config.rs)当时直接 `fs::write`，没有配置文件原子替换或编辑冲突检测。Runner 二进制安装的原子逻辑不等于 profile 保存安全。

C# 配置服务必须继续满足：

| 范围 | 必须保留或验证的语义 |
| --- | --- |
| 读改写 | 只更新编辑字段；其他 profile、非 Windows 项、未知键保留。库无法安全保留时阻止写入并说明；未知格式版本不降级覆盖 |
| 默认值 | 旧文件省略 `wait_mode` 当前解释为 `root`；仅新建 Windows 配置显式写 `job`。缺省 `args`、`working_dir` 等按当前 Rust 解析器解释 |
| 标识 | profile 表键与 `app_id` 不是同一个字段；保留旧别名键。新 Steam 游戏用明确 AppID，发现歧义时不猜测关联、不重编号 |
| 路径和参数 | 中文、空格、引号、反斜杠、参数数组和相对路径；target/working_dir 以 game_dir 解析，不把参数数组拼成新命令行格式 |
| 写入安全 | 同目录临时文件、落盘、备份与原子替换；失败保留旧文件。防止本应用多写者，检测读取后外部修改并报告冲突；不宣称能锁住所有外部编辑器 |
| 真实消费 | C# 写出的 TOML 由现有 Rust 解析器断言完整语义，再驱动受控 Runner 验证 argv、cwd、等待；Rust 历史 fixture 经 C# 单字段编辑后仍保持未编辑语义 |

最初 TOML 库的选型依据是这个往返试验，而非未经验证的包选择。这仍是回归要求：测试需要覆盖省略值、所有现存 wait mode、别名键、未知字段/版本、写入中断和竞争写入。只比较几份 TOML 文本或“两边都能解析”不够。

## 5. Runner 与 Steam 验收

[当前 Runner](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/main.rs)启动 profile 的 `target` 与 `args`；`steam_command` 被接收并记录，未被执行或自动追加。保留 `%command%` 是兼容契约，**不等于已有原命令转发**。不能借迁移同时启动原 exe、自动回退原游戏或更改参数语义。

Windows 新配置默认 `job`。真实测试需验证 launcher 先退、子进程后退、目标无法启动、中文/空格路径、argv/cwd、Runner 错误退出和日志。`root` 仅等直接子进程；`process_name` 是显式兼容选择，不能证明同名进程属于该游戏。

本机第一部 CHS 场景已通过真实先退验收：14:15:55 启动器退出后，实际游戏和 Runner 继续约 2 分 21 秒，至 14:18:15 普通退出，Steam 时长 36 → 38 分钟。UI 确认使用 `job`，独立进程观察无采样错误或元数据失败，最终无残留。此记录不直接证明 Job 成员，也不扩大为任意启动器保证。当前 [Windows 实现](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/platform/windows.rs)等 Job 完成后返回启动器退出状态；这次日志的 CHS/Runner exit 0 不能解释为实际游戏 exit 0。

Job Object 不能覆盖任意脱离行为：子进程是否入 job 受创建方式、breakaway 和父 job 等条件影响；完成端口的一般通知也不能被笼统当成必达事件。异常场景需查询和验证实际进程状态，不能只根据使用了某个 API 宣称正确。[Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)

常规自动化使用隔离 Steam/用户目录和受控进程。发布验收另外在 Windows 的真实 Steam 上记录：Manager 关闭后启动，游戏期间 Steam 显示运行，退出后状态结束，客户端时长更新情况，以及游戏/launcher/系统版本。代理操作真实库需用户明确授权；本次用户已授权真实 galgame 测试，条件是不损坏游戏文件。测试前记录原启动项、核对文件，测试后恢复原值并复查；不处理未明确解决的存档/云同步冲突。未取得真实记录时只报告 fixture 证明的生命周期行为。

## 6. 安全一键应用与恢复

公开 `v0.2.8` 支持手动复制启动项及清除已识别生成命令。**候选 `v0.2.9` 已实现明确单账号的自动应用与记录原值恢复；真实 Steam 和交付验收仍待完成。**[单账号设计](/SteamWrapper/zh-cn/project/design/steam-launch-options/)定义玩家流程、备份、恢复及交付门槛，不依赖可选的 P3 更新器。验证安全写入及真实客户端保留结果后，才公开交付主要流程。

不能把 Steam 私有本地文件当作稳定的公开写入 API。实施前重新核验实际文件结构，在脱敏 fixture 中验证解析与无关数据保留。流程需做到：

- 明确游戏和 Steam 用户；多用户时由玩家选择，不向所有账号盲写。
- 检测 Steam 是否运行，提示玩家自行退出；写入前再次检查，不自动结束 Steam。
- 在预览中展示原值和新值；备份原启动项、相关文件及恢复所需标识，写入前检查文件是否已改变。
- 只修改目标值，原子写入并复读验证；记录完成/中断状态。无法解析、备份失败或发生冲突则保持原值。
- 恢复时仅在当前值仍是本工具写入值的情况下自动恢复原值；外部新改动需保留并明确提示。不能用整份旧备份覆盖后来修改的其他游戏。

手动复制阶段不能宣称已有可靠原值备份或一键恢复。用户原有启动参数可能有业务意义，不自动丢弃或拼接到新 profile；预览和迁移引导应让玩家明确处理。

## 7. 安装、更新、卸载

**实现基线，2026-10-05：**P1 已提供共享同一应用布局的 **unpackaged 自包含每用户 Inno 安装器与 portable ZIP**，同时携带 .NET 和 Windows App SDK 依赖。普通玩家无需安装开发工具或手动准备运行时；Runner 仍是独立 Rust EXE，不承诺单文件 EXE。安装器已存在，隔离安装／升级测试已通过，干净客户端和更广泛恢复验收仍待完成。这更新了上文九月的实现状态。[官方自包含部署](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

首次安装默认使用 `%LOCALAPPDATA%\Programs\SteamWrapper\`，也可选择经过验证的固定本地盘空目录。升级和修复保留已注册位置；更换位置需先只卸载 Manager 并保留数据，再安装到新位置。开始菜单快捷方式默认开启、桌面快捷方式默认关闭，安装完成后可选择打开 Manager。Manager 单独校验并准备 `%LOCALAPPDATA%\SteamWrapper\bin` 中的稳定 Runner。Runner 占用时保留原二进制、配置和有效启动项，游戏结束后可重试；版本／兼容检查防止随意降级，摘要不同本身不是可升级的证明。

默认卸载只删除 Manager、快捷方式和注册信息。七个独立可选项可移除已识别 Steam 启动选项、下载缓存、日志、偏好、配置、配置备份或经过验证的 Runner 文件。Steam 关闭后，严格标准命令先备份再清空；不推测自定义命令或未知历史值。删除配置／Runner 必须完整扫描账号，确认没有残留 Runner 引用或未解决的还原备份。未知／占用文件、游戏／存档、更新信任状态和 Steam 恢复备份始终保留。冻结 0.2.6 共用清理逻辑通过九项隔离原生选择场景：七项分别单选、还原／配置／Runner 合选及全七项选择。生产 0.2.7 普通权限流程另验证默认保留，不代表全部语言或生产 0.2.7 选择逐项重跑。先前双语取消／缓存／布局检查继续保留各自范围，控件与保护边界见[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)。

每次安装器或便携载荷改变后，都需要绑定实际字节的验证，源码测试本身不足。已通过核心包含无 SDK WDAG 安装／升级／便携、0.2.7 普通权限产品生命周期、真实隔离升级／回滚、默认数据保留、限定清理及注册／快捷方式恢复部分、有界版本保留。自有 VHD NativeAOT 复制中途修复使用本地清单夹具，未执行 Inno；部分结果通过时也保留先前整体失败。完整新账户主登录、双用户 GUI、其他硬件／构建／语言组合及物理断电仍独立评估，宿主夹具、客体产品执行和独立 ISO 证据分别记录。先记录包体／安装体积和启动观察，再优化；MSIX、ARM64、Windows 10 留待后续。

P2 已自动化版本标签的 Setup／便携 ZIP 交付、校验和及完整英语／简体中文说明；公开 `v0.2.6-preview.1` 的相同附件已在 GitHub 与 CNB 核验。P3 自 `0.2.5` 起提供手动检查、可选启动检查、项目签名元数据、有界验证下载，以及确认后交给现有安装器的流程。Windows Authenticode 可选，与必须验证的项目更新签名独立。先前真实隔离 `0.2.4` → `0.2.5` 接力继续保留为历史证据；CNB 公开 0.2.5 → 0.2.6 原生下载至安装流程现已另行通过，GitHub 的真实超时失败及更广自动检查／原生／客户端／恢复门槛仍保留。Manager 更新保留既有稳定 Runner 字节。旧版已知 Runner 需要修正时，Manager 引导明确保存配置以安装随包 Runner；替换 Manager 不会静默替换它，也不证明旧二进制可运行。详见[分发说明](/SteamWrapper/zh-cn/development/distribution/)及[测试](/SteamWrapper/zh-cn/development/testing/)。更新不进入 Runner 日常启动路径，并保留用户数据。

## 8. 实施顺序与停止条件

以下 A–D 阶段保留 2026-09-08 最初验收框架，是要求而非各阶段均已通过的声明；[路线图](/SteamWrapper/zh-cn/project/roadmap/)区分已完成证据与剩余 P0–P4 工作。原 E 阶段退役条件已被 2026-10-02 明确移除的决定取代。

| 阶段 | 完成条件 |
| --- | --- |
| A. 工具链与契约 | 固定 .NET / Windows App SDK / Windows SDK / Rust MSVC；Windows Runner 基线可运行；C#↔Rust 配置保真和受控进程验证通过；无损写入方案可行 |
| B. WinUI 配置切片 | 原生窗口中选择 fixture 游戏/目标、保真保存、安装稳定 Runner、复制精确启动项；取消、缺目录、不可写和占用可恢复；键盘/中文/缩放可用 |
| C. Windows 可用预览 | 真实 Windows/Steam 启动记录；干净 VM 自包含安装、更新、移动 Manager、卸载保留能力通过；文档说明手动恢复与已知兼容范围 |
| D. 安全应用与稳定化 | 多用户、Steam 运行检测、备份、冲突、中断恢复、单游戏撤销均通过；扩大真实 launcher 测试；再考虑正式版默认一键应用 |
| E. 原清理决定（已取代） | 最初设计在 C 通过后才切换默认 Manager／CI 并退役 Dioxus。用户于 2026-10-02 明确要求移除；未完成的交付门槛继续保留。Windows 稳定后再评估新平台范围 |

最初实施顺序从 A→B 配置／受控启动切片和增量 Windows 构建／契约 CI 开始，当时保留旧 UI 工作流的决定现已被取代。当前按 P0 原生 WinUI UI 自动化、更广玩家反馈及明确可选的本地优先封面，P1 安装器／portable 验收，P2 标签发布，P3 可选更新，P4 安全 Steam 写入推进。P0 反馈与 P1 准备可并行，P4 不依赖 P3。配置、生命周期或交付门槛尚未完成时，界面完善或删除旧实现都不证明稳定发布。mise 是可选项；SDK 要求、直接命令与限定范围的验证记录见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。
