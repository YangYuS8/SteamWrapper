# WinUI 3 迁移技术评估

[English](winui3-assessment.md) | 简体中文

核验日期：2026-09-07。本文件记录实施前的技术依据、备选和环境限制。随后已按 [Windows v2 产品与架构](windows-v2-design.zh-CN.md)实现首个配置预览；最新实现与验证状态见 [预览验收](winui-preview-validation.zh-CN.md)，新安装器仍未完成。

实施后的同输入服务、功能门禁与资源结果见 [Windows Manager 实测比较](windows-manager-comparison.zh-CN.md)；框架取舍应结合这些实际结果及其测量边界。

## 建议与取舍

采用 **C# + XAML WinUI 3 Manager，C# 应用服务，独立 Rust Runner**。两者通过现有 TOML、稳定路径和 CLI 配合。撤回初次评估中“保留 manager-core 并新增 manager-ffi”的默认建议：当前 Windows 配置工具没有必须共享进程内 Rust 管理层的需求，增加 ABI 的收益不足以抵消额外边界。

WinUI 3 是 Microsoft 的 Windows 原生 UI 框架，官方支持 C# 与 C++，可运行于 Windows 10 1809/build 17763 起；项目先验证受支持的 Windows 11 x64。框架最低版本不是本产品支持承诺。[WinUI 3 概述](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)、[平台语言支持](https://learn.microsoft.com/en-us/windows/apps/develop/platform/)

| 路线 | 本项目决定与代价 |
| --- | --- |
| C# WinUI + C# 配置服务 + Rust Runner | 采用；Windows 配置与游戏生命周期保持独立。代价是同一 TOML 协议的双语言实现，必须以真实读改写和 Runner 消费测试控制 |
| C# WinUI + Rust manager-core / C ABI | 暂不采用；节省部分移植，却新增编码、缓冲区释放、错误/panic、DLL 架构与发布兼容。若近期需要两种 GUI 共享成熟管理逻辑，再重新评估 |
| 全 C#，Runner NativeAOT | 技术可行；可能统一工具栈，但需同时重做 Windows 进程控制和兼容验证，不与本次 UI 替换绑定 |
| C# WinUI + Rust 管理 helper CLI | 可以隔离进程故障，但增加第三个程序、协议、取消/超时和版本同步；当前文件管理场景收益不足 |
| C++/WinRT 或 Rust 直接做 WinUI | C++ 属于官方支持路线；当前仓库无可复用 C++ GUI。Rust 路线需承担更多语言投影/工具链工作，首版不选 |

ABI 成本依据 [Microsoft 原生互操作指南](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)。[NativeAOT](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/) 能生成无需预装 .NET 的原生程序，但需要处理 trimming、依赖兼容和平台构建工具；不能以“C# 必须让玩家安装运行时”排除它。表中架构取舍是结合本项目的工程判断，不是框架性能排名。

## 当前代码与迁移风险

| 现有部分 | 迁移处理 |
| --- | --- |
| [Profile/TOML](../crates/core/src/config.rs)、[字段与默认值](../crates/core/src/profile.rs) | 作为既有兼容协议依据；C# 实现由跨语言往返和实际 Runner 解析验证 |
| [ManagerService](../crates/manager-core/src/lib.rs) | 只维护现有 Dioxus 管理链；不要求新 C# 应用调用它 |
| [Runner 安装](../crates/manager-core/src/runner.rs) | 摘要、临时文件、落盘、原子替换和失败保留可作为行为参考，C# 实现另做 Windows 验证 |
| [Steam 扫描](../crates/core/src/steam.rs) | 当前 Windows 主要检查环境变量和 Program Files；新实现需覆盖自定义位置和部分库读取失败，不能把现有 VDF 解析当成已验证的写入器 |
| [Windows Runner](../crates/runner/src/platform/windows.rs) | 保留挂起启动、Job Object 和等待代码；以真实进程和 Steam 验收约束，不迁入 GUI |
| [UI contract](../apps/manager-dioxus/tests/ui_contract.rs) | 字符串断言不能移作 WinUI 的原生交互、布局或可访问性证据 |

