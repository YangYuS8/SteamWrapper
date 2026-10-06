---
title: "测试"
description: "选择相关的服务、原生界面、Runner、包体和 Steam 验证门禁。"
---

<a id="测试"></a>

SteamWrapper 分别验证跨 Windows/Linux 的 Rust core 与独立 Runner，以及 WinUI Manager 的 C# 服务、跨语言契约、自包含发布和本地交互原生 UI 回归切片。Dioxus、其 Rust 管理服务、Native E2E 与旧打包流程已退役。Windows 最终交付仍按 [阶段门槛](/SteamWrapper/zh-cn/project/design/windows-v2/#8-实施顺序与停止条件)验收。

[Manager 实测比较](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)是选型的归档证据；[测量脚本](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09ed5af8a06a04b3c36b2587efa5d94dc92c/scripts/windows/Measure-ManagerComparison.ps1)与 Dioxus 源码固定在提交 `ca6a09e`，不再是当前开发前置条件。

## 按改动选择验证

先读取受影响代码和测试，选择能证明本次结果的检查。无需每次编辑前运行整个 workspace，也无需为文档或纯样式调整新增匹配源码字符串的测试。

| 本次改动 | 本地验证范围 |
| --- | --- |
| 文档 / AGENTS / 技能 | 审核 diff、链接和指令冲突；文档/站点变更运行 `pnpm docs:check` 与 `pnpm docs:build` |
| Rust core 行为 | 先写能复现缺失行为的测试并观察预期失败，再修改实现；运行受影响 crate 测试；共享契约或跨 crate 影响时运行 workspace 检查和测试 |
| Runner 启动 / 等待 | 对应平台的真实进程回归测试；CLI / TOML / 公共模块变化再扩展到 workspace |
| WinUI / C# 服务 | `Invoke-WinUI.ps1 -Action Test`；配置协议或 Runner 分发变化增加 `Test-WinUIContracts.ps1`；发布修改后的 UI，在解锁的交互 Windows 桌面运行 `Test-WinUINativeUi.ps1`，其余 UI 门槛另做限定范围的人工检查 |
| 纯视觉调整 | 构建并在隔离 Desktop 预览中检查受影响界面；按影响选择现有测试，不用固定 CSS 字符串代替视觉验收 |
| 发布 / 工具链或共享构建变化 | 相关 Rust/WinUI 门禁、当前 Windows Runner staging、完整发布目录与 `Test-WinUIPublish.ps1`；安装器另行验收 |

CI 工作流仍执行各自完整门禁。上表限定日常本地工作量，不删减 CI。已通过的检查只在新改动、失败或未解决疑点出现时重跑；缺少工具时记录阻塞，不把未运行写成通过。

行为回归优先验证外部结果。服务或源码声明测试不能证明原生窗口、可访问性、布局或文件选择行为。现有仅用于开发的原生 UI 回归工具通过 Windows UI Automation 操作实际 WinUI 应用；首个切片不等于[原生验收路线图](/SteamWrapper/zh-cn/project/roadmap/)全部完成。实际执行用例与限定范围的人工检查须分别记录。

<a id="winui-迁移的新增验收"></a>

## WinUI 验收

先验证 C# 配置服务与 Rust Runner 的既有文件协议，再证明 UI 和安装器。已有入口：

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test
pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Test-WinUINativeUi.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

`Test` 动作同时运行 `SteamWrapper.Application.Tests` 与 `SteamWrapper.Windows.Tests`，包含配置保真／冲突／替换失败、本地 Steam、封面偏好／下载／缓存服务、稳定 Runner 安装与共享文件位置测试，以及实际 Windows 图片解码器。Windows 测试项目直接链接生产解码器源码，不加载 WinUI 或创建窗口，不属于原生 UI 自动化。`Test-WinUIContracts.ps1` 从共享历史 fixture 开始，C# 单字段修改后由 Rust 比较完整 TOML 和 Profile；再用受控父子进程验证 C# 新配置的精确 argv、cwd、job/root 等待差别、退出码和错误日志。详情见 [契约说明](https://github.com/YangYuS8/SteamWrapper/blob/main/tests/contracts/README.md)。测试驱动、fixture 及生成的用户目录都不进入发布目录。

封面回归使用一次性的 Steam／设置／缓存 fixture 与注入的 HTTP handler，不请求真实账号，也不写入真实游戏库。验证自定义／本地候选优先级与哈希布局、默认关闭与偏好持久化、离线缓存复用、取消／超时／404／限流及冷却、重定向白名单、有界字节／并发、缓存配额／过期／清理及无关文件保留。Windows 解码器测试涵盖有效 PNG／JPEG、截断容器、CRC 有效但 zlib 数据损坏的 PNG、尺寸／像素／字节限制、预先取消及可用 WebP codec 行为。codec 测试不证明行图片呈现、流畅编辑、语言布局或对话框取消，这些仍需 P0 实际 WinUI 验收。

目录分离新增 AppID 关联、库外运行路径保留和真实双库安装冲突回归，该实现轮 C# 共 49/49 通过。原生隔离保存、重新扫描和歧义新建配置也已验证；详见 [目录分离验证记录](/SteamWrapper/zh-cn/guides/translated-games/)。这些隔离结果本身不代表真实汉化迁移或成就触发通过。

后续默认英语/完整简体中文实现通过 59/59 项 C# 测试，其中新增 10 项本地化/偏好测试。两条默认英语测试先在旧服务中文消息上失败；UTF-8 BOM 偏好读取和嵌套 JSON 重复键拒绝也先失败再修复。测试覆盖英文与中文资源键和格式参数一致、已存在嵌套状态/错误切换、诊断和用户值不变、双语扫描/Runner 消息、规范语言持久化、未知字段与 profiles 保留、损坏/重复/过大 JSON 拒绝及 BOM 兼容。跨语言／Runner 契约和最终自包含发布通过。[后续语言验收](/SteamWrapper/zh-cn/project/validation/winui/#后续语言支持)记录隔离的原生切换、重启保持、输入／profile 字节保留和图标检查；这些不是干净系统或真实 Steam 证据。

原生本地化验收应使用没有 `ui-settings.json` 的全新隔离数据根，确认首次启动跟随已支持的 Windows 界面语言，不支持时回退英语。打开配置编辑、添加参数并触发验证/状态消息，切换到简体中文再切回英语；检查应用自有标签、参数行、等待模式、既有状态、对话框和 picker 动作按钮文案同步变化，未保存的名称、路径、参数及已生成启动项保持不变。重开沙盒 Manager 检查持久化，并检查两种语言的换行、截断、键盘操作和对话框布局；检查发布目录的 `zh-CN/SteamWrapper.Application.resources.dll`。服务/资源测试不能替代原生呈现或发布完整性验证。

