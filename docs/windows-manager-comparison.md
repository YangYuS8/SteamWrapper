# Windows Manager 实测比较

日期：2026-09-07。初始比较针对提交 `31a609df027e54bf97156f7698d4a420bc7e3c71` 之上的当时工作区：Dioxus 0.7.10/Rust Manager 与首个 WinUI 3/C# Manager。后续组件精简及发布保护单独记录；历史运行数据不代表新产物的复测结果，也不是两个框架的一般性能排名。

建议继续 **WinUI 3 + C# 配置服务 + 独立 Rust Runner**，以 Windows 首版为目标。配置一次后关闭 Manager、从 Steam 日常启动的产品定位，意味着配置可靠性、Windows 操作体验和交付稳定性比 Manager 常驻性能更重要。现阶段保留 Dioxus 基线和已有 CI，待安装、更新及真实 Steam 验收完成再切换默认发布。

## 功能与兼容性

初始功能比较阶段重新运行了以下检查：

| 检查 | 本轮结果 | 证据范围 |
| --- | --- | --- |
| `mise.exe run winui:test` | 34/34 通过 | C# 配置、服务、文件保护等 |
| `mise.exe run winui:contracts` | 通过 | Rust 历史配置 → C# 单字段编辑 → Rust 完整语义检查；实际 Rust Runner 的 argv/cwd、job/root 等待差别、退出码与错误日志 |
| `mise.exe run windows:rust-test` | 33 通过，1 默认忽略 | 忽略的跨语言用例已由上一项单独执行通过；其中 7 项为源码字符串检查，不算原生 UI 证据 |
| Dioxus Native E2E | 3 个 spec、6 项通过 | 扫描、配置保存、启动项文本与稳定 Runner 安装；未执行所配置目标 |
| WinUI 原生操作补测 | 通过 | 其他平台配置只读；中文改名后保存，除名称外文件逐字保持，包含空/多行参数、未知字段、别名键、省略的 `wait_mode`；生成 1 份备份并安装稳定 Runner |

Dioxus 第一次 E2E 使用了被 workspace 测试覆盖的普通二进制，缺少 `e2e` feature；重新构建正确产物后通过。该次前置产物错误不作为产品崩溃记录。后续运行 E2E 应先构建带 `e2e` feature 的二进制，避免共享 `target/debug` 产物互相覆盖。

另用同一份包含高级字段、中文、空格、引号、反斜杠、空/多行参数和未知表的合成配置，调用两套**真实服务源码**，仅要求修改目标程序。结果揭示了常规回归尚未覆盖的差异：

| 同输入探针 | 当前 Dioxus/Rust 服务 | 当前 WinUI/C# 服务 |
| --- | --- | --- |
| 只修改 `target` | 清空 6 项参数、工作目录改为 `.`、等待模式改为 `job`、进程名清空 | 仅目标字段一行改变，其他文本逐字保留 |
| 未知顶层/嵌套内容 | 探针中的 5 类均丢失 | 全部保留 |
| 保存备份 | 0 份 | 1 份 |
| 未支持的 `version = 3` | 仍允许保存 | 拒绝写入，原文件字节不变 |
| 稳定 Runner 为较新兼容版本、随包版本较旧 | 按摘要差异替换为随包旧内容 | 保留较新兼容版本 |

Runner 版本探针用带摘要/版本清单的合成文件表示 `0.3.0` 与 `0.2.0`，没有启动这些合成文件，也不表示产品已发布这些版本。实际可执行 Runner 的行为由跨语言门禁另行验证。

这些是服务实现差异。旧版 [保存服务](../crates/manager-core/src/lib.rs)重建 Profile，[配置序列化](../crates/core/src/config.rs)重新生成整个文件；[Runner 安装](../crates/manager-core/src/runner.rs)按摘要判断替换。Dioxus 可以修复这些行为，不能把问题归因于 WebView 或 Rust。C# 方案的保护来自新实现及测试，也不能因使用 WinUI 就省略验证。

