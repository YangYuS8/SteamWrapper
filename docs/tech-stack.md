# SteamWrapper v2 技术栈选型

## 总体选择

SteamWrapper v2 采用 Rust workspace 重构。

核心理由：

- 生成原生可执行文件，普通用户无需安装 .NET Runtime。
- 适合实现轻量、可信、无后台常驻的系统工具。
- 可以同时覆盖 Windows、Linux 与未来 SteamOS / Steam Deck。
- Manager 与 Runner 可以共享同一套配置模型。

## Workspace

```text
crates/core
crates/runner
crates/manager
```

### steamwrapper-core

职责：

- profile 数据结构；
- TOML 配置读写；
- Steam Launch Options 生成；
- 跨平台通用规则。

依赖：

- `serde`
- `toml`
- `thiserror`

### steamwrapper-runner

职责：

- 被 Steam 启动选项自动调用；
- 无界面运行；
- 根据 `--appid` 查找 profile；
- 启动真正的游戏 exe / launcher；
- 等待目标进程退出，让 Steam 正确统计游玩时间。

依赖：

- `clap`
- `anyhow`
- `tracing`
- `steamwrapper-core`

平台计划：

- Windows：默认使用 Job Object 等待进程组。
- Linux：使用 process group / session 等待。
- SteamOS：优先保留 Steam / Proton 展开的原始 `%command%` 环境。

### steamwrapper-manager

职责：

- 图形化配置；
- 扫描/添加 Steam 游戏；
- 选择真正启动的 exe / launcher；
- 生成 Steam Launch Options；
- 后续自动写入 Steam 本地配置并备份。

GUI 选择：

- 初期采用 `egui/eframe`。

原因：

- Rust 原生；
- 不引入 WebView；
- 跨平台；
- 足够完成配置器需求；
- 比 Tauri/Electron 更轻量。

## 明确不选

### C#/.NET

旧版可以继续维护，但 v2 不再选择 C# 作为主实现。主要原因是普通用户会感知到运行时依赖或更大的 self-contained 发布包。

### Electron / Tauri

SteamWrapper 的 GUI 只负责配置，不需要完整 Web 技术栈。使用 Electron/Tauri 会让工具显得过重。

### Python

不适合该项目的分发场景。打包体积、杀软误报和运行时问题都不利于普通玩家使用。

## 发布目标

短期：

- Windows x64 zip
- 内含 `SteamWrapperManager.exe` 与 `SteamWrapperRunner.exe`

中期：

- Windows x64 / arm64
- Linux x86_64

长期：

- SteamOS / Steam Deck 文档化支持
