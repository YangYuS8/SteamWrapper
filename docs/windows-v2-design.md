# Windows v2 产品与架构重设计

日期：2026-09-07。状态：用户授权实施后，WinUI 配置预览、C# 配置安全服务和跨语言/真实 Runner 契约已落地，远程 WinUI CI 通过。[真实 galgame 测试](real-steam-validation.md)已完成一个 Unity 游戏的 Steam → Runner → 游戏闭环，包含正常退出、Steam 状态和时长更新；早先 OS Error 3 已定位为开发宿主的 AppData 重定向，新增实际文件位置检查。真实自定义 launcher、安装器和干净系统验收尚未完成。本文是 Windows 实施的主方案，取代上一版评估中的 `manager-ffi` 默认路线；Dioxus 代码和 CI 仍保留为迁移基线。

## 1. 回到最初要解决的问题

**让 Windows 玩家通过 Steam 启动汉化版游戏或自定义启动器，尽可能让 Steam 的游玩状态和时长跟随真实游戏生命周期。配置一次，平时只在 Steam 点击开始。**

需求依据是仓库历史，而非推测未取得的早期对话：

| 仓库材料 | 可确认的需求 |
| --- | --- |
| `f95770b:README.md`（当前旧版 main） | Windows 小工具，解决汉化版/自定义启动器 galgame 的 Steam 游玩时长问题 |
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
3. 选择汉化 exe 或 launcher，填写必要名称与路径。参数、工作目录和等待方式放在“高级设置”，现有值必须完整保留。
4. 保存配置，确认稳定 Runner 可用后生成精确启动项；在 Steam 属性中粘贴。引导玩家先保留原启动项，说明恢复步骤。复制成功只表示已复制。
5. 关闭 Manager，从 Steam 启动并退出游戏；遇到问题可回到该游戏查看本次错误和日志位置。

状态分别表达“配置已保存”“启动项已复制”“已应用到 Steam”（后续写入并验证后才可显示）和“已人工验证启动”。不以按钮点击、TOML 保存或 Runner 退出码推断 Steam 时长正确。

首版只读取本地封面，缺失时使用友好占位；封面不影响保存和启动。现有 Dioxus 的 Steam CDN 回退暂不改代码，WinUI 首版不继承该网络请求。中文、键盘操作、原生文件选择、缩放及可恢复错误属于基本体验。

暂不做账号登录、在线游戏资料、通用 mod 管理、多目标切换、常驻托盘、后台更新服务、Linux/SteamOS 新 GUI、Proton 或商店分发。Steam Overlay、成就和所有第三方 launcher 的兼容性不是默认承诺。

## 3. 技术决定

采用 **C# / XAML WinUI 3 Manager + 独立 Rust Runner**。Manager 的 Windows 配置服务在 C# 内实现，通过已有文件格式与 Runner 配合：

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

迁移期间 `crates/core` 继续为 Rust Runner/Dioxus 提供现有功能，`crates/manager-core` 仅维护现有 Dioxus 管理链。WinUI 新功能在 C# 一处实现。WinUI 达到替换门槛后再按实际调用关系退役 Dioxus、旧管理层和构建链，不在设计阶段先删除代码。

## 4. 配置保真是第一个门槛