## 依赖精简前的资源测量

使用 [比较脚本](../scripts/windows/Measure-ManagerComparison.ps1)，在两端完成构建及功能测试、测试窗口退出后顺序测量。两端使用相同隔离目录中的 10 条配置、10 个 Steam manifest、本地封面和同一个 release Runner，不操作真实 Steam 库。

本机为 Windows build 26200、i7-12700H（20 逻辑处理器）、系统可见物理内存 31.62 GiB；Dioxus 子进程使用 WebView2 145.0.3800.97。资源测量使用当日先前已构建的 release 产物，本脚本没有重建；二进制 SHA-256、时间戳及机器信息保存在 `metadata.json`，工作区提交号不单独证明二进制与未提交源码对应。

每端预热 1 次，再各运行 6 次；配对内先后顺序随机且平衡。主窗口句柄出现后等待 5 秒，于第 5/6/7 秒采集完整进程树。Dioxus 包含其 WebView2 子进程，不把机器上其他 Edge/Codex 进程算入。

| 指标 | 精简前 WinUI / C# | Dioxus / Rust |
| --- | --- | --- |
| 未压缩应用目录，含同一 Runner | 226.23 MiB / 522 个文件 | 6.87 MiB / 4 个文件，另依赖系统 WebView2 |
| 完整进程树空闲私有字节，中位数 | 83.02 MiB | 267.91 MiB |
| 工作集相加，中位数 | 158.93 MiB | 461.73 MiB |
| 空闲进程数，中位数 | 1 | 7，包含 WebView2 子进程 |
| 主窗口句柄出现，中位数 | 339.82 ms | 26.48 ms |
| 主窗口句柄出现，最小–最大 | 324.35–352.88 ms | 24.99–28.84 ms |

两端各 6 次正式测量全部完成；14 次启动/退出（含预热）均正常，夹具配置 SHA-256 始终未变。EXE 均为 GUI 子系统，因此没有把控制台窗口算作主窗口。上述启动数字仍仅是窗口创建代理。

解释限制：

- 窗口句柄出现时间仅表示窗口创建，轮询间隔 10 ms；没有测首帧或可交互时间，不能称为界面加载速度。
- 私有字节表示进程私有分配，非实际驻留物理内存；工作集相加可能重复计算共享页。
- 两端默认页面与窗口尺寸不同。这是现有产品的启动与空闲测量，并非功能/布局相同的框架实验。
- 本机已预热，有系统和其他应用背景活动；未清空系统缓存、未测冷启动或干净 VM。
- 文件大小为未压缩应用目录、包含同一 Runner。Dioxus 不包含系统共享 WebView2，WinUI 包含 .NET 与 Windows App SDK，不能直接把目录比值解释为总安装成本比值。

## 后续组件精简与发布验证

