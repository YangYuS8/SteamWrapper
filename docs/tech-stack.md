# SteamWrapper v2 技术栈选型

## 总体选择

SteamWrapper v2 采用全 Rust 主线：`core`、`manager-core`、`runner` 与 Dioxus Desktop Manager 都由 Rust 构建。Manager 使用 **Dioxus 0.7.10**，而不是继续扩展 Tauri + React。

选择依据不是“Rust 看起来更纯粹”这种幼稚理由，而是已验证的边界：早期 Manager 的 Profile、Steam 扫描、路径、Launch Options 与 Runner 安装逻辑可抽成不依赖桌面框架的 `manager-core`；Dioxus 可直接调用该 typed Rust service，避免 Tauri command / IPC DTO 与 React 状态之间的重复层。

- Runner 仍生成原生可执行文件，普通用户无需 .NET Runtime。
- Dioxus Desktop 能提供 Windows、Linux 的原生窗口、文件选择、CSS 布局和 bundle resources。
- Manager 不再依赖 Node、React、Vite、Tailwind、shadcn 或 Tauri 运行时；pnpm 仅保留给隔离的 WDIO Native E2E 工具。
- Runner 保持轻量、无界面、无后台常驻。
- v2 继续覆盖 Windows、Linux、SteamOS / Steam Deck。

## Workspace

```text
crates/core                 # 跨平台 domain：TOML、Steam、封面、Launch Options
crates/manager-core         # 框架无关的 Manager service
crates/runner               # Steam 启动的原生无界面运行器
apps/manager-dioxus         # Dioxus 0.7.10 Desktop Manager
apps/manager-dioxus/e2e     # WDIO Dioxus Native E2E（仅测试工具）
```

### `steamwrapper-core`

职责：

- Profile 数据结构与 TOML 读写；
- Steam Launch Options 生成；
- Steam Library / `appmanifest` 解析；
- 本地 Steam 封面缓存发现；
- 跨平台通用规则。

依赖保持为 `serde`、`toml`、`thiserror` 等通用 Rust crate；禁止 UI 或平台进程 API 反向渗透。

### `steamwrapper-manager-core`

职责：

- 稳定用户数据路径与目录准备；
- Profile 列表、保存、Launch Options；
- 本地 Steam 游戏扫描与 Runner 日志；
- 随包 Runner 的摘要检查、原子安装与修复。

它是普通 Rust API，不是 IPC server：Dioxus 直接调用，且不定义第二套 Profile / Steam DTO。

### `steamwrapper-runner`

职责：

- 被 Steam Launch Options 自动调用；
- 无界面运行；
- 根据 `--appid` 查找 profile；
- 启动真正的游戏 exe / launcher；
- 等待目标进程退出，使 Steam 正确统计游玩时间。

依赖：`clap`、`anyhow`、`tracing`、`steamwrapper-core`。

平台策略：Windows 默认 Job Object，Linux 默认 POSIX process group；SteamOS / Proton 要保留 Steam 展开的 `%command%` 环境，具体包装策略仍待平台测试。

### `SteamWrapper Manager`

技术栈：

- Dioxus `0.7.10` + `desktop` feature；
- RSX 组件与原生 CSS；
- `Dioxus.toml` 统一 bundle metadata、图标与 `resources/runner`；
- `@wdio/dioxus-service` 1.0.0 + embedded provider 仅用于 Native E2E；
- `wdio-dioxus-embedded-driver` 1.0.0 仅在 Cargo `e2e` feature 编译。

UI 职责：扫描 / 添加游戏、读取本地封面、选择目标程序、保存 profile、生成 Launch Options、查看已配置游戏 / 日志 / 稳定路径、安装或修复 Runner。

正式 Rust dependency graph 不含 WDIO bridge 或 embedded driver；测试 feature 与 release bundle 必须分离。

## Dioxus Agent 开发约定

- 版本固定在 `0.7.10`，升级必须先复核官方 API、CLI 与 bundle 行为。
- 开发先用 `dx check`，生产构建用 `dx build --release`。
- bundle 资源必须在 `[bundle].resources` 显式声明；`asset_dir` 只解决 UI asset，不等于随包 Runner。
- 不要把 Dioxus UI 伪装成 Tauri command client；直接调用 `manager-core`。
- HTML / CSS 是适合玩家桌面 UI 的选择，不因“全 Rust”而退回难用的即时模式 GUI。
- 选择目标程序使用 Dioxus 的本地文件 input；不加入 Node runtime 或前端框架。

## Windows 与 Linux 分发

目标发布物：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
SteamWrapper-v2.x.x-win-x64-portable.zip
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

Windows 使用 Dioxus NSIS CurrentUser 安装器，建议安装到 `%LOCALAPPDATA%\Programs\SteamWrapper\`；Linux / SteamOS 预览使用 AppImage 或 tar.gz。Manager bundle 中只读 Runner 资源由平台 CI stage：Linux 为 `steamwrapper-runner`，Windows 为 `SteamWrapperRunner.exe`，随后由 Manager 安装到稳定数据路径。

## 不选的方案

### Tauri + React

该实现已随迁移完成而移除。重新引入它会恢复 command adapter、Node 构建与两套状态 / 数据模型成本；当前 Manager 只采用 Dioxus 路线。

### egui / eframe

egui 适合极简工具，但 SteamWrapper Manager 需要中文友好、封面卡片、引导式配置与表单。Dioxus 的 WebView CSS 布局更合适。

### Electron

Manager 只负责配置，不值得携带完整 Chromium。

### Python 与 C#/.NET runtime

不利于此项目面向普通玩家的跨平台分发、体积和维护边界。旧 C# 版本仍按旧版稳定实现维护，不是 v2 技术主线。

## 已知限制

Dioxus bundle 与 Native E2E 已在本机 Linux 路径验证；Windows NSIS、Windows Runner resource、SteamOS / Steam Deck 实机和 Proton 行为须依赖对应 CI / 设备验证。不要拿本机 Linux 成功假装跨平台发布已完成。
