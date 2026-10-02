---
title: "SteamWrapper v2 技术栈"
description: "WinUI/C# Manager、独立 Rust Runner 与 Windows 优先的开发工具。"
---

<a id="steamwrapper-v2-技术栈"></a>

## 目标方案

**C#/XAML WinUI 3 是唯一的 Manager**，使用可独立测试的 C# Application 服务和独立 Rust Runner。Windows 配置预览、自包含目录构建已实现。Dioxus、其 Rust Manager 服务层、Native E2E 和 GUI 发布工作流已移除，历史结果不定义当前产品。详见 [Windows 设计](/SteamWrapper/zh-cn/project/design/windows-v2/)与 [WinUI 评估](/SteamWrapper/zh-cn/project/decisions/winui3/)。

| 部分 | 当前选择 | 边界 |
| --- | --- | --- |
| Manager UI | WinUI 3、C#、XAML | Windows 原生控件、选择器、可访问性；默认英语和完整简体中文 |
| Manager 服务 | C# Application | 配置、本地 Steam 发现、Runner 安装、日志；无 Rust FFI 或 helper |
| 日常运行 | 独立 Rust Runner | 既有 CLI 与进程生命周期；游玩时关闭 Manager |
| 配置 | `profiles.toml` v2 | C# 编辑保留未知／未编辑数据，测试实际 Rust 消费 |
| 封面 | 自定义／本地 Steam 图片、可选官方 Steam CDN 回退与占位 | 默认离线；有界请求与 SteamWrapper 缓存 |
| 交付 | unpackaged 自包含 Windows 目录与 CI 产物 | 每用户安装器、WinUI 标签发布和更新器未实现 |
| 平台 | Windows 11 24H2 x64 预览 | 仅保留已有 Linux Runner 兼容性／CI，没有 Linux GUI |

C# 使用 Tomlyn 2.10.1 语法树和字段跨度，而非全模型序列化；生成 Rust 可读的 TOML 1.0 字符串子集，保留其他源码。字段、缺省值、旧别名、路径与参数由跨语言及真实 Runner 测试约束。[Tomlyn 包](https://www.nuget.org/packages/Tomlyn/2.10.1)、[语法 API](https://github.com/xoofx/Tomlyn/blob/2.10.1/site/docs/low-level.md)

Runner 保持 Rust。早先 NativeAOT 备选属于归档评估，不是另一实现，也不计划同时重写。未来若重新考虑，须有完整 CLI/TOML 和平台进程证据。[NativeAOT 文档](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)

## 当前仓库布局

```text
apps/manager-winui/SteamWrapper.Manager             # WinUI UI
apps/manager-winui/SteamWrapper.Application         # C# 配置服务
apps/manager-winui/SteamWrapper.Application.Tests   # MSTest
crates/core                                       # Rust 配置/路径契约
crates/runner                                     # Steam 调用的无界面运行器
tests/contracts                                   # C# / Rust 契约与驱动
tests/fixtures                                    # 受控测试进程
docs                                              # Astro/Starlight 静态站
```

### Rust 核心与服务

`steamwrapper-core` 定义 Profile/TOML、路径、启动项契约及既有元数据工具，不依赖 GUI 或平台进程 API。Runner 使用其配置语义。WinUI 直接调用 C# Application，不通过 ABI 调用 core。当前不再保留 Rust Manager 服务 crate。

### Runner

`steamwrapper-runner` 使用 `clap`、`anyhow`、`tracing` 和 `steamwrapper-core`，启动 profile 的 target/args，并按模式等待，不依赖 GUI、WebView、.NET 或常驻服务。

新 Windows 配置显式使用 `job`；旧配置缺少 `wait_mode` 时为 `root`。Linux 保留 `process_group`，但没有当前 Linux Manager。`%command%` 仅接收／记录，不自动执行或转发，Proton 集成未完成。平台进程测试与实际 Steam 验收证明不同事实。

<a id="当前-dioxus-manager"></a>

### 已归档的 Dioxus 实现

已移除的 Dioxus 0.7.10 Manager、WDIO Native E2E 和 Rust 服务层仅保留在 [ca6a09e 历史源码](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus)中。[2026-09-07 比较](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)与 [2026-09-08 包检查](/SteamWrapper/zh-cn/development/distribution/#dioxus-desktop-bundle)保留测量及限制，不提供当前构建命令、受支持发布物或备用 Manager。

## 工具链与交付

mise 为可选项。`global.json` 指定 .NET SDK 10.0.400；Rust 1.98.1 是可选 mise 配置记录的本地参考。适用版本／组件由清单、锁文件、`packageManager` 和 `.vsconfig` 定义。直接 PowerShell/pnpm 命令不要求 mise。

Manager 使用 Windows App SDK 2.4.0 组件集，直接固定 `Microsoft.WindowsAppSDK.WinUI` 2.3.6、`Microsoft.WindowsAppSDK.InteractiveExperiences` 2.1.6 和 SDK.BuildTools 10.0.26100.7705。包版本不是框架名称“WinUI 3”。显式引用 InteractiveExperiences 避免其旧最低依赖；所选依赖版本／摘要与原 2.4.0 总包锁文件一致。

按需组件引用是官方支持的自包含部署方式。Manager 通过项目引用排除未使用的 AI、ML、Search、Widgets、DWrite，不手动删除发布 DLL。2026-09-07 组件精简记录为未压缩约 **171 MiB、457 文件**；早先 **226.23 MiB** 版本的启动／内存结果仍属于历史，未对该较小产物重测。后续产物各有清单，这些数字不代表所有当前构建。[官方组件说明](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8#version-180-18250907003)、[比较记录](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)、[预览记录](/SteamWrapper/zh-cn/project/validation/winui/)

预览目标为 Windows 11 24H2（26100）x64，自包含且关闭 trimming。服务使用 net10.0，测试使用 MSTest 4.4.0 / Test SDK 18.9.0，并有 NuGet 锁文件。Manager 项目直接维护，不使用 alpha 模板或 WinApp MSIX 调试身份包。发布先构建并验证新目录，再替换旧产物。命令与发布回归见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。

Node/pnpm 用于品牌资源生成和静态文档，不是桌面运行时。`pnpm brand:generate`／`pnpm brand:check` 使用仅开发期需要的 `@resvg/resvg-js` 处理统一 SVG/PNG/ICO。`docs/` 工作区使用 Astro 7.3.1 / Starlight 0.42.0，详见[文档维护](/SteamWrapper/zh-cn/development/documentation/)。

Windows CI 生成完整预览目录，包含 `Runner/SteamWrapperRunner.exe` 和版本／摘要元数据。Rust CI 保留 Linux 进程兼容性。WinUI 安装器、标签发布流水线、更新器和自动 Steam 启动项写入属于后续[路线图](/SteamWrapper/zh-cn/project/roadmap/)工作；当前不提供 Linux GUI 包。

## 不选的方向

当前产品不保留 Dioxus，不恢复 Tauri/React、Electron、Node UI runtime 或 Python 运行时组件。不增加 C ABI、管理 helper 或全 C# Runner 重写。Windows 10、ARM64、MSIX、Linux GUI 和 SteamOS/Proton 扩展需要独立决策和证据；Windows x64 预览结果不证明这些平台。
