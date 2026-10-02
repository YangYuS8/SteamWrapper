---
title: "测试"
description: "选择相关的服务、原生界面、Runner、包体和 Steam 验证门禁。"
---

<a id="测试"></a>

SteamWrapper 分别验证跨 Windows/Linux 的 Rust core 与独立 Runner，以及 WinUI Manager 的 C# 服务、跨语言契约和自包含发布。Dioxus、其 Rust 管理服务、Native E2E 与旧打包流程已退役。Windows 最终交付仍按 [阶段门槛](/SteamWrapper/zh-cn/project/design/windows-v2/#8-实施顺序与停止条件)验收。

[Manager 实测比较](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)是选型的归档证据；[测量脚本](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/scripts/windows/Measure-ManagerComparison.ps1)与 Dioxus 源码固定在提交 `ca6a09e`，不再是当前开发前置条件。

## 按改动选择验证

先读取受影响代码和测试，选择能证明本次结果的检查。无需每次编辑前运行整个 workspace，也无需为文档或纯样式调整新增匹配源码字符串的测试。

| 本次改动 | 本地验证范围 |
| --- | --- |
| 文档 / AGENTS / 技能 | 审核 diff、链接和指令冲突；文档/站点变更运行 `pnpm docs:check` 与 `pnpm docs:build` |
| Rust core 行为 | 先写能复现缺失行为的测试并观察预期失败，再修改实现；运行受影响 crate 测试；共享契约或跨 crate 影响时运行 workspace 检查和测试 |
| Runner 启动 / 等待 | 对应平台的真实进程回归测试；CLI / TOML / 公共模块变化再扩展到 workspace |
| WinUI / C# 服务 | `Invoke-WinUI.ps1 -Action Test`；配置协议或 Runner 分发变化增加 `Test-WinUIContracts.ps1`；UI 变化使用 `Invoke-WinUI.ps1 -Action Publish` 与隔离原生交互（完整命令见下文） |
| 纯视觉调整 | 构建并在隔离 Desktop 预览中检查受影响界面；按影响选择现有测试，不用固定 CSS 字符串代替视觉验收 |
| 发布 / 工具链或共享构建变化 | 相关 Rust/WinUI 门禁、当前 Windows Runner staging、完整发布目录与 `Test-WinUIPublish.ps1`；安装器另行验收 |

CI 工作流仍执行各自完整门禁。上表限定日常本地工作量，不删减 CI。已通过的检查只在新改动、失败或未解决疑点出现时重跑；缺少工具时记录阻塞，不把未运行写成通过。

行为回归优先验证外部结果。服务或源码声明测试不能证明原生窗口、可访问性、布局或文件选择行为。WinUI 自动化原生 UI 门禁尚未实现，见 [路线图](/SteamWrapper/zh-cn/project/roadmap/)；隔离的人工原生验收须单独记录。

<a id="winui-迁移的新增验收"></a>

## WinUI 验收

先验证 C# 配置服务与 Rust Runner 的既有文件协议，再证明 UI 和安装器。已有入口：

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test
pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

`Test` 动作包含配置保真/冲突/替换失败、本地 Steam、稳定 Runner 安装与共享文件位置测试。`Test-WinUIContracts.ps1` 从共享历史 fixture 开始，C# 单字段修改后由 Rust 比较完整 TOML 和 Profile；再用受控父子进程验证 C# 新配置的精确 argv、cwd、job/root 等待差别、退出码和错误日志。详情见 [契约说明](https://github.com/YangYuS8/SteamWrapper/blob/main/tests/contracts/README.md)。测试驱动、fixture 及生成的用户目录都不进入发布目录。

目录分离新增 AppID 关联、库外运行路径保留和真实双库安装冲突回归，该实现轮 C# 共 49/49 通过。原生隔离保存、重新扫描和歧义新建配置也已验证；详见 [目录分离验证记录](/SteamWrapper/zh-cn/guides/translated-games/)。这些隔离结果本身不代表真实汉化迁移或成就触发通过。

后续默认英语/完整简体中文实现通过 59/59 项 C# 测试，其中新增 10 项本地化/偏好测试。两条默认英语测试先在旧服务中文消息上失败；UTF-8 BOM 偏好读取和嵌套 JSON 重复键拒绝也先失败再修复。测试覆盖英文与中文资源键和格式参数一致、已存在嵌套状态/错误切换、诊断和用户值不变、双语扫描/Runner 消息、规范语言持久化、未知字段与 profiles 保留、损坏/重复/过大 JSON 拒绝及 BOM 兼容。跨语言／Runner 契约和最终自包含发布通过。[后续语言验收](/SteamWrapper/zh-cn/project/validation/winui/#后续语言支持)记录隔离的原生切换、重启保持、输入／profile 字节保留和图标检查；这些不是干净系统或真实 Steam 证据。