以下契约不变：`profiles.toml` 的 v2 格式、字段和枚举语义；Windows 的 `%LOCALAPPDATA%\SteamWrapper\`；Runner 的 `bin\SteamWrapperRunner.exe`；原 CLI：

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

当前源码揭示了两个需要修正、不能直接移植的行为：

- [Manager 保存](../crates/manager-core/src/lib.rs)重建 Profile，会重置 `args`、`working_dir`、`wait_mode` 和 `process_name`。改一个目标路径不应丢失这些设置。
- [配置保存](../crates/core/src/config.rs)直接 `fs::write`，没有配置文件原子替换或编辑冲突检测。Runner 二进制安装的原子逻辑不等于 profile 保存安全。

新的配置服务必须满足：

| 范围 | 必须保留或验证的语义 |
| --- | --- |
| 读改写 | 只更新编辑字段；其他 profile、非 Windows 项、未知键保留。库无法安全保留时阻止写入并说明；未知格式版本不降级覆盖 |
| 默认值 | 旧文件省略 `wait_mode` 当前解释为 `root`；仅新建 Windows 配置显式写 `job`。缺省 `args`、`working_dir` 等按当前 Rust 解析器解释 |
| 标识 | profile 表键与 `app_id` 不是同一个字段；保留旧别名键。新 Steam 游戏用明确 AppID，发现歧义时不猜测关联、不重编号 |
| 路径和参数 | 中文、空格、引号、反斜杠、参数数组和相对路径；target/working_dir 以 game_dir 解析，不把参数数组拼成新命令行格式 |
| 写入安全 | 同目录临时文件、落盘、备份与原子替换；失败保留旧文件。防止本应用多写者，检测读取后外部修改并报告冲突；不宣称能锁住所有外部编辑器 |
| 真实消费 | C# 写出的 TOML 由现有 Rust 解析器断言完整语义，再驱动受控 Runner 验证 argv、cwd、等待；Rust 历史 fixture 经 C# 单字段编辑后仍保持未编辑语义 |

TOML 库选型以这个往返试验决定，不先锁定未经验证的包。测试需要覆盖省略值、所有现存 wait mode、别名键、未知字段/版本、写入中断和竞争写入。只比较几份 TOML 文本或“两边都能解析”不够。

## 5. Runner 与 Steam 验收

[当前 Runner](../crates/runner/src/main.rs)启动 profile 的 `target` 与 `args`；`steam_command` 被接收并记录，未被执行或自动追加。保留 `%command%` 是兼容契约，**不等于已有原命令转发**。不能借迁移同时启动原 exe、自动回退原游戏或更改参数语义。

Windows 新配置默认 `job`。真实测试需验证 launcher 先退、子进程后退、目标无法启动、中文/空格路径、argv/cwd、Runner 错误退出和日志。`root` 仅等直接子进程；`process_name` 是显式兼容选择，不能证明同名进程属于该游戏。

Job Object 不能覆盖任意脱离行为：子进程是否入 job 受创建方式、breakaway 和父 job 等条件影响；完成端口的一般通知也不能被笼统当成必达事件。异常场景需查询和验证实际进程状态，不能只根据使用了某个 API 宣称正确。[Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)

常规自动化使用隔离 Steam/用户目录和受控进程。发布验收另外在 Windows 的真实 Steam 上记录：Manager 关闭后启动，游戏期间 Steam 显示运行，退出后状态结束，客户端时长更新情况，以及游戏/launcher/系统版本。代理操作真实库需用户明确授权；本次用户已授权真实 galgame 测试，条件是不损坏游戏文件。测试前记录原启动项、核对文件，测试后恢复原值并复查；不处理未明确解决的存档/云同步冲突。未取得真实记录时只报告 fixture 证明的生命周期行为。

## 6. 安全一键应用与恢复

Windows 首个预览闭环允许手动复制启动项；**一键应用/恢复紧随其后，优先于跨平台扩展**。先实现可靠预览，再考虑作为正式版默认流程。

不能把 Steam 私有本地文件当作稳定的公开写入 API。实施前重新核验实际文件结构，在脱敏 fixture 中验证解析与无关数据保留。流程需做到：

- 明确游戏和 Steam 用户；多用户时由玩家选择，不向所有账号盲写。
- 检测 Steam 是否运行，提示玩家自行退出；写入前再次检查，不自动结束 Steam。
- 在预览中展示原值和新值；备份原启动项、相关文件及恢复所需标识，写入前检查文件是否已改变。
- 只修改目标值，原子写入并复读验证；记录完成/中断状态。无法解析、备份失败或发生冲突则保持原值。
- 恢复时仅在当前值仍是本工具写入值的情况下自动恢复原值；外部新改动需保留并明确提示。不能用整份旧备份覆盖后来修改的其他游戏。

手动复制阶段不能宣称已有可靠原值备份或一键恢复。用户原有启动参数可能有业务意义，不自动丢弃或拼接到新 profile；预览和迁移引导应让玩家明确处理。

## 7. 安装、更新、卸载

首个目标是 **unpackaged 自包含目录 + 每用户安装器**，同时携带 .NET 和 Windows App SDK 依赖。普通玩家无需安装开发工具或运行时；Runner 仍是独立 Rust EXE。portable 后续复用同一目录结构，不承诺单文件 EXE。[官方自包含部署](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

应用文件建议安装至 `%LOCALAPPDATA%\Programs\SteamWrapper\`，随包 Runner 经校验安装至稳定 `bin`。首次配置时确保安装成功；普通 UI 打开不应因安装失败而完全不可用。Runner 被占用时保留原文件、配置和有效启动项，游戏结束后可重试。更新不得让旧 Manager 随意把已安装 Runner 降级，需在发布版本元数据与兼容策略中明确处理；摘要不同本身不是可升级的证明。

卸载 Manager 默认保留 profile、日志、备份和稳定 Runner，使仍指向它的启动项继续有效。完整移除 Runner 必须先处理已接管的 Steam 启动项；手动粘贴或无法枚举的引用无法证明已解除时，保留 Runner 并提供清理说明。不能把“保留配置”误当成删除 Runner 也安全。

每个候选安装器必须在无开发环境的 Windows 11 x64 VM 中验证安装、配置、关闭 Manager 后启动、覆盖更新和卸载。记录包体、冷启动和空闲内存后再优化；MSIX、自动更新、ARM64 和 Windows 10 单独评估。

## 8. 实施顺序与停止条件

| 阶段 | 完成条件 |
| --- | --- |
| A. 工具链与契约 | 固定 .NET / Windows App SDK / Windows SDK / Rust MSVC；Windows Runner 基线可运行；C#↔Rust 配置保真和受控进程验证通过；无损写入方案可行 |
| B. WinUI 配置切片 | 原生窗口中选择 fixture 游戏/目标、保真保存、安装稳定 Runner、复制精确启动项；取消、缺目录、不可写和占用可恢复；键盘/中文/缩放可用 |
| C. Windows 可用预览 | 真实 Windows/Steam 启动记录；干净 VM 自包含安装、更新、移动 Manager、卸载保留能力通过；文档说明手动恢复与已知兼容范围 |
| D. 安全应用与稳定化 | 多用户、Steam 运行检测、备份、冲突、中断恢复、单游戏撤销均通过；扩大真实 launcher 测试；再考虑正式版默认一键应用 |
| E. 清理与后续 | C 通过后才切换默认 Manager 和替换 CI，随后按依赖退役 Dioxus 管理链；D 稳定后再评估跨平台等新范围 |

首个实现任务聚焦 A→B 的完整配置与受控启动切片，并增量建立 Windows 构建/契约 CI，保留现有工作流；C 后才切换默认发布链。工具链未就绪、配置无法无损往返或 Runner 生命周期回归未解决时，不以精美界面作为迁移完成证据。工具链已通过 mise 开始落地，最新安装与验证记录见 [Windows 开发环境](windows-development.md)。
