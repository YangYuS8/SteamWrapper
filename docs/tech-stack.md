# SteamWrapper v2 技术栈选型

## 总体选择

SteamWrapper v2 采用 Rust + Tauri 重构。

核心理由：

- Runner 生成原生可执行文件，普通用户无需安装 .NET Runtime。
- Manager 使用 Tauri v2，可以获得更友好的中文界面、Web UI 生态和更好的视觉表现。
- Manager 可以展示本地 Steam 游戏列表与本地封面缓存。
- Runner 仍然保持轻量、无界面、无后台常驻。
- v2 作为长期支持主线，架构上需要同时覆盖 Windows、Linux 与 SteamOS / Steam Deck。

## Workspace

```text
crates/core
crates/runner
apps/manager
apps/manager/src-tauri
```

### steamwrapper-core

职责：

- profile 数据结构；
- TOML 配置读写；
- Steam Launch Options 生成；
- 后续 Steam Library / appmanifest 解析；
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
- Windows、Linux、SteamOS 都属于 v2 长期支持范围，不再后置到 v3。

### SteamWrapper Manager

职责：

- 图形化配置；
- 扫描/添加 Steam 游戏；
- 读取本地 Steam 游戏库与本地封面缓存；
- 选择真正启动的 exe / launcher；
- 生成 Steam Launch Options；
- 后续自动写入 Steam 本地配置并备份。

技术栈：

- Tauri v2
- React
- TypeScript
- Vite
- Tailwind CSS
- shadcn/ui
- lucide-react
- @tanstack/react-query

选择原因：

- 中文字体和中文排版比 egui 更容易处理；
- 可以用 shadcn/ui 快速做出玩家友好的界面；
- 可以自然展示 Steam 游戏封面、卡片、状态提示和配置表单；
- 不需要像 Electron 一样打包完整 Chromium；
- Tauri 后端可以直接调用 Rust core 逻辑。

## Windows 分发

主推：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

备选：

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

安装路径建议：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

用户数据建议：

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Runner 应该被安装或复制到稳定路径，Steam Launch Options 不应该引用临时解压目录。

## 本地封面策略

第一阶段只读取本地 Steam 缓存，不接入在线封面服务。

候选位置：

```text
<Steam安装目录>\appcache\librarycache\
<Steam安装目录>\userdata\<steamid>\config\grid\
```

找不到封面时，Manager 显示占位图，不报错、不联网。

## 明确不选

### C#/.NET

旧版可以继续维护，但 v2 不再选择 C# 作为主实现。主要原因是普通用户会感知到运行时依赖或更大的 self-contained 发布包。

### egui/eframe

egui 适合极简配置器，但 SteamWrapper Manager 需要中文友好、封面展示、卡片布局和更强的玩家向引导，因此改为 Tauri。

### Electron

SteamWrapper 的 GUI 只负责配置，不需要完整 Chromium 运行时。Electron 对这个项目过重。

### Python

不适合该项目的分发场景。打包体积、杀软误报和运行时问题都不利于普通玩家使用。

## 发布目标

短期：

- Windows x64 NSIS setup.exe
- Windows x64 portable zip
- 内含 `SteamWrapperManager.exe` 与 `SteamWrapperRunner.exe`

中期：

- Windows x64 / arm64
- Linux x86_64
- Linux AppImage 或 tar.gz
- SteamOS / Steam Deck 桌面模式文档

长期：

- v2 LTS 发布矩阵稳定化：Windows、Linux、SteamOS