原生本地化验收应使用没有 `ui-settings.json` 的全新隔离数据根，确认无论 Windows 显示语言如何，首次启动均为英语。打开配置编辑、添加参数并触发验证/状态消息，切换到简体中文再切回英语；检查应用自有标签、参数行、等待模式、既有状态、对话框和 picker 动作按钮文案同步变化，未保存的名称、路径、参数及已生成启动项保持不变。重开沙盒 Manager 检查持久化，并检查两种语言的换行、截断、键盘操作和对话框布局；检查发布目录的 `zh-CN/SteamWrapper.Application.resources.dll`。服务/资源测试不能替代原生呈现或发布完整性验证。

WinUI Manager 使用与 `profiles.toml` 同级的 `ui-settings.json`，`language` 为 `en-US` / `zh-CN`；兼容 `en` / `zh-Hans`，去除首尾空白且不区分大小写。缺失或未知语言默认英语。保存成功后刷新界面而不重载正在编辑的配置；失败保留旧语言并报告错误，损坏的设置文件原样保留。系统 picker 自有文案和外部原始诊断保持原语言。测试必须使用一次性设置目录，不修改真实 AppData 或 Steam 配置。

当前 Windows CI 运行 C# 测试、跨语言 Runner 契约和发布检查。历史提交 `3d322db` 的 [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718)已通过；这是有日期的记录，不代表最新提交。托管 Windows Server 2025 构建不是 Windows 11 干净系统或原生 UI 验收。完整验收范围如下；本机 Unity 游戏及 9-nine 五部独立汉化版已另行通过 Steam 闭环，第一部另覆盖 CHS 启动器先退场景，过程与边界见 [真实 Steam 验证](/SteamWrapper/zh-cn/project/validation/steam/)。

| 范围 | 有效证据 |
| --- | --- |
| TOML 兼容 | C# 读取 Rust fixture、只改一个字段、保存后由 Rust 断言未编辑语义；包括省略 wait_mode=root、新建 job、别名键、未知字段/版本和所有现存枚举 |
| 保存安全 | 原子替换失败、备份失败、多写者/外部修改冲突、中断与旧文件保留；不以序列化成功代替无损保存 |
| 配置到运行 | C# 保存的配置驱动真实 Rust Runner fixture，断言 argv、cwd、launcher/child 等待与错误；不能只比较 TOML 文本 |
| 共享数据位置 | 核验现存 Runner/profile 与安装候选的句柄最终路径；重定向返回非就绪，候选失败保留旧文件，真实 junction 和合法路径形式仍可用 |
| WinUI 操作 | 真实原生窗口、原生 picker、取消、中文输入、键盘、缩放及错误恢复；旧 Dioxus DOM/RSX 断言不适用 |
| Windows 发布 | 干净 Windows 11 x64 VM 上自包含安装、稳定 Runner、覆盖更新/占用/降级保护、移动 Manager、卸载后既有启动项仍可用 |
| Steam apply/restore | 脱敏多用户 VDF fixture、Steam 运行保护、备份/复读、冲突和中断恢复、保留其他设置；私有格式需先核验 |
| 最终游玩体验 | 测试者在真实 Steam 人工记录运行状态、退出和时长更新；注明游戏、launcher、系统版本，不能由 fixture 结果替代 |