WinUI Manager 使用与 `profiles.toml` 同级的 `ui-settings.json`，`language` 为 `en-US` / `zh-CN`；兼容 `en` / `zh-SG` / `zh-Hans`，去除首尾空白且不区分大小写。没有键时跟随支持的系统界面文化（`zh-CN`、`zh-SG` 及明确的 `zh-Hans`），其余文化使用英语；已保存的明确选择优先，无效明确值或无法读取的设置回退英语。读取或仅保存封面偏好不会保存识别出的语言。保存成功后刷新界面而不重载正在编辑的配置；失败保留旧语言并报告错误，损坏的设置文件原样保留。系统 picker 自有文案和外部原始诊断保持原语言。测试必须使用一次性设置目录，不修改真实 AppData 或 Steam 配置。

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
| C# 服务 | `Invoke-WinUI.ps1 -Action Test` | 配置保真和安全写入、本地发现、语言／封面设置、有界封面请求／缓存、稳定 Runner 安装与共享数据位置 |
| Windows 图片解码器 | `Invoke-WinUI.ps1 -Action Test` | 生产解码器及 Windows codec；有效／损坏图片、资源限制与预先取消，不创建 WinUI 窗口 |
| C# / Rust 契约 | `Test-WinUIContracts.ps1` | 未编辑语义全量比对，以及真实受控 Runner 的 argv/cwd、等待、退出和错误行为 |
| Windows 发布 | `Test-WinUIPublish.ps1` | 自包含 Manager/Runner 资源与发布目录替换、恢复 |
| WinUI 交互 | 发布后运行 `Test-WinUINativeUi.ps1`；额外人工检查使用 `Invoke-WinUI.ps1 -Action Sandbox` | 可丢弃数据下实际窗口的 UIA 回归；其余选择器、输入、布局和玩家门槛单独限定范围 |

## 原生 UI 回归

完整发布后运行 `pwsh -NoProfile -File scripts/windows/Test-WinUINativeUi.ps1`，或可选的 `mise run winui:native-test`。包装脚本验证已有完整便携目录，以锁定依赖 restore/build `SteamWrapper.NativeUi.Tests`，再用新的可丢弃 Steam／用户数据夹具打开实际 Manager。它不重新发布 Manager、不构建安装器、不使用真实游戏库。`-PublishDirectory` 可选择具体的完整便携目录；已安装的版本目录会被拒绝。

执行需要**解锁的交互 Windows 桌面**，套件操作夹具窗口期间应保持该桌面可用。CI 仅编译这个开发用控制台 UIA 工具。WPF 引用用于取得 Windows 自动化 API，不是另一个 Manager 实现，也不进入应用包。托管服务会话中的编译不能记为原生测试通过。

单独验证 DPI 与中文输入法时，可用 `Test-WinUINativeUi.ps1 -Inspect` 保留可丢弃夹具 Manager 窗口。将输出的 PID 记为 `$fixturePid`，再读取实际窗口指标：

```powershell
pwsh -NoProfile -File scripts/windows/Read-WinUIWindowMetrics.ps1 -ProcessId $fixturePid
```

只读工具要求进程位于当前会话，且 Manager 可执行文件在本仓库 `target/winui` 内。它记录窗口／工作区像素边界、真实 HWND DPI／缩放、键盘布局及可读取的旧式 IMM 状态；无 IMM 上下文明确记为 `unknown`，不能据此认为现代 TSF 输入已禁用。可选的 `-OutputPath target/winui/window-metrics.json` 在已有证据目录创建新 JSON，拒绝覆盖和链接路径。工具不改变焦点、窗口大小、输入或显示设置；单次指标不证明视觉可用性或输入法组合输入。应使用实际按键观察候选、提交和取消，并在截图旁记录真实 DPI；Unicode `ValuePattern.SetValue` 或放大截图不能代替这些验收。

首个切片检查英语启动、现有 AppID 不可改、切换语言时保留 Unicode 编辑、取消未保存导航／关闭窗口、外部保存冲突、重启后保留中文偏好／未知设置，以及未知 Runner 失败时不替换其字节。另覆盖取消原生目标选择器、CDN 关闭时选择／筛选封面缺失或损坏的本地游戏，以及成功保存后保留未知 TOML 并生成稳定 Runner 启动项。选择检查不能证明所有封面已正确呈现或网络请求为零。证据与窗口快照保存在 `target/winui/native-ui/`。工具仅正常关闭自己创建的夹具 Manager；未解决的夹具窗口与诊断文件会保留。中文输入法组合输入、显示缩放、可访问性／布局、剪贴板、实际下载／网络行为及更广玩家验收仍需单独证据。

**2026-10-03 本地记录：**包装脚本针对真正编译的 `0.2.2` 便携目录执行，**10 项原生用例全部通过**。三个可丢弃夹具分别覆盖普通编辑／重启、选择器／封面／成功保存流程和未知 Runner 失败。证据记录实际发布的 EXE／DLL／Runner／清单哈希及 `cleanVm=false`；成功保存另保留 TOML 注释、未知字段与备份字节。这是该切片的真实交互窗口证据，不代表 CI 原生执行、输入法／缩放／剪贴板、零 HTTP 或真实 Steam 验收。W1 仍未完成。

**2026-10-03 后续系统语言记录：**新增实际窗口用例在本机 `zh-CN` Windows 桌面的 `0.2.2` 产物上先失败，因为首次启动仍显示英语。真正编译的 `0.2.3` 在四个可丢弃夹具中通过 **11 项原生用例**，包括自动中文且不保存 `language` 偏好，以及已有的明确英文／中文重启流程。注入文化的服务测试另覆盖未支持／繁体文化、明确无效值、损坏设置及仅保存封面偏好。这改变首次启动默认行为，不代表输入法、缩放或干净客户端验收。

**2026-10-03 聚焦 `0.2.4` 记录：**WinUI 排队的 `TextChanged` 事件曾把刚载入且未改变的字段误标为未保存，阻断后续原生添加流程。修复后，真正编译的 `0.2.4` 发布通过本地游戏添加、手动 AppID 验证／添加、添加／导航时保留未保存编辑，以及键盘焦点／导航四个新增流程，另通过八个受影响的已有编辑用例，共 **12 项实际窗口用例**；六个夹具进程均正常退出。可用 `Test-WinUINativeUi.ps1 -Cases add-local`、`manual-appid`、`dirty-add`、`keyboard`、`existing-editor` 或 `saved-editor` 选择流程。键盘检查使用 HWND 消息并观察焦点，不证明物理键盘输入、中文输入法组合输入或 100%／150%／200% DPI 验收通过。W1 仍未完成。

## 安装器与签名命令

### 项目更新检查与安装

