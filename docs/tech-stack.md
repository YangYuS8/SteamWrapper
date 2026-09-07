# SteamWrapper v2 技术栈

## 目标方案

采用 **C# / XAML WinUI 3 Manager + C# 应用服务 + 独立 Rust Runner**，先做好 Windows。详见 [产品与架构重设计](windows-v2-design.md)及 [WinUI 技术评估](winui3-assessment.md)。WinUI 配置预览已实现并可自包含构建；Dioxus 0.7.10 及其发布链保留，尚未通过完整 Windows 替换门槛。

| 部分 | 目标选择 | 原因与约束 |
| --- | --- | --- |
| Manager UI | WinUI 3、C#、XAML | Windows 原生窗口、输入、文件选择与可访问性；中文优先 |
| Manager 服务 | 小型、可独立测试的 C# 应用服务 | 管理配置、Steam 发现、Runner 安装与日志；不调用 Rust FFI，不设后台 helper |
| 日常运行 | 独立 Rust Runner | 保持现有 CLI 和进程控制边界，Manager 不参与正常游戏启动 |
| 持久配置 | 现有 profiles.toml v2 | C# 实现同一协议；必须通过读改写、未知数据保护与实际 Rust 消费验证 |
| 封面 | WinUI 首版仅读取本地缓存 | 缺失时占位，配置/启动不依赖网络 |
| 发布 | unpackaged 自包含目录 + 每用户安装器 | 携带 .NET/Windows App SDK，玩家无需准备运行时；Runner 安装到稳定用户路径 |
| 平台 | 首先验证受支持的 Windows 11 x64 | Windows 10、ARM64、Linux/SteamOS 新功能另评估，不提前承诺 |

现有 Rust 管理层的存在不要求新 UI 加一层 ABI。C# TOML 使用固定版本 Tomlyn 2.10.1 读取语法树并按跨度修改字段，其他源码原样保留；仅生成 Rust 可读的 TOML 1.0 字符串子集，不使用 TOML 1.1 全模型序列化。字段、默认值、旧别名键、路径和参数由已通过的跨语言/真实 Runner 契约约束。[Tomlyn 包](https://www.nuget.org/packages/Tomlyn/2.10.1)、[低层语法接口](https://github.com/xoofx/Tomlyn/blob/2.10.1/site/docs/low-level.md)

不为语言统一同时重写 Runner。C# NativeAOT 是可行备选，若将来考虑，应先证明完整 CLI/TOML 和 Windows 进程行为，再比较实际包体、性能与维护成本。[NativeAOT 官方说明](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

## 当前仓库布局

```text
crates/core                 # Rust TOML、Steam、封面、Launch Options
crates/manager-core         # 现有 Dioxus 使用的 Manager service
crates/runner               # Steam 调用的原生无界面运行器
apps/manager-dioxus         # Dioxus 0.7.10 Desktop Manager
apps/manager-dioxus/e2e     # WDIO Native E2E，仅测试工具
apps/manager-winui         # WinUI UI、C# Application 和 MSTest 测试
tests/contracts           # C# / Rust 共享契约和测试驱动
tests/fixtures            # 真实 Runner 消费的受控进程，仅测试
```

迁移期间保留现有代码和 CI；WinUI 达到配置、运行与交付门槛后再切换默认 Manager，并按实际调用关系清理旧管理层。

### Rust 核心与服务

`steamwrapper-core` 定义现有 Profile/TOML、Steam 扫描、封面 URL 和 Launch Options；不依赖 UI 或平台进程 API。Runner 继续依赖 core 的配置与路径语义。

`steamwrapper-manager-core` 组合稳定路径、保存/列表、Steam 扫描、日志及 Runner 安装/修复，是 Dioxus 直接调用的 Rust API。该链不引入第二套 Rust Profile，也不改成 IPC server；其“全 Rust 管理服务”边界不约束新的 C# 服务实现。

当前 profile 保存会重建高级字段，core 直接写配置文件；不能把这些行为复制成新 Manager 的设计要求。兼容的是玩家配置的含义，不是保留覆盖数据的缺陷。