常规自动化使用隔离 Steam/用户数据。真实 Steam 验收须有用户明确授权；本次用户已授权不损坏游戏文件的 galgame 测试。原启动项、文件完整性与存档保护需单独记录，未解决的云同步冲突不能由测试流程自动选择覆盖。真实用户数据、完整 Steam 配置和本机测试备份不进入提交或 CI 产物。具体配置边界见 [主方案](/SteamWrapper/zh-cn/project/design/windows-v2/#4-配置保真是第一个门槛)。

真实验收中的 Manager 应从正常 Windows 资源管理器打开完整发布目录中的 `SteamWrapper.Manager.exe`，完成配置与稳定 Runner 安装后关闭，再由 Steam 启动游戏。本机 Codex 进程环境曾把字面上的 AppData 路径映射到包的 `LocalCache`；shell 或 Manager 没有 package identity，并不能排除此重定向。最终文件句柄路径才揭示两种视图不同。具体步骤见 [共享数据路径与真实 Steam 验收](/SteamWrapper/zh-cn/development/windows/#共享数据路径与真实-steam-验收)，常规自动化继续使用隔离沙盒，mise 别名是可选项。

2026-09-07 的实际记录：`The NOexistenceN of you AND me`（AppID 2873080）在 12:46:03 形成 `Steam 4268 → Runner 4624 → 游戏 19752 → Unity 12996`，从标题界面正常退出后，Steam 在 12:53:33 记录三个子进程全部 exit 0；UI 回到“开始”、云显示最新，显示时长 11.2 → 11.4 小时，启动项已恢复为空。正常 Explorer 启动同一 Manager、在真实稳定目录配置安装后，原命令格式即成功，无需改动引号或斜杠规则。最终独立核对确认 35/35 个游戏文件及 4/4 份原存档 SHA-256 与初始基线一致，存档句柄路径未被重定向。此结果限于本机该款游戏，不扩大为其他游戏、干净 VM 或安装器通过。

2026-09-08 较早的隔离目录实测：9-nine 第二、三、四部和新章分别从 Steam 经稳定 Runner 运行库外汉化版，均确认中文开场、正常退出、Steam 运行状态和显示时长更新。第一部当时从现有原始入口启动即报产品 ID 检查处理启动失败，未到标题，也未开展 Steam 路径验收。该阶段失败记录保留，后续恢复 CHS 入口后的结果独立记录。

第一部恢复后，14:06:56–14:08:31 普通文件夹直启和 14:15:53–14:18:15 Steam → Runner → CHS → 游戏均通过中文开场与普通退出；CHS 先退出后，游戏与 Runner 仍继续约 2 分 21 秒。UI 确认 `job`，独立观察零采样错误、零元数据失败和最终无残留，完成本机该 CHS 场景的真实 launcher 先退门槛。日志只记录 CHS 和 Runner 的 exit 0；[当前 job 实现](https://github.com/YangYuS8/SteamWrapper/blob/main/crates/runner/src/platform/windows.rs)返回启动器状态，实际游戏退出码未知，不能由 UI 或进程父子关系证明 Job 成员。

本次官方 68 文件、恢复的三个文件及其余非存档文件不变；启动前已有的四个存档差异单独记录，直接启动和 Steam 阶段各仅有五个 `savedata` 文件自然更新，24 份原始/检查点备份副本完整。五部共享 profile 已保存，临时 Steam 启动选项均恢复为空（第一部由字段缺失变为空字符串，语义相同）。第一部云始终开启、显示最新且无冲突，时长 36 → 38 分钟；成就 0/4，但未达到触发条件，不判定兼容失败。自然成就触发、汉化存档实际云同步、更广泛的启动器兼容性仍未验证。本轮没有产品源码改动，未重复编译和自动化全门禁。

## 当前实现分层

| 层 | 命令 | 验证内容 |
| --- | --- | --- |
| Rust core / Runner | `cargo test --locked --workspace` | TOML、VDF、路径、Steam 元数据、Launch Options 与平台 Runner 行为；无 GUI 依赖 |
| C# 服务 | `Invoke-WinUI.ps1 -Action Test` | 配置保真和安全写入、本地发现、语言设置、稳定 Runner 安装与共享数据位置 |
| C# / Rust 契约 | `Test-WinUIContracts.ps1` | 未编辑语义全量比对，以及真实受控 Runner 的 argv/cwd、等待、退出和错误行为 |
| Windows 发布 | `Test-WinUIPublish.ps1` | 自包含 Manager/Runner 资源与发布目录替换、恢复 |
| WinUI 交互 | `Invoke-WinUI.ps1 -Action Sandbox` 加单独记录的原生交互 | 一次性数据、真实窗口/picker；自动化原生 UI 门禁仍在计划中 |

## 本地命令

按自己的方式安装 Windows 工具；mise 是可选项。SDK 要求及 PowerShell 入口见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。Rust workspace 只包含 core 与 Runner，Linux 不再需要 GTK/WebKit、Dioxus CLI、Xvfb 或桌面会话。

```bash
cargo fmt --all -- --check
cargo check --locked --workspace
cargo test --locked --workspace
```

Windows 使用上文 WinUI 命令，并用 `pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1` 验证发布及恢复。`Invoke-Build.ps1 -Action Doctor` 检查 .NET/Rust/MSVC/SDK；`-Action RustTest` 执行 `cargo test --locked --workspace`；`-Action Verify` 在 Rust 检查后依次运行 C# `Test`、`Test-WinUIContracts.ps1` 和 WinUI `Publish`，遇错停止。它不调用 Dioxus、pnpm Native E2E 或自动原生 UI 验收。相关行为改变时，另加发布恢复和隔离原生交互检查。

自动预览和进程 fixture 必须把 `STEAM_DIR`、`STEAMWRAPPER_E2E_ROOT`、`XDG_DATA_HOME`、`LOCALAPPDATA` 指向一次性目录，不能为了通过回归改用真实 Steam 或用户数据。

<a id="dioxus-native-e2e"></a>

## 已归档的 Dioxus Native E2E 证据

Dioxus 与 `manager-core` 已从当前 workspace 移除。[归档实现和测试](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/apps/manager-dioxus)、[管理服务](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/crates/manager-core)和[历史测试指南](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/docs/src/content/docs/zh-cn/development/testing.md#dioxus-native-e2e)固定在 `ca6a09e`。它们的命令和依赖不再是当前指导，也不验证 WinUI。

2026-09-07 Windows 本机完成当时的 Rust workspace、Runner 进程测试、Dioxus check/release build 和 3 个 spec / 6 项 Native E2E。提交 `3d322db` 的 [v2 完整 CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282786)还通过 Windows/Ubuntu 与 Linux AppImage 检查；工具修复与边界见 [归档环境记录](/SteamWrapper/zh-cn/development/windows/#本机安装与验证记录)。

2026-09-08 语言/图标实现通过 10 次隔离 Native E2E：原有 6 项、2 项语言/状态/错误用例，以及两个进程中的语言保存/重启。当时 Windows Rust workspace 共 43 项通过；依赖 C# 输出的契约在普通运行中有意忽略，另由 `winui:contracts` 通过。两个旧 Manager 包占其中 30 项，覆盖未知 JSON 数值保真、嵌套重复键拒绝和共同 64 层深度限制。TypeScript、E2E 工具、Dioxus check/release build 与 scoped strict Clippy 通过。[分发记录](/SteamWrapper/zh-cn/development/distribution/#ci--release-验证)保留旧 NSIS 内容检查及其边界。这些归档结果不能作为当前 WinUI 原生 UI 自动化、安装器或干净系统通过的证据。

## Runner 稳定安装验证

WinUI 的 [RunnerInstaller](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application/Services/RunnerInstaller.cs)在判定就绪前核验现存 Runner 与存在的 `profiles.toml`，并核验安装候选与安装后文件位置；缺少 profile 不影响独立健康检查。[位置检查](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application/Services/SharedDataFileLocation.cs)比较文件句柄最终路径与显式文件链接解析后的逻辑路径，发现重定向时返回非就绪并提示从资源管理器重新打开 Manager。现有 UI 仅在安装服务就绪后展示可复制启动项，Launch Options 字符串契约与 ProfileStore 保存算法未修改。

本次新增 9 条 [位置回归](https://github.com/YangYuS8/SteamWrapper/blob/main/apps/manager-winui/SteamWrapper.Application.Tests/RunnerLocationTests.cs)：已安装 Runner 重定向、升级候选重定向且保留旧 Runner/清单/配置、首次安装候选重定向、仅 profile 重定向、路径查询失败、普通原生句柄、真实 junction 升级、中文/大小写/扩展前缀及 DOS/UNC 前缀规范化。四种重定向场景先观察旧实现错误返回就绪，再验证修复；最终 `mise run winui:test` 43/43 通过，`winui:contracts` 通过。红/绿证据位于忽略的 `target/runner-location-tests/`，本轮契约结果位于 `target/winui-contracts/bfad46a031ff4713b378d875f6f2f621/results`。

服务测试后另行验证了新版发布产物的原生行为：受重定向的工具环境启动 Manager 后出现位置警告，保存不展示启动项或复制按钮；普通 Explorer 启动新版 Manager 后保存成功，生成完全一致的既有启动项。该原生复核与上述服务/进程证据分别记录，不替代干净 VM 或安装器验证。

当前稳定 Runner 的安装安全由 C# Application 测试和跨语言契约覆盖。退役的 Rust `manager-core` 与 Dioxus UI 安装测试已归档，旧结果不能替代当前服务测试。

Runner 进程测试覆盖 Linux `process_group`、Windows Job Object，以及两平台的 `process_name` 边界。`process_name` 仅按进程名匹配，无法判断并发同名业务归属；它不是默认等待模式。

## CI

`v2-ci.yml` 现为 Windows / Ubuntu 的 Rust core/Runner 检查及平台进程测试。`winui-windows.yml` 在 Windows 运行 C# 测试、C# / Rust 契约和自包含发布/恢复检查。旧 Dioxus Native E2E、AppImage job 与 NSIS release 链已移除。工作流声明不等于最新运行通过，须另行核验；WinUI 自动化原生 UI、安装器与更新门禁仍属于路线图。

## 限制

- C# 服务/契约和发布检查不能证明原生 UI、可访问性或干净 Windows 安装；WinUI 自动化原生 UI 门禁尚在计划中。
- 常规自动化不操作真实 Steam；真实验收需要授权、记录原启动项、保护存档、校验文件并恢复。一键应用/恢复 Launch Options 仍是后续功能。
- Runner 进程 fixture 仅证明对应平台和已测生命周期场景，不证明真实 Proton、breakaway、Unix daemonize/新 session 或 Steam Deck 兼容性。
- 当前预览是完整的 Windows 自包含目录；安装器、更新/卸载及干净 Windows VM 仍需独立验收。
- 上述 2026-09-07–09-08 Dioxus 记录是归档历史结果，不是当前 WinUI 证据。
