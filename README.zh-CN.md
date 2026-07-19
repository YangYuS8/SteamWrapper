# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="128" height="128" />
</p>

SteamWrapper v2 是 SteamWrapper 的重构版本。

它不再只是“把一个 wrapper exe 放进游戏目录”的小工具，而是一个面向普通玩家的 Steam 自定义启动管理器。

核心目标：

> 在 SteamWrapper Manager 里配置一次，以后仍然从 Steam 正常启动游戏。

日常游玩时，用户不需要打开 SteamWrapper Manager。Steam 会通过启动选项自动调用无界面的 `SteamWrapperRunner`，Runner 再启动用户配置好的汉化 exe、启动器或 mod loader。

## 品牌资源

统一项目图标位于：

```text
assets/brand/steamwrapper.svg
```

它是为 SteamWrapper 设计的原创 SVG 图标，结合了 Rust 齿轮感和类似 Steam 启动链路的视觉意象，但不是 Steam 官方 Logo。

## 设计目标

- 不要求用户安装 .NET Runtime。
- 默认不依赖 SteamEdit。
- 不需要把完整 wrapper 复制到每个游戏目录。
- GUI 只负责配置，平时游玩无感。
- Runner 是无界面原生程序，由 Steam 自动调用。
- v2 是长期支持主线，覆盖 Windows、Linux 与 SteamOS / Steam Deck。
- Windows 用户优先使用安装程序，也提供 portable zip；Linux 与 SteamOS 分发也纳入 v2 路线。
- 面向普通游戏玩家，安装、更新、卸载都应尽量简单；后续发布会同步 GitHub 与 CNB，方便国内玩家下载。
- 第一阶段只读取本地 Steam 游戏库和本地封面缓存，不接入在线封面服务。

## 产品形态

```text
SteamWrapperManager.exe   # Tauri 图形配置器
SteamWrapperRunner.exe    # 被 Steam Launch Options 调用的无界面原生运行器
profiles.toml             # 游戏配置
logs/                     # 运行日志
backups/                  # Steam 配置备份，后续使用
cache/                    # 本地缓存，后续使用
```

## 普通用户流程

```text
安装 SteamWrapper
→ 打开 SteamWrapper Manager
→ 扫描本地 Steam 游戏
→ 选择需要修改启动方式的游戏
→ 选择真正要启动的 exe / launcher
→ 应用到 Steam 或复制生成的启动选项
→ 以后直接从 Steam 启动游戏
```

生成的 Steam 启动选项示例：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

## 技术栈

v2 采用 Rust + Tauri 架构：

```text
crates/
  core/      # 共享配置、profile、启动选项和 Steam 库逻辑
  runner/    # 被 Steam 调用的原生无界面运行器

apps/
  manager/   # Tauri v2 + React + shadcn/ui 配置器
```

主要技术选择：

- Runner/Core：Rust
- Manager 桌面壳：Tauri v2
- Manager 前端：React + TypeScript + Vite
- UI：Tailwind CSS + shadcn/ui
- 配置格式：TOML
- Windows 分发：优先 NSIS setup.exe，其次 portable zip
- Linux 分发：规划 AppImage 或 tar.gz
- Windows 进程等待：规划使用 Job Object
- Linux 进程等待：规划使用 process group / session
- SteamOS / Proton 支持：纳入 v2，不再作为独立 v3 路线

## Windows 安装方式

正式发布后，中文 README 会优先提供 CNB 国内下载入口，同时保留 GitHub Release 链接。

主推：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

备选：

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

建议路径：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager 安装目录
%LOCALAPPDATA%\SteamWrapper\bin\           # Runner 稳定路径
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # 用户配置
%LOCALAPPDATA%\SteamWrapper\logs\          # 日志
%LOCALAPPDATA%\SteamWrapper\backups\       # Steam 配置备份
```

Manager 安装包内会携带与当前 Windows 构建对应的 Runner；首次打开 Manager 时会自动安装到第二个稳定路径。以后 Manager 安装目录或 portable 解压目录可以更新、移动或删除，Steam 启动项仍只依赖稳定数据目录。若 Runner 被删除、损坏或升级不一致，可在“设置”页安装或修复；这不会覆盖 `profiles.toml`、日志、备份或缓存。

Steam 启动选项应该引用稳定的 Runner 路径，不应该引用临时解压目录。

更新时应直接运行新版安装包覆盖旧版本，并保留 `%LOCALAPPDATA%\SteamWrapper\` 下的用户配置、日志和备份。卸载时默认只删除程序本体，用户数据应提供明确选项再清理。

## 本地封面策略

第一阶段不接入在线封面 API。

Manager 只读取本地 Steam 缓存，例如：

```text
<Steam安装目录>\appcache\librarycache\
<Steam安装目录>\userdata\<steamid>\config\grid\
```

找不到封面时只显示占位图，不联网、不报错，也不影响配置游戏。

## 安全边界

SteamWrapper v2 不做：

- 不注入 DLL；
- 不修改 Steam 客户端；
- 不破解游戏；
- 不绕过 DRM；
- 不常驻后台；
- 第一阶段不联网拉取封面。

SteamWrapper v2 只做：

- 读取本地 Steam 游戏库；
- 读取本地 Steam 封面缓存；
- 配置自定义启动目标；
- 生成或应用 Steam Launch Options；
- 运行时启动用户选择的本地程序；
- 等待目标退出，以配合 Steam 统计游玩时间。

## 开发说明

给 Agents 或贡献者的开发规范见：

- `AGENTS.md`
- `docs/tech-stack.md`
- `docs/architecture.md`
- `docs/distribution.md`
- `docs/roadmap.md`

## License

Apache-2.0

## 状态

`v2` 分支仍处于早期布局阶段。`main` 分支上的 C# 版本暂时仍是旧版稳定实现。