当前 `save_profile` 会重置高级字段，`config.save` 直接写文件；这说明复用 FFI 并不能自动获得无损保存。新方案要求只更新编辑字段、保护未知字段/版本、原子写入和冲突检测，见 [配置门槛](windows-v2-design.zh-CN.md#4-配置保真是第一个门槛)。旧配置缺失 `wait_mode` 解释为 `root`，新建 Windows 配置才显式设 `job`。

最初源码对照发现 [manager_service.rs](../crates/manager-core/tests/manager_service.rs) 的保存测试硬编码 `process_group`，而 Windows 路径选 `job`。工具链安装后已实际复现失败，随后修正为独立的平台期望值，保留其余格式断言；产品默认行为没有改变。现有 Manager 也没有一键写入/恢复 Steam Launch Options。

## 部署与稳定路径

首个目标采用 **unpackaged 目录 + .NET self-contained + Windows App SDK self-contained**，由每用户安装器包装。两个 self-contained 设置需分别配置并在干净系统验证；依赖仍占包体并需要随版本维护。[官方自包含部署](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager 与随包依赖/Runner 资源
%LOCALAPPDATA%\SteamWrapper\profiles.toml
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
"<stable-runner-path>" --appid "<appid>" -- %command%
```

没有 Rust bridge DLL。Manager 负责把 Runner 资源安全安装到稳定路径。更新、移动和卸载 Manager 都不能破坏已有启动项；删除 Runner 前须解除引用，无法确认时默认保留，详见 [安装与卸载](windows-v2-design.zh-CN.md#7-安装更新卸载)。

MSIX 留待后续评估包身份、manifest 运行模型与路径访问；不能直接改用 `ApplicationData.LocalFolder`，必须证明 Steam、Runner 与 Manager 读到同一份稳定数据。AppData 虚拟化取决于运行模型，不是所有 MSIX 均重定向。[MSIX 运行模型](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)

首版不承诺单文件 EXE：[部署总览](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)与自包含说明对单文件能力的表述并不完全一致，应以锁定版本的构建和干净系统运行结果为准。

## 工具链与当前机器

截至核验日，Microsoft stable 页面列出 Windows App SDK **2.4.0，2026-08-13 发布**。实施时锁定经过验证的 stable 包，不从旧教程照抄版本。[发布渠道与支持周期](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)

当前官方快速入门提供 Visual Studio 2026 + WinUI application development workload，以及 .NET 10 SDK CLI 模板路线。需匹配 Windows SDK，Rust MSVC 目标另外需要 C++ 工具链。[WinUI 快速入门](https://learn.microsoft.com/en-us/windows/apps/get-started/start-here)

最初调研时的本机检查结果（后续安装已推进，见下文）：

- `dotnet --info`：Host 10.0.11 x64，有 .NET/WindowsDesktop runtime，但 **No SDKs were found**。
- 标准路径未发现 `vswhere` / Windows Kits Include，`msbuild` 不在 PATH；不据此断言整台机器没有其他安装位置。
- 前轮按原 AGENTS 尝试 `cargo test --workspace`，编译依赖时因 `link.exe not found` 退出，未执行到测试。本次仅重设计文档，没有重复该已知受阻命令。

同日用户授权使用 mise 准备环境后，已安装项目 .NET SDK、Rust/PowerShell 等工具及官方 MSVC/Windows SDK组件，独立 WinUI 自包含发布通过。安装器返回 3010，未自动重启；当前组件可检测。以 [Windows 开发环境](windows-development.zh-CN.md)中的新记录替代“缺少 SDK/linker”的当前状态判断。

## 验证路径

先补工具链与配置契约，再做 WinUI 配置切片、独立 Runner 启动、干净 Windows 安装更新，最后替换默认 Manager 与构建链。具体阶段和停止条件以 [主方案](windows-v2-design.zh-CN.md#8-实施顺序与停止条件)和 [路线](roadmap.zh-CN.md)为准。

Dioxus WDIO 测试不能覆盖新 WinUI 窗口；需建立原生 UI 自动化，并正确安排 XAML/UI 线程测试。自动化使用隔离数据，真实 Steam 的状态和时长另做人工验收。[WinUI 测试指导](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/testing/)
