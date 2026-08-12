# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="128" height="128" />
</p>

SteamWrapper v2 是 SteamWrapper 的 Rust 重构版本：它不是往每个游戏目录塞一个 wrapper，而是让玩家**在 Manager 配置一次，以后仍从 Steam 正常启动游戏**。

Steam 通过 Launch Options 调用无界面的 `SteamWrapperRunner`；Runner 从稳定数据目录读取 profile，启动用户选择的汉化 exe、启动器或 mod loader，并等待游戏退出以维持 Steam 游玩时间统计。

## 产品目标

- 不要求安装 .NET Runtime；核心与 Runner 均为 Rust 原生程序。
- 默认不依赖 SteamEdit，不修改 Steam 客户端，不复制完整 wrapper 到游戏目录。
- Manager 仅负责配置；游玩时无需打开它。
- v2 是长期支持主线，覆盖 Windows、Linux、SteamOS / Steam Deck 桌面模式。
- 首阶段完全离线：只读取本地 Steam 游戏库和本地封面缓存，不请求在线封面服务。
- 面向普通玩家：配置、安装、更新与恢复流程应清晰而非终端化。

## 产品形态

```text
SteamWrapperManager(.exe)       # Dioxus Desktop 图形配置器
SteamWrapperRunner(.exe)        # Steam Launch Options 调用的无界面 Runner
profiles.toml                   # 游戏配置
logs/                           # 运行日志
backups/                        # Steam 配置备份（后续一键应用功能使用）
cache/                          # 本地缓存
```

## 普通用户流程

```text
安装 SteamWrapper
→ 打开 SteamWrapper Manager
→ 扫描本地 Steam 游戏
→ 选择需要修改启动方式的游戏
→ 选择真正要启动的 exe / launcher
→ 复制生成的启动选项（或后续使用“应用到 Steam”）
→ 以后直接从 Steam 启动游戏
```

生成的 Launch Options 兼容格式保持为：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

`%command%` 必须保留在 `--` 后，供后续 Steam / Proton 兼容策略使用。启动项始终引用稳定 Runner 路径，而不是安装包或 portable 解压路径。

## 架构

```text
apps/manager-dioxus (Dioxus Desktop + CSS)
                ↓ 直接调用，不做伪 IPC
crates/manager-core (Manager 服务：路径、profile、扫描、Runner 安装/修复)
                ↓
crates/core (GUI 无关的 TOML、Steam、封面和 Launch Options 逻辑)

crates/runner (独立、无界面、被 Steam 调用)
```

- `crates/core` 不依赖 Dioxus、桌面框架或平台进程 API。
- `crates/runner` 不依赖 GUI、WebView 或前端资源。
- `crates/manager-core` 负责 Manager 专属编排，但不依赖 Dioxus；这保留了未来替换 UI 的边界。
- `apps/manager-dioxus` 使用 Dioxus 0.7.10、RSX 和原生 CSS，直接消费 typed Rust service。

## Runner 的稳定安装

Manager bundle 带有当前平台的 Runner 资源。首次启动时会校验并原子安装到稳定用户数据目录；如果缺失、损坏或版本不同，可在“设置”中修复。此操作不会覆盖 `profiles.toml`、日志、备份或缓存。

Windows：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager 安装目录
%LOCALAPPDATA%\SteamWrapper\bin\           # 稳定 Runner
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # 用户配置
%LOCALAPPDATA%\SteamWrapper\logs\          # 日志
%LOCALAPPDATA%\SteamWrapper\backups\       # 备份
```

Linux / SteamOS：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

未设置 `XDG_DATA_HOME` 时使用 `~/.local/share/SteamWrapper/`。

## 本地封面策略

只读取本机 Steam 缓存：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

找不到封面时显示占位图，不联网、不报错，仍允许配置游戏。

## Dioxus Manager 开发

前置条件：稳定 Rust 工具链、Dioxus CLI `0.7.10`、WebKitGTK 桌面依赖（Linux）以及 pnpm（仅 Native E2E）。根目录 `justfile` 是本地入口：

```bash
just dev          # 使用真实本机 Steam / 用户数据启动，并开启热重载
just dev-sandbox  # 使用一次性 Steam / 用户数据沙箱启动
just verify       # Rust、Dioxus、Native E2E 全量门禁
just bundle-linux # stage Runner 并产出 release-artifacts/*.AppImage
```

执行 `just --list` 查看完整命令。需要手工执行各层门禁时：

```bash
pnpm install --frozen-lockfile
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
```

Native E2E 会在隔离临时目录中创建 Steam Library、XDG / LocalAppData 与 profile fixture，绝不读取或写入真实 Steam 配置：

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Dioxus Native E2E 使用 `@wdio/dioxus-service` 的 embedded provider；其 Rust bridge 仅在 `e2e` Cargo feature 下编译，正式 bundle 不携带测试 WebDriver。

## 分发

计划发布物：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
SteamWrapper-v2.x.x-win-x64-portable.zip
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

Windows 使用 CurrentUser NSIS 安装器；Linux / SteamOS 的预览目标为 AppImage 或 tar.gz。正式发布同步 GitHub Release 与 CNB Release，中文 README 将优先提供国内可用下载入口。

## 安全边界

SteamWrapper v2 不做：

- DLL 注入；
- Steam 或游戏二进制补丁；
- DRM 绕过；
- 隐藏后台服务；
- 用户数据上传；
- 首阶段在线封面抓取。

## 品牌资源

统一项目图标为 `assets/brand/steamwrapper.svg`。它是 SteamWrapper 的原创 Rust 齿轮与启动链路意象，不是 Steam 官方 Logo。

## 文档

- `AGENTS.md`
- `docs/architecture.md`
- `docs/tech-stack.md`
- `docs/distribution.md`
- `docs/testing.md`
- `docs/roadmap.md`

## License

Apache-2.0

## 状态

`v2` 仍处于早期开发阶段；`main` 上的 C# 版本仍是旧版稳定实现。