Manager 已使用 Windows App SDK 2.4.0 对应的组件集：直接引用 `Microsoft.WindowsAppSDK.WinUI` 2.3.6 与 `Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6，保留 SDK.BuildTools 10.0.26100.7705。显式固定 InteractiveExperiences 防止回落到 WinUI 包的最低依赖 2.1.3。所有保留依赖的版本和摘要与原锁文件一致；这是按需组件引用，没有手动删除发布 DLL。组件包及其自包含模式由微软支持。[官方组件包说明](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003)

| 发布布局检查 | 原总包产物 | 最终组件产物 |
| --- | --- | --- |
| 未压缩目录 | 237,216,420 字节 / 226.23 MiB | 179,511,987 字节 / 171.196 MiB |
| 文件数 | 522 | 457 |
| 未使用的 AI/ML/Search/Widgets/DWrite 文件 | 包含 | 不再进入发布目录，共少 65 个文件 |

原生资源索引、.NET、WinUI、picker 投影、Runner 和清单均存在；Runner 摘要匹配，三种 Storage.Pickers 激活注册仍指向随包 `Microsoft.WindowsAppRuntime.dll`。locked restore 和 Release self-contained publish 通过。最终产物另行通过了沙盒原生窗口、配置读取、picker 打开/取消、保存和稳定 Runner 就绪复核，见[预览验收](winui-preview-validation.md)。**没有重测上述 6 轮内存或启动指标。**

发布现在先写入全新暂存目录，校验后替换 `target/winui/publish`。回归先观察到旧脚本保留唯一哨兵文件的失败，再验证 5 项全部通过：真实发布清除旧文件、缺失资源保留旧版、锁住候选时回滚、成功替换仅含新文件、越界路径拒绝。目录操作限制在本仓库 `target/winui`；运行中的预览会阻止替换，失败候选保留用于排查。普通错误回滚已验证，目录重命名不构成断电事务。

## 方案选择

WinUI 的理由首先是 Windows 优先的范围与原生配置界面。Microsoft 将 WinUI 3 定位为 C#/C++、XAML 的 Windows 原生桌面框架；Dioxus Desktop 则由原生 Rust 代码配合系统 WebView 渲染。两条路线都能调用 Windows API，使用 Dioxus 并不自动增加 Node 运行时。[WinUI 官方说明](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)、[Dioxus Desktop 官方说明](https://dioxuslabs.com/learn/0.7/guides/platforms/desktop/)

目前 C# 配置服务已达到更完整的保真和写入保护要求，并已通过真实 Rust Runner 消费测试。继续完成该方案比回头补齐旧管理链更符合已确定的 Windows 方向。双语言契约是持续维护成本，应保留跨语言门禁；本轮没有证据表明需要再加 Rust FFI/helper 或重写 Runner。

WinUI 的主要代价是自包含依赖体积，以及 Windows 特定的构建与交付。后续组件精简已移除原目录中的 ONNX、DirectML 等未使用依赖，最终仍为 171.196 MiB；这一包体改善不能推断启动或内存改善。Dioxus 对恢复 Linux/SteamOS 优先级、复用 Rust 管理模型和较小的应用自带文件仍有价值。

两端共用独立 Rust Runner。更换 Manager 不会直接提高 Steam 时长记录、Job 等待或游戏兼容性；这些必须继续在 Runner 与实际 Steam 上验证。

下一步应完成 WinUI 的干净 Windows 11 安装/更新/卸载、缩放/键盘/中文 IME/屏幕阅读器，以及真实 Steam 启动和退出验收。当前结果足以支持技术路线，尚不足以宣布 Windows 正式版可发布。完整未完成项见 [预览验收](winui-preview-validation.md)。

## 复查入口与本机证据

```powershell
mise.exe run winui:test
mise.exe run winui:contracts
mise.exe run windows:rust-test
# 真实发布与 4 项独立目录保护检查，共 5 项：
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
# Dioxus Native E2E 按 testing.md 先构建 --features e2e，再运行 pnpm 测试。
# 两端 release 产物就绪且其他测试结束后，可生成一组新的资源结果：
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Measure-ManagerComparison.ps1
```

- 功能门禁：`target/comparison-gates-eb091a2741314f3299d7c10db775b534/README.md` 与其日志。
- 跨语言及真实 Runner：`target/winui-contracts/67f27c0007cc4229af7e2407d15efe4b/results`。
- 同输入服务探针：`target/comparison-config/evidence/observations.json`、`rust-result.json`、`csharp-result.json` 和双方保存文件；临时探针源码在 `target/comparison-config`。
- 原生单字段保存：`target/ui-comparison-5523059ad7ac4b60a91e86f7ee931cee/before.toml`、`ui-result.json` 和隔离保存文件。
- 资源测量：`target/manager-comparison/e9cb1333d8c64656b25f50e9536779a0`。
- 最终组件发布：`target/winui-component-study/integrated-publish.json`；发布回归：同目录下 `publish-regression-before.log`、`publish-regression-after.log`。

`target` 证据为本机临时产物，不进入提交。报告、资源测量脚本和发布回归脚本保留在仓库中。干净 Windows 11 安装及真实 Steam 时长验收仍未完成。