**公开预览版，2026-10-05：**[v0.2.5-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.5-preview.1) 已作为 GitHub 预发布公开，包含七个附件，构建源码为 `19d04b8`。[发布运行 37232987692](https://github.com/YangYuS8/SteamWrapper/actions/runs/37232987692)通过成品打包、隔离安装／恢复和修正后的最终安装选项矩阵。安装包为 49,901,116 字节，便携 ZIP 为 73,765,434 字节。这完成公开发布及该托管运行器矩阵，不代表干净 Windows 客户端，也不替代下文各自限定范围的原生／接力证据。

实际 `0.2.5` 的 `OfficialUpdateService` 使用内嵌项目公钥及隔离数据目录，验证了公开 GitHub `update-preview` 更新源。传入已安装标签 `v0.2.4-preview.1` 时，选中 `v0.2.5-preview.1` 并下载 49,901,116 字节安装包，SHA-256 为 `0cd78a00070d4e40eeb1f376a98b94f0b3febb82a3357be3b6b0b35555ae57da`；传入 `v0.2.5-preview.1` 时正确返回无更新。证据为 `target/winui/public-update-probe/run-20261004T205845Z-0c539c056f89474d808503ab38c9ac0d/evidence.json`。**没有执行下载的公开安装器**。这是服务级公网验签／下载验证，与下文真实隔离 Inno 接力分开，不是公开下载至安装完整流程或干净虚拟机通过。旧 `0.2.4` 应用没有更新界面，仍须手动安装一次。

随后[元数据续期运行 37234226421](https://github.com/YangYuS8/SteamWrapper/actions/runs/37234226421)通过，新签名验证成功，序号从 `1791147499592` 增至 `1791147575660`；标签／提交、签名中的软件身份和七个发行附件的 ID／摘要／大小／更新时间均未改变。同目录 `refresh-evidence.json` 记录本次核验：没有重建软件、再次下载安装包或执行安装器。

完整 Publish 后，运行 `pwsh -NoProfile -File scripts/windows/Test-WinUIInstallerOptions.ps1` 验证隔离静默安装／快捷方式选择；增加 `-BaselineDirectory <冻结旧版目录> -BaselineTag <旧标签>` 可验证真实版本升级与修复时的选择继承。在交互式 Windows 桌面运行 `pwsh -NoProfile -File scripts/windows/Test-WinUIInstallerOptionsUi.ps1`，验证英语和简体中文原生安装／卸载选择。两者均支持 `-PublishDirectory <完整目录> -Tag <匹配标签>`。界面脚本检查取消、七个默认关闭的卸载选项，以及明确选择缓存清理时保留其他夹具数据；不会选择真实 Steam 游戏库或真实应用数据目录。脚本存在不等于测试通过，实际结果单独记录。

`Invoke-WinUI.ps1 -Action Test` 包含签名／时效／重放、官方源重定向、有界下载、取消及安装接力回归。`pwsh -NoProfile -File scripts/releases/Test-ProjectUpdates.ps1` 使用临时测试密钥和网络替身测试项目签名及 GitHub／CNB 发布／续期，不实际写入公开 Release。普通 CI 包含此门禁，但不构建安装包。

设置 `STEAMWRAPPER_RELEASE_TAG` 为准确匹配标签并发布完整目录后，`Test-WinUINativeUi.ps1 -Cases updates` 操作真实更新对话框，检查默认值及取消不改变测试设置。使用 `Test-WinUIUpdateHandoff.ps1 -BaselineDirectory <冻结旧版目录> -PublishDirectory <新版目录> -BaselineTag <旧标签> -Tag <新标签>`，通过复制后的 NativeAOT 更新 Host 完成真实隔离 Inno 升级。脚本检查发起进程正常退出、新 Manager 启动、旧版本保留，以及配置／设置／稳定 Runner 字节不变，再正常关闭并卸载仅属于该测试的安装。证据保留在 `target/winui/update-handoff-*`。

该本机测试使用真实的新旧产品版本与隔离安装包，不执行公开生产安装器，不证明干净 Windows 环境或公开更新源／下载可用；这些事实需单独记录。失败时保留诊断，不强制结束进程。旧客户端没有更新界面，首次切换到新客户端仍需手动安装。

**2026-10-05 隔离接力结果：**`target/winui/update-handoff-0cda5e9d953e4070bdb9268a3cbbb8a5/evidence.json` 记录真实 `v0.2.4-preview.1` → `v0.2.5-preview.1` 升级通过，由 NativeAOT 辅助程序交接实际 Inno 安装器。发起进程正常退出，新 Manager 重新启动并确认安装健康，随后正常关闭；旧 `0.2.4` 版本保留。SHA-256 检查确认 `profiles.toml`、`ui-settings.json` 和稳定 Runner 测试文件在升级及成功卸载隔离测试安装后均未改变。证据明确记录 `actualInstaller=true`、`cleanVm=false` 和 `signedFeedNetwork=false`：该结果验证本机安装接力，不代表干净客户端或完整公开更新源／下载路径通过。

**2026-10-05 安装选项后续结果：**完整服务测试中的 **173 + 9 + 149 项**全部通过。随后跨卷还原修正通过 **15 项 Steam 还原／卸载选项聚焦用例**，其中设置 `STEAMWRAPPER_TEST_SECOND_VOLUME=G:\`，在 C: 与 G: 上使用一次性夹具执行 `SteamAndUserDataCanResideOnDifferentVolumes`。未设置该环境变量时不执行跨卷用例，因此普通 CI 不证明双卷行为。还原在已验证副本写入数据备份目录前，将原子替换备份保留在 `localconfig.vdf` 旁；未解决的相邻备份阻止删除配置／Runner。处理方法见[恢复指导](/SteamWrapper/zh-cn/guides/installer-preview/#卸载)。

修正注册 `InstallLocation` 的尾部分隔符后，新的真实 `0.2.4` → `0.2.5` 接力通过，证据为 `target/winui/update-handoff-a7435f5b11e64f18ab5c78387d0a078a/evidence.json`。记录确认 Manager 健康重启、保留旧版、配置／偏好／稳定 Runner 未变、进程正常退出及隔离安装卸载。这次运行验证修正后的位置处理，替代之前接力结果的对应部分，仍为 `cleanVm=false` 和 `signedFeedNetwork=false`。它不证明各项新清理选择、原生安装器／更新界面或公开更新源／下载验收通过，这些仍待完成。

**2026-10-05 安装选项进程与原生窗口结果：**`target/winui/installer-options-ee70315ca4d445459894dc0b04d7f3c2` 记录 **14 个实际静默进程步骤均以 0 退出**，覆盖真实 `0.2.4` → `0.2.5` 升级／修复继承、默认／仅桌面／双快捷方式／无快捷方式，以及正常卸载。随后测试脚本在 `finally` 中尝试重启仍在自删除的卸载器而失败；夹具现已等待删除结束。这些成功步骤不代表原先整次脚本运行通过，发布工作流将重跑修正后的矩阵。

原生证据 `target/winui/installer-options-ui-63f76dbce89a40689978dfe2e0126e17` 记录**六个成功动作**：每种语言各执行安装导航／取消、卸载取消、明确选择仅清理缓存的卸载。英文 `setup-english.json`、`cancel-english.json`、`cache-english.json` 通过；夹具补充处理测试目录已存在的确认后，中文续跑的 `evidence-chinesesimplified.json` 及动作／数据记录通过。这是英文成功后修正夹具再续跑中文，并非一次不中断的完整套件通过。七个卸载选项默认关闭；取消保持哈希；仅缓存卸载删除下载缓存和 Manager，六个未选夹具文件哈希不变，保留了双语截图。最终尺寸／对齐微调另做视觉检查。这不证明所有删除选项、更广 DPI／键盘行为、干净虚拟机或公开更新源／下载通过。

随后最终英／中仅布局套件通过，证据为 `target/winui/installer-options-ui-9f9ff0ee0edf401bbd33f3d62c16d74b/evidence-english-chinesesimplified.json`（`passed=true`、`layoutOnly=true`、`cleanVm=false`）。两个原生窗口均有七个未勾选选项，文字完整、按钮位于右下；取消保持全部夹具数据与安装清单哈希，随后正常默认卸载保留全部夹具数据。前述仅缓存检查后只改变尺寸／对齐，因此最终聚焦运行未重复缓存清理。这单独验证最终布局和默认保留路径，不扩大前述功能范围。

`Invoke-WinUI.ps1 -Action Test` 也运行部署库的进程／清单／日志回归。`Test-WinUIInstallerScripts.ps1` 不生成应用安装包，仅测试打包保护；`Test-WindowsSigning.ps1` 使用政策夹具和真实 Windows 信任失败，不申请签名。`Test-RunnerSigningMetadata.ps1` 检查已构建 Runner 的 PE，不执行它。这些检查进入日常 Windows CI。

完整发布后，`Test-WinUIProductMetadata.ps1` 检查全部七个自有 EXE／DLL 产品（含中文资源）及实际 x64／GUI NativeAOT Host。发布工作流要求此门禁，它不执行文件，也不证明发布者签名。

`Test-WinUIHostLanguage.ps1` 在新建的隔离程序／数据夹具中单独启动发布后的 NativeAOT Host，不传 `--language`、不注入文化。本机 `zh-CN` Windows 上，缺失及未含语言键的偏好最初失败，因为 Host 发布时启用了 invariant globalization；移除该模式后，包含显式英／中选择和损坏设置回退的五项全部通过。设置、配置和独立 Runner 夹具字节保持不变。隔离路由要求既有 test-root 授权，并将程序／数据路径限定在同一 sandbox；生产偏好位置不变。这是真实本机 Host 证据，不代表另一种系统文化或干净虚拟机。

完整 Publish 并安装已验证 Inno 工具后，`Test-WinUIInstaller.ps1` 在隔离程序／数据根目录运行真实安装／卸载及兼容 maintenance 回滚进程。默认下一版本输入是人工构造的元数据夹具。真实版本验收需冻结旧的完整目录，并用 `-UpgradePublishDirectory` 指向真正编译的新数字版本；命令与证据边界见[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)。版本标签及手动预览工作流执行隔离门禁并单独构建安装包；普通分支 CI 不打包安装器。本地真实版本通过仍不等于干净 Windows 11、原生向导／Explorer 或注册表／快捷方式／断电验收。

磁盘准入预算包含载荷文件、清单、原子启动器副本、有界状态／日志替换和 16 MiB 余量。回归先观察到短预算被错误接受，再验证空间不足时不激活或改变旧文件。七个隔离子进程停止用例在五个安装、两个恢复检查点使用 `Environment.Exit(73)`，验证持久化回执／日志、操作系统释放租约、恢复／隔离残留及独立数据夹具不变。这是编译部署引擎的进程停止测试，不是整机断电、真实填满磁盘或注册表／快捷方式故障。在当时的 2026-10-03 阶段，旧版本清理尚未实现，因为扩展严格旧状态／根目录结构可能破坏旧二进制回滚；下方后续源码回归在不扩展这些结构的前提下修复这一缺口。

**2026-10-03 新增卸载切片：**编译后的进程夹具在卸载日志创建、版本隔离、停用、清理预约、部分自有文件删除和清理完成六个检查点，使用 `Environment.Exit(73)` 结束自己的进程。聚焦的 **14 项卸载用例通过**，覆盖持久化阶段恢复、租约释放、未知／已改变字节保留、独立数据保留及隔离保护；共享夹具改变后，原有**七项安装／恢复进程停止用例另行通过**。测试仅触及新建且严格归属的临时目录，不终止其他程序。复现命令为 `dotnet test apps/deployment-windows/SteamWrapper.Deployment.Tests/SteamWrapper.Deployment.Tests.csproj --configuration Release --filter FullyQualifiedName~ProcessStopUninstallTests`，TRX 记录位于 `target/winui/test-results/uninstall-process/`。这个聚焦结果不替代此前完整的 99 项套件，也不宣称本机完整跑过 113 项、Inno／注册表／快捷方式中断、真实磁盘耗尽或版本保留。

首次真实 `0.2.2 → 0.2.3` 安装器测试发现加入原始依赖许可后，长路径导致卸载拒绝。重点真实 Win32 回归复现了自有路径在隔离时由 248 增至 281 字符。修复对已核验的删除句柄采用 Unicode 扩展路径，保留所有权、哈希、大小、reparse／只读拒绝及锁定检查。修复后卸载／重装和独立数据保留通过；最终 Deployment 套件 **99/99** 通过，非法 root 的显式 CLI 语言也有实际进程覆盖。未修改 Windows 路径政策或玩家数据。

`Test-WinUIInstallableReleaseScripts.ps1` 验证明确的第 2 版创建／下载校验，同时保留第 1 版校验器。GitHub／CNB 发布器测试分别运行默认旧输入和 `-Installable`，使用可丢弃 API，不写真实网络。`Test-SignPathConfiguration.ps1` 验证草案／声明前置条件与精确签名目标，不提交或读取凭据。[申请材料](/SteamWrapper/zh-cn/project/design/signing-application/)区分本地准备、外部批准及真实已签名产物验收。

**2026-10-03 本地真实版本记录：**经哈希核验的冻结 `0.2.1` 目录与真正编译的 `0.2.2` 载荷完成 **13 个真实进程步骤，结果符合各自预期**，包括英文安装、中文修复／升级、实际 maintenance 回滚 `0.2.2 → 0.2.1`、Inno 再升级、占用／未知文件／迟到自有文件锁拒绝，以及卸载／重装。`numericUpgradeUsesSyntheticMetadataFixture=false`；回滚保留 928 个自有版本文件及 maintenance／卸载器／夹具快捷方式的哈希，六个数据夹具始终未变。两套 Setup 及项目自有 PE 产品匹配其真实数字版本；当前 C#／Rust 契约另行通过。日志与 `evidence.json` 保存在 `target/winui/installer acceptance 中文 ' <id>/`。证据明确标记 `unsigned=true`、`cleanVm=false`。没有可用的干净 VM；这不代表 W2、完整中断／注册表／快捷方式恢复、旧版本清理或认证交付完成。

**2026-10-03 后续修正后的 `0.2.2 → 0.2.3` 记录：**冻结 `0.2.2` 目录与最终编译的 `0.2.3` 发布完成相同的 **13 个真实进程步骤**，包含长路径修正后成功卸载／重装。实际 maintenance 回滚 `0.2.3 → 0.2.2` 保留 1,066 个自有版本文件哈希和独立 maintenance／卸载器／快捷方式所有权，随后 Inno 再升级成功。六个数据夹具保持不变；升级为真实版本、本机未签名测试，`cleanVm=false`。该修正结果与保留的首次失败夹具分别记录，不代表剩余 W2 门槛完成。

**2026-10-03 真实 `0.2.3 → 0.2.4` 记录：**经核验的冻结 `0.2.3` 目录与编译后的 `0.2.4` 发布完成 **13 个符合预期的真实 Inno／maintenance 步骤**。实际 maintenance 回滚 `0.2.4 → 0.2.3` 保留 1,204 个自有版本文件哈希及维护程序／卸载器／快捷方式，随后 Inno 再升级。迟到的自有文件锁和未知文件拒绝卸载，后续正常卸载／重装通过，六个数据夹具始终未变。证据为 `target/winui/installer acceptance 中文 ' f9b299a94e654ab78a528bd1ea227c37/evidence.json`，记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`unsigned=true`、`cleanVm=false`。当前七个自有 PE 产品版本和五项实际 NativeAOT Host 语言另行通过；跨语言契约结果位于 `target/winui-contracts/8091f4314b2a4d44af031837ef6ad933/results`。此前记录继续保留，这不代表干净客户端、完整中断、版本保留或签名门槛完成。

**2026-10-03 公开下载记录：**[版本 `v0.2.3-preview.1`](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.3-preview.1)已由成功的[运行 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907)发布。从官方公开 URL 下载全部七个附件，核对 GitHub API 长度／摘要与第 2 版元数据；七个自有 PE 产品版本均匹配 `0.2.3`，Setup 正确识别为未签名。下载的 NativeAOT Host 在本机 `zh-CN` Windows 上五项实际语言用例通过。证据为 `target/winui/public-download/2d644b9cc4b344a78e2fc4a0d8c10e45/evidence.json`，标记 `signed=false`、`cleanVm=false`、`installedPublicSetup=false`：此次只检查下载的公开 Setup，没有安装它。CNB 发布凭据未配置，二进制发布实际跳过，因此不公告 CNB 二进制下载。这是下载完整性和限定范围的本机 Host 证据，不代表发布者签名或干净客户端验收。

## 本机验收

常规 Windows 验收可以直接在维护者的电脑上执行。安装器脚本编译独立的测试安装身份，把程序、数据和快捷方式限制在可丢弃目录中；原生 UI 测试也使用模拟 Steam 游戏库。Windows Sandbox 是可选工具。不要给生产 Setup 传入测试目录覆盖参数，应使用现成的隔离安装器脚本。

**2026-10-05 本机记录（Windows 11，系统构建 26300）：**实际 `0.2.4` 基线与当前 `0.2.5` 发布通过全部 **13 个符合预期的 Inno／maintenance 步骤**，包括安装、中文修复、真实升级、兼容回滚、再升级、占用／锁定／未知文件拒绝、卸载和重装。回滚保留 1,204 个受管版本文件及维护程序／卸载器／快捷方式哈希，六个独立数据夹具始终未变。证据为 `target/winui/installer acceptance 中文 ' 07f33d24318b4ed1b087cb19eeb1561d/evidence.json`，记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`cleanVm=false`。

该轮 `0.2.5` 原生 Manager 在 `target/winui/native-ui/中文 空格 ' 095cf2308c774c6e8a17ff368726e516/evidence.json` 中通过 **16/16 用例**，包含实际系统语言默认值、英中切换、Unicode 编辑及未知 TOML／设置保留、取消导航／关闭、外部保存冲突、缺失封面占位、稳定 Runner 就绪、本地／手动添加游戏、夹具窗口键盘导航，以及更新对话框默认值／取消。

完整英中安装器 UI 也在**一次连续命令中通过六个动作**，证据为 `target/winui/installer-options-ui-6026e35ccd6c40f6a24b8ed294e34a22/evidence-english-chinesesimplified.json`，标记 `layoutOnly=false`：每种语言分别执行安装取消、卸载取消、只清理缓存的卸载。七项默认不选；取消保留数据与安装哈希，选择缓存清理时保留全部未选中的夹具文件。两条命令均以 0 退出。本次结果补充此前局部／分段记录，不改写那些记录。

实际打包的 `0.2.5` Runner 另行通过**五项检查**，证据为 `target/winui/packaged-runner-smoke-98f6ef9ca2674cfebf45b45fda7694d2/evidence.json`，命令以 0 退出。稳定副本与清单哈希一致；中文／空格／引号／尾反斜杠／空参数及工作目录均准确。`job` 等待受控子进程，`root` 只等父进程；保留正常退出码 7、缺失目标退出码 1 及错误日志。三个 Runner 和四个目标进程均正常退出。在启动前、轮询期间及结束后未观察到新的 Manager，这种限定观察不保证每个瞬间的窗口状态。较早的 WMI 订阅尝试在任何 Runner 启动前失败，作为单独的测试工具诊断保留。

这些是当前电脑上的实际原生窗口及隔离安装器测试，不代表无 SDK 的干净客户端、生产目录选择器、其他 Windows 版本、物理键盘／输入法／DPI、全部清理组合或真实 Steam／游戏验收通过。

## 版本保留与稳定通道回归

**2026-10-05 尚未发布的源码记录：**完整 Deployment 套件通过 **160 项测试**，另有一项依赖环境的跨盘用例跳过；结果为 `target/winui/retention-tests/deployment-retention-staging-all.trx`，跳过不计为通过。新增版本保留回归覆盖健康确认后的清理、未确认时保留、32 版本准入与有界日志大小、超过 32 个版本的旧安装，以及未知、改变、占用或链接文件的拒绝。安装／修复只在当前版本确认健康后持有独占锁清理，保留当前版本和记录的上一版本；新安装可能暂留三个版本。卸载允许在 32 MiB 所有权日志内记录最多 1,024 个旧版本，不递归清除未知数据。当前行为见[分发](/SteamWrapper/zh-cn/development/distribution/)。

实际冻结的 `0.2.1`、`0.2.2`、`0.2.4` 部署辅助程序还通过 **18 个夹具场景，共执行 42 个真实旧二进制进程**。`target/winui/retention-legacy-compat/evidence-staging/evidence.json` 记录正常恢复／回滚／修复，以及版本保留日志创建、版本暂存、部分删除、目录删除完成和恢复记录创建处的中断。输入使用人工载荷元数据并模拟健康确认；未启动旧 Manager UI、真实 Steam 或游戏。这证明实际执行的部署协议／恢复范围，不代表完整历史应用启动或真实下一版本 Setup 升级；当前／上一版本自有字节和恢复隔离数据仍受保护。

重点 C# `UpdatesOfficialServiceTests` 命令通过 **19 项**，包含已安装稳定／预览通道与 GitHub／CNB 来源的四种组合，下载同一经过项目验证的稳定安装包；同数字版本的预览转稳定在下载前拒绝。测试使用一次性签名元数据、密钥和 HTTP handler，不代表公开稳定更新源已存在。复现命令为 `dotnet test apps/manager-winui/SteamWrapper.Application.Tests/SteamWrapper.Application.Tests.csproj --configuration Release --filter FullyQualifiedName~UpdatesOfficialServiceTests`。

脚本门禁也通过稳定与预览夹具：`Test-WinUIReleaseScripts.ps1`、`Test-WinUIInstallableReleaseScripts.ps1`、GitHub／CNB 发布器测试及 `scripts/releases/Test-ProjectUpdates.ps1`。发布器测试覆盖旧便携与安装包；给 `Test-GitHubRelease.ps1`、`Test-CnbRelease.ps1` 添加 `-Installable` 和／或 `-Preview` 可选择对应夹具。测试验证标签决定的发布标记、不可变重试、稳定／预览签名更新源发布与续期，以及同数字版本替换拒绝，不写公开版本。现有第 1 版和七附件第 2 版契约仍相互独立。

**2026-10-06 真实新载荷记录：**冻结 `0.2.5` 与真正编译的 `0.2.6` 通过 **13 个符合预期的隔离 Inno／maintenance 结果**，包括修复、实际升级／回滚／再升级、占用／锁定／未知文件拒绝、卸载和重装。`target/winui/installer acceptance 中文 ' 98642fc6bdb34eb09d69bfb6e2aab89f/evidence.json` 记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`cleanVm=false`。实际 maintenance 从 `v0.2.6` 回滚到 `v0.2.5-preview.1`，保留 1,204 个自有版本文件哈希及维护程序／卸载器／快捷方式；六个独立数据夹具均保持原字节。这是真正编译的版本序列，使用隔离安装身份，与上方人工旧辅助程序夹具区分。

当前 `0.2.6` 的 `Invoke-WinUI.ps1 -Action Test` 还通过 **178 项 Application、九项 Windows 解码器和 160 项 Deployment**，另跳过依赖环境的跨盘 Deployment 用例；`Test-WinUIContracts.ps1` 单独通过。`target/winui/stable-readiness-cli-gates/summary.json` 记录两条命令的退出码、跳过用例、命令日志及 `target/winui-contracts/63e2434c8acd46c1b183886db8db5601/results`；actionlint 1.7.12 通过，检查后未改工作流。这是 CLI／契约结果，不代表原生或干净客户端验收。

协调的源码／产品版本现为 `0.2.6`；这些测试不代表已创建 `v0.2.6` 标签或发布稳定版，公开版本仍为 `v0.2.5-preview.1`。剩余干净客户端／原生验收仍须先于真实发布与下载核验；Authenticode 可选。

## 干净 Windows Sandbox 验收

普通 Windows CI 使用可丢弃输入执行以下验收工具回归。便携检查覆盖压缩包清单、哈希和安全解压；普通账户检查覆盖身份／令牌、交接路径与 ACL 边界，不创建用户。工作流另使用 Windows 自带 PowerShell 5.1 解析只读指标脚本并编译其嵌入 C#，不读取窗口。这些门禁不执行客体、不构建安装包，也不发布版本：

```powershell
pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptanceScripts.ps1
pwsh -NoProfile -File scripts/windows/Test-PortableAcceptanceScripts.ps1
pwsh -NoProfile -File scripts/windows/Test-StandardUserAcceptanceScripts.ps1
```

Runner 依赖检查器按四个数值文件版本字段选择官方 MSVC 工具。托管工具的显示字符串可能附带 `built by: cloudtest`，首次 CI 因把显示文本当版本号解析而失败。`pwsh -NoProfile -File scripts/windows/Test-RunnerDependenciesScripts.ps1` 的四项聚焦选择回归通过，现已加入正常 CI，在编译前执行。此工具修正不改变已验收候选载荷的字节。

Windows Sandbox 提供全新的 Windows 客户端，不带宿主机已安装的开发工具。以管理员身份启用 `Containers-DisposableClientVM` Windows 功能，并完成系统要求的重启。这是维护者可选的验收环境，不是贡献者的前置要求。分别记录实际客体与宿主构建：2026-10-06 运行中客体为 **26100**，宿主为 **26300**。这个由 Sandbox 管理的客体使用管理员账户，并非独立 ISO 安装的虚拟机，不代表标准用户或其他构建兼容性通过。

```powershell
pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptance.ps1 -Action Prepare
# 使用 Prepare 输出的准备目录：
pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptance.ps1 -Action Launch -PreparedRoot "<prepared-directory>"
pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptance.ps1 -Action ReadEvidence -PreparedRoot "<prepared-directory>"
```

准备阶段对照 GitHub 附件的哈希、大小及精确标签提交，核验两个公开 Setup 安装包及其描述文件。可选的 `-BaselineInstallerPath`、`-InstallerPath` 允许复用已下载的公开 Setup，但仍需通过相同核验，不能使用重新构建的测试安装包。默认执行真实的 `v0.2.4-preview.1 → v0.2.5-preview.1` 升级；完整便携 ZIP 检查仍由独立发布门槛负责。

发布前，独立的 `CandidateFirstInstall` 路径可验证使用实际生产安装身份的本地 Setup，不假装它已经公开下载或完成数字版本升级。Prepare 时使用 `-Tag v0.2.6 -CandidateInstallerDirectory target/winui/installers/static-readiness-v0.2.6 -StartupMode AfterLogin`。它核验封存的构建／部署清单及安装器准确字节，记录源码 HEAD 和未提交工作区标记；候选证据明确为 `unpublishedCandidate=true`、`numericUpgradeTested=false`。候选首次安装生命周期与公开升级路径、完整稳定交付相互独立。

排查启动命令导致的连接失败时，可使用 `Prepare -StartupMode AfterLogin` 不自动执行客体。启动这个新准备环境，用 `wsb list` 找到准确 UUID，待桌面连接后执行 `Test-CleanWindowsAcceptance.ps1 -Action Execute -PreparedRoot "<prepared-directory>" -SandboxId "<sandbox-uuid>"`。该受保护路径核验封存输入／配置、唯一已连接 Sandbox 和全新输出目录，绝不回退到宿主执行 Setup。仅启动或 CLI 连接不代表验收。

沙盒仅共享专用只读输入目录与可写结果目录，并关闭联网、剪贴板、麦克风、摄像头和打印机共享。真实 Steam、游戏、存档、用户数据及仓库均不映射。内置 PowerShell 5.1 客体脚本在执行生产 Setup 之前，会拒绝开发宿主机、已有产品安装、数据重定向和测试环境覆盖；它记录初始运行库状态，不安装额外 SDK 或运行库。

Windows 自带 CBS 运行库与外部安装运行库通过准确的 Microsoft 发布者／包族、`System` 签名类型、`NonRemovable=true`、framework 身份及预期的 `C:\Windows\SystemApps` 位置区分。脚本拒绝外部运行库，并验证 Manager 实际从自己的版本载荷加载 `coreclr.dll` 和 `Microsoft.UI.Xaml.dll`；不为制造“无运行库”环境而删除 Windows 组件。

客体执行正常当前用户首次安装、原生 Manager 保存配置并安装稳定 Runner、无害程序的独立 Runner 启动、修复、真实升级、默认卸载保留数据，以及自定义中文目录重装；核对快捷方式、注册、受管版本目录及保留配置／Runner 哈希。安装器使用生产静默选项，因此不能据此证明向导交互或真实 Steam 验收。日志、截图及 `evidence.json` 保存在专用结果目录。准备或启动沙盒不代表通过，必须读取对应运行的完整客体验收结果；超时保留进程，不强制关闭。

2026-10-05 已通过脚本解析、内置 UIA／辅助检查及拒绝宿主执行检查，公开安装输入完成核验。在那次重启后，Sandbox 0.8.107.0 使用完整验收配置时反复丢失远程连接，没有生成客体证据；最小配置和仅映射配置可以进入桌面。关闭虚拟 GPU、简化命令和临时客体启动快捷方式均未取得验收结果。那轮放下 Sandbox，改为上述本机测试，不推断故障根因。

2026-10-06 重启后恢复了 Sandbox 0.8.107.0 应用／CLI。明确配置 `<vGPU>Disable</vGPU>` 后桌面成功连接；官方 CLI 执行以 0 返回，写入 `target/sandbox-repair-20261005/post-reboot-7f8c917e9a4545b7a12516067d7feb1d/output/marker.json`。该客体标记记录交互式 `WDAGUtilityAccount` 管理员会话、内置 PowerShell 5.1、没有 .NET SDK，以及通过的 UIA／辅助检查，`productionInstallerExecuted=false`。受保护的验收脚本回归门禁通过 **40 项夹具检查**。这证明诊断客体执行，不代表生产 Setup 验收或标准用户通过；对应的完整客体证据才能关闭干净客户端门槛，普通 Windows 虚拟机或独立测试电脑也可提供该证据。

**2026-10-06 尚未完成的生产客体记录：**首次验收在 Setup 前停止，因为过宽运行库保护拒绝了系统自带 CBS 包。修正有界分类／模块来源检查后，验收脚本门禁通过 **73 项夹具检查**。后续全新客体的 `target/winui/clean-windows-72e32494652c4e4ea206e1fdee5b6737/evidence/evidence.json` 核验公开安装器，生产 `0.2.4` 基线安装以 0 退出，随后通过正常已安装启动器打开 Manager；进程记录确认 .NET 与 XAML 模块均来自自己的载荷。该运行随后**未通过**手动 AppID 对话框断言，仅凭这份记录尚不能确定具体原因；不宣称完整配置、修复／升级／卸载或干净客户端整体通过。客体离线、无外部 SDK／运行库，使用构建 26100 的 Sandbox 管理员账户，没有测试公网更新或真实 Steam／游戏。

后续 `target/winui/clean-windows-19b22e0eb1884c98ae5a4a79d4ad4e90/evidence/evidence.json` 保留准确的中文按钮名称，以及已验证 Manager 窗口（PID 1900）内 UIA provider 的 PID 0。测试工具此前要求子 provider PID 必须等于 Manager PID，因此拒绝了名称正确且来自该窗口的控件。这份诊断指出需要修正的测试工具检查，不证明生产 AppID 流程有缺陷，也不代表验收整体通过。

**2026-10-06 Runner 运行库缺陷与修复：**全新无 SDK 客体没有 `C:\Windows\System32\VCRUNTIME140.dll` 或 `VCRUNTIME140_1.dll`。冻结的公开 `0.2.5` Runner（SHA-256 `a6f56ba7af7ca63adeea7516bcaa1294145aa8b3b1ca5da06e02e6735fda7f9d`）执行 `--help` 时加载失败，退出 `0xC0000135`；修正为静态链接的 `0.2.6` Runner（SHA-256 `685ad18f2b63689d7ef8ab40b7fadbdacf75de8242687b37f0000da69f1a4f97`）在同一客体以 0 退出。证据为 `target/winui/runner-clean-runtime-d78c0499091c4609bbfa5f5c649eee78/evidence/loader-ab.json`，记录 `productInstallerExecuted=false`、`gameFilesTouched=false`。这是真实干净客体加载证据，不代表候选 Setup 或完整配置／升级／卸载通过。

修复在 `.cargo/config.toml` 中仅为 Windows MSVC 目标启用 `+crt-static`。`Test-RunnerDependencies.ps1` 使用官方 MSVC `dumpbin` 检查实际常规／延迟加载 DLL 依赖及 x64／GUI PE 身份，拒绝独立 Visual C++ redistributable 依赖，允许 Windows 11 自带 DLL；它通过 `Test-RunnerSigningMetadata.ps1` 执行，也在 `Invoke-WinUI.ps1` 暂存 Runner 与清单前执行。修改后 `mise exec -- cargo test --locked -p steamwrapper-runner` 通过**六项真实 Rust Runner 进程测试**，这是进程回归，不是六项打包安装器检查。验收工具先通过 **95 项夹具检查**，加入候选输入及 Windows 文件名大小写回归后再通过 **125/125**。上方此前真实 `0.2.5 → 0.2.6` 安装器结果早于这次 Runner 载荷变化，继续按日期保留；修正载荷后续通过下方单独的重复隔离安装器门禁。`0.2.6` 仍为未发布候选，完整干净客户端生命周期、普通用户、多种 DPI／输入法及公开发布／下载门槛仍未完成。

**静态载荷重复安装器记录（2026-10-06）：**修改 Runner 链接后，冻结 `0.2.5` → 修正为静态链接的 `0.2.6` 载荷再次通过 **13 个符合预期的隔离安装器／maintenance 结果**，证据为 `target/winui/installer acceptance 中文 ' 9b6fb41052a44fc783e239c7315ff398/evidence.json`。实际回滚保留 1,204 个自有版本文件哈希及维护程序／卸载器／快捷方式，六个数据夹具均未变；证据记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`cleanVm=false`。修正 Runner 的跨语言契约再次通过，输出位于 `target/winui-contracts/04438575229b451dbd30d7d3b5745580/results`。这是宿主的实际隔离安装器与进程／契约结果，不是全新客体中的生产候选 Setup 安装。

**候选首次安装生命周期通过（2026-10-06）：**`target/winui/clean-windows-93d7747c15bc4c7f93370eb953cabf13/evidence/evidence.json` 记录 **14 个步骤通过**，宿主 `ReadEvidence` 保护核验通过，客体以 0 退出。实际使用生产安装身份、非隔离的 `0.2.6` Setup 为 49,937,618 字节，SHA-256 `26ebacd4a41eda4e6609f034ebbef2c7f381951f5af5ae106bd94c0f756aec16`。它在全新离线、构建 26100 的 Sandbox 安装；客体没有 SDK、系统 .NET、外部安装的 Windows App Runtime 或两项 System32 VC 运行库 DLL，系统自带 CBS 组件记录并保留。

实际中文原生 UI 保存 AppID `487`，生成准确的稳定 Runner 启动项，并安装通过哈希验证的 Runner。关闭 Manager 后，Runner 完成无害夹具并以 0 退出。修复、默认卸载、卸载后独立 Runner、自定义中文目录重装、重新打开后的配置可见、迁移后的 Runner 及最终卸载均通过；Manager 在两个位置都从自己的 `0.2.6` 载荷加载 `coreclr.dll` 和 `Microsoft.UI.Xaml.dll`。配置／Runner／清单三个准确哈希保留；最终移除核验自有程序版本、快捷方式和注册已删除，无害夹具未变。

这是已通过的**本地未发布 `CandidateFirstInstall`** 生命周期，`unpublishedCandidate=true`、`workingCopyDirty=true`、`numericUpgradeTested=false`、`publicSevenAssetsTested=false`。账户是具有管理员身份的 `WDAGUtilityAccount`，不是普通账户或独立 ISO 虚拟机；不代表干净真实数字版本升级、便携版、多种 DPI／中文输入法、公开下载／公网更新或真实 Steam／游戏验收完成。先前一次 Sandbox 断连提示经明确重新连接恢复；产品路径通过不保证 Sandbox 本身可靠。整体 W2／稳定门槛及公开发布仍独立保留。

**公开基线 → 本地候选的干净升级（2026-10-06）：**明确的 `CandidateUpgrade` 路径在全新离线构建 26100 客体通过 **18 步**，`ReadEvidence` 核验通过。在上述候选准备命令中加入 `-BaselineTag v0.2.5-preview.1` 即选择该路径；基线独立核验公开七附件与准确提交。证据为 `target/winui/clean-windows-9b0667b94cd946d2805377067870a21b/evidence/evidence.json`。基线 Setup 哈希为 `0cd78a00070d4e40eeb1f376a98b94f0b3febb82a3357be3b6b0b35555ae57da`，目标为上方同一个 `26ebacd4…` 候选。真实安装／修复／升级、原生界面复用配置、配置／偏好字节不变、上一版本保留、默认卸载及自定义目录重装均通过。保存保留的配置后安装实际更新的静态 Runner，生成的启动项不变；关闭 Manager 后，三次无害 Runner 启动均以 0 退出。

该升级路径明确**未运行**历史基线 Runner：其加载缺陷保留在上方记录，`baselineRunnerOperationalTested=false`。通过结果证明 `numericUpgradeTested=true`、`stableRunnerUpdated=true`，不代表旧 Runner 可用、目标已公开发布、普通账户或联网更新接力通过。输入保留准确的公开基线描述符／API 哈希和本地候选来源；聚焦回归拒绝相同／更高数字版本基线及不符合范围的证据。

**干净便携候选（2026-10-06，DPI 布局修改之前）：**实际 schema 1 五附件 ZIP 通过 **10 步**，证据为 `target/winui/portable-client-8c6b61d0557c4fb7891fea190f5f09cb/evidence/evidence.json`。ZIP SHA-256 为 `4766f2d7ffc1d97043bd0bd90c12658049f68827cbfca4394724a0dcac23a309`。603 个载荷文件全部核验，解压到全新离线、构建 26100 且无需准备 SDK／运行库的客体中文目录。原生配置保存、共享稳定 Runner 安装、两次正常 Manager 退出及两次独立 Runner 退出均通过。实际 NativeAOT 安装辅助程序拒绝占用的便携目录，退出码 11，全部载荷／数据哈希未变。关闭后移动 Manager 目录，配置和 Runner 仍可用。未运行 Setup、Steam 或操作游戏文件；不证明安装版转便携版、普通账户或公开发行验收。载荷变化后须重新验收，不能复用本记录。

**普通账户的环境阻塞（2026-10-06）：**仅客体可运行的控制器在全新构建 26100 Sandbox 创建了真正的本地普通账户；直接令牌读取确认子进程属于新 SID、Medium 完整性、未提升且完全没有 Administrators 组，不是过滤后的管理员。子进程未进入 PowerShell 诊断：控制器等待超时，Windows Application Popup 事件 26 记录 `0xC0000142`。证据位于 `target/winui/clean-windows-9175aa168e2840da94d21ba8ef9ecb9c/evidence/`，包含 `standard-controller.json`、`standard-child-token.json`、`standard-startup-events.json` 与 `standard-observation.json`。不把事件代码当作已观察的进程退出码，也不据此确定某个 DLL／桌面原因；未执行生产 Setup，没有普通账户完整生命周期通过。桌面／映射 ACL、UAC 和机器策略未变；官方停止 Sandbox 后临时账户随客体销毁。完整普通账户验收仍受阻，等待可用的独立会话。

**DPI 修复后的最终载荷（2026-10-06）：**`target/winui/installers/client-final2-v0.2.6/` 中的新封存 Setup 为 49,925,609 字节，SHA-256 `9c2b1a7424f9f3157f4705d25f8dc78c54a8682c2e57065600d19408890b8ac9`。在 `target/winui/clean-windows-441fc7b4a6044012bb8bb77eba19cf8c/evidence/evidence.json` 再次通过完整 **18 步 CandidateUpgrade**，客体退出码 0，宿主 `ReadEvidence` 匹配核验通过。Manager 与 Runner 各三次正常退出且退出码 0；客体没有 SDK／准备过的运行库或两项 System32 VC DLL。配置／偏好字节、有效的稳定启动项、上一版本保留及默认卸载的数据保留均通过。实际更新的静态 Runner 哈希为 `02cc236966d34fbcd3d038486f2196913055b4ed18fa768ffe5fadde82c1f3de`。本路径仍未运行有已知问题的基线 Runner。

`target/winui/releases/client-final2-v0.2.6/` 的最终 ZIP 为 73,813,972 字节，SHA-256 `85eb556835aeb768d4b93bfdabe21ad377f6e921c76036e0a0cadadc0ef00e5d`。使用最终窗口代码及修正后的共享辅助函数依赖，另行重复通过全部 **10 步便携验收**，证据为 `target/winui/portable-final2-c2ffc44039ed495b95afc28a008806c3/evidence/evidence.json`。603 个载荷文件、两次正常 Manager 退出及两次 Runner 退出均通过。本轮最终结果取代此前候选字节，但仍明确记录 `unpublishedCandidate=true`、未提交源码来源、构建 26100 的管理员 Sandbox；不代表目标公开发布／联网更新／普通账户／ISO 或真实 Steam／游戏验收。中间封存包保留，没有覆盖。

**原生 DPI 与中文输入（2026-10-06）：**真实微软拼音候选组合提交了名称 `测试`；Escape 取消后续组合并保留已提交文字，原生保存与准确的保存前备份逐字比较，仅改变预期名称。中文语言偏好与未知设置在正常重启后保留。人工证据为 `target/winui/native-ui/中文 空格 ' a7c534dc20944c3db817dcc88236145d/manual-ime-evidence.json`；这与工具使用 Unicode setter／HWND 键盘消息的证据分开。

实际 200% 冷启动窗口原先仍固定为 1160 × 900 物理像素，界面明显受挤压。初始放置修复后，最终 Manager DLL SHA-256 `7fa74fbfb34c1178d6589ed66f57f0e3e2e18764238e7372ada0b70542fc003b` 实测为 **96／144／192 DPI**，对应物理尺寸 **1160 × 900／1740 × 1350／2320 × 1344**，所有边缘都在真实活动工作区内。记录为 `target/winui/window-metrics-final-{100,150,200}-cold.json` 及 `target/winui/final-native-dpi-evidence.json`。宿主“设置”中确认已还原 **125%**；键盘布局保持中文，未切换输入语言／模式，没有停止用户／游戏进程。纯函数红／绿回归先复现固定物理像素缺陷，再复现显示器相对坐标错误，最终 **28 项通过**；多屏硬件及每一种对话框／语言／DPI 组合仍属独立验收。

还原宿主后，最终产物通过默认原生工具的英中双语 **16 项用例**，覆盖语言持久化、冲突、取消、选择器、封面占位、保存及聚焦键盘／更新路径。证据为 `target/winui/native-ui/中文 空格 ' c987f88c13644090895b2cbc8eef4c13/evidence.json`，全部夹具 Manager 正常关闭。必需 C# 门禁通过 **178 项 Application、37 项 Windows、160 项 Deployment**，另有一项有条件的跨盘跳过；跨语言 Runner 契约也通过。这些结果不消除普通账户阻塞，也不代表稳定版／公开更新完整验收完成。

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

`v2-ci.yml` 定义 Windows / Ubuntu 的 Rust core/Runner 格式／检查／测试门禁及平台进程测试。`winui-windows.yml` 在拉取请求与 `main` 中运行 C# Application 和 Windows 解码器测试、C# / Rust 契约、实际 WinUI 编译及原生 UI 工具的仅编译门禁；不在托管服务会话执行 UIA。日常 CI 还使用一次性文件／API fixture 运行发布替换、发布包安全和 mock GitHub/CNB 发布器测试，不向外部 Release 写入。它上传测试证据，不生成应用包。

`winui-release.yml` 在版本标签或明确请求的手动预览中重新执行完整门禁，再发布自包含应用，运行全部发布／恢复回归并检查完整布局。版本标签运行先验证源码／标签／版本和双语说明，再生成明确的 schema 2 包：Setup、portable ZIP、两份本地化说明、旧 portable 描述符、安装版描述符及校验和。纯版本标签发布稳定版，预发布后缀发布预览版；稳定发布把两个签名更新源推进到同一个新安装包。手动运行只上传预览产物。发布边界和可选 CNB 镜像见[发布准备](/SteamWrapper/zh-cn/development/distribution/)。

旧 Dioxus Native E2E、AppImage job 与 NSIS release 链已移除。工作流声明不等于最新运行通过，须另行核验；手动发布工作流预览运行真实隔离安装器进程，本地原生 UI 自动化现有首个回归切片。完整原生验收、干净客户端交付和启用更新后的验收仍属于路线图。

## 限制

- C# 服务/契约和发布检查不能证明原生 UI、可访问性或干净 Windows 安装；原生 UI 工具仅证明在交互桌面实际执行的夹具用例，不等于整个 W1 门槛通过。
- 常规自动化不操作真实 Steam；真实验收需要授权、记录原启动项、保护存档、校验文件并恢复。一键应用/恢复 Launch Options 仍是后续功能。
- Runner 进程 fixture 仅证明对应平台和已测生命周期场景，不证明真实 Proton、breakaway、Unix daemonize/新 session 或 Steam Deck 兼容性。
- 当前预览包含完整的 Windows 自包含目录和单独的未签名安装器；隔离安装／卸载测试不能证明干净 Windows VM、原生向导或经过认证的更新验收。
- 上述 2026-09-07–09-08 Dioxus 记录是归档历史结果，不是当前 WinUI 证据。