### Runner

`steamwrapper-runner` 使用 `clap`、`anyhow`、`tracing` 和 `steamwrapper-core`，独立启动 profile 的 target/args 并按模式等待。它不依赖 GUI、WebView 或 .NET，不常驻后台。

新 Windows 配置默认 Job Object，Linux 新配置默认 POSIX process group；旧 TOML 省略 wait_mode 时为 root。当前 `%command%` 仅接收和记录，未自动执行/转发；Proton 包装尚未完成。Runner 生命周期测试与真实 Steam 状态/时长验收是不同证据。

### 当前 Dioxus Manager

- Dioxus `0.7.10` + desktop feature、RSX 和本地 CSS；版本/API 修改先核验官方文档。
- UI 经 `src/services.rs` 直接调用 manager-core，无伪 Tauri IPC。
- 当前封面本地优先、AppID Steam CDN 回退；新 WinUI 本地封面目标不代表当前网络代码已改。
- `Dioxus.toml` 管理图标、metadata 与 Runner resources；构建前 stage 当前平台 Runner。
- `@wdio/dioxus-service` 1.0.0 embedded provider、`wdio-dioxus-embedded-driver` 1.0.0 仅用于 e2e feature；release 不带测试 bridge。
- pnpm 仅用于 Native E2E，不作为 UI 产品运行时。

具体流程见 [Dioxus 技能](../skills/dioxus-manager/SKILL.md)。新 WinUI 不使用该技能的 DOM/RSX 或 bundle 步骤。

## 工具链与交付

项目工具由 mise 管理，.NET SDK 10.0.400、Rust 1.98.1；本机重启后 MSVC/SDK 已复检。Manager 使用 Windows App SDK 2.4.0 对应的组件集：直接固定 `Microsoft.WindowsAppSDK.WinUI` 2.3.6、`Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6 与 SDK.BuildTools 10.0.26100.7705。组件包版本不等于框架名称中的“WinUI 3”；显式固定 InteractiveExperiences 避免回落到 WinUI 包的最低依赖 2.1.3。保留依赖的版本和摘要与原 2.4.0 总包锁文件一致。

按需组件引用是 Windows App SDK 官方支持的自包含部署方式。Manager 不引用未使用的 AI、ML、Search、Widgets 和 DWrite 组件，也不通过手动删除发布 DLL 精简。精简后目录约 171 MiB（457 文件，未压缩），最新产物字节数见[预览验收](winui-preview-validation.md)；原 226.23 MiB 版本的启动/内存基准仍作为历史结果保留，精简后未重测这些指标。[官方组件包说明](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003)、[本机比较与发布验证](windows-manager-comparison.md)

目标仍为 Windows 11 24H2（26100）x64，自包含且关闭 trimming。服务使用 net10.0、测试使用 MSTest 4.4.0 / Test SDK 18.9.0，各项目有 NuGet 锁文件。Manager 项目直接维护，无需 alpha 模板或 WinApp MSIX 调试身份包。发布先生成全新目录并校验，再替换旧产物，防止旧依赖残留；命令、五项发布回归及未完成的原生/干净系统验收见 [Windows 开发环境](windows-development.md)。

现有 Dioxus 构建使用 `dx check`、`dx build --release` 和 NSIS/AppImage bundle；Runner 名称为 Windows `SteamWrapperRunner.exe`、Linux `steamwrapper-runner`。这些命令只对应现有实现，不能证明 WinUI 安装器正确。[测试](testing.md)和 [分发](distribution.md)分别记录当前命令与目标验收。

## 不选的方向

本轮不恢复已移除的 Tauri/React，不引入 Electron、Node UI runtime 或 Python 产品组件。也不因全 Rust、通用跨平台或追求单 EXE，放大 Windows 配置工具的首发范围。

C ABI、管理 helper、全 C# Runner、MSIX 各有适用条件，保留在技术评估中；当前选择只解决实际需要的 UI、配置安全和独立游戏生命周期边界。
