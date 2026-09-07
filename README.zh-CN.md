# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="128" height="128" />
</p>

SteamWrapper 解决 Windows 汉化游戏或自定义启动器的 Steam 游玩状态与时长问题：**在 Manager 配置一次，以后仍从 Steam 正常启动游戏**。[新的 v2 设计](docs/windows-v2-design.md)采用 **WinUI 3/C# Manager、C# 配置服务和独立 Rust Runner**，通过现有 TOML/CLI 配合。首个 WinUI 配置预览已在 `apps/manager-winui` 实现；Dioxus 与现有发布链暂时保留，尚未切换默认交付。

Steam 通过 Launch Options 调用无界面的 `SteamWrapperRunner`；Runner 从稳定数据目录读取 profile，启动用户选择的汉化 exe 或启动器并按模式等待。真实 Steam 状态与时长是否符合预期仍需客户端验收，不能仅凭进程测试承诺所有游戏兼容。

WinUI 预览分别显示 Steam 安装位置与实际运行文件夹。可保留官方安装供 Steam 更新和校验，将完整汉化版放到库外运行；迁移、存档及成就限制见 [官方安装与汉化版分开存放](docs/translated-games.md)。SteamWrapper 不会补出游戏缺失的成就逻辑。

## 产品目标

- 目标是玩家无需手动配置运行时；未来 C# Manager 可随包携带 .NET，Runner 继续保持 Rust 原生程序。
- 默认不依赖 SteamEdit，不修改 Steam 客户端，不复制完整 wrapper 到游戏目录。
- Manager 仅负责配置；游玩时无需打开它。
- 优先做好 Windows；保留已有 Linux 代码和兼容契约，暂缓 Linux / SteamOS 扩展与发布承诺。
- WinUI 首版读取本地 Steam 游戏库和封面缓存，缺失时友好占位；现有 Dioxus 的 Steam CDN 回退暂未改动。
- 面向普通玩家：配置、安装、更新与恢复流程应清晰而非终端化。

## 产品形态

```text
SteamWrapper.Manager.exe       # WinUI 原生 Windows 配置预览
SteamWrapperManager(.exe)       # 保留的 Dioxus Desktop 图形配置器
SteamWrapperRunner(.exe)        # Steam Launch Options 调用的无界面 Runner
profiles.toml                   # 游戏配置
logs/                           # 运行日志
backups/                        # Steam 配置备份（后续一键应用功能使用）
cache/                          # 本地缓存
```

## 目标 Windows 用户流程

```text
安装 SteamWrapper
→ 打开 SteamWrapper Manager
→ 扫描本地 Steam 游戏
→ 选择需要修改启动方式的游戏
→ 选择真正要启动的 exe / launcher
→ 保存配置，保留已有高级参数和工作目录
→ 复制生成的启动选项（或后续使用“应用到 Steam”）
→ 保留原启动项，再在 Steam 属性中粘贴新值
→ 以后直接从 Steam 启动游戏
```

生成的 Launch Options 兼容格式保持为：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

`%command%` 必须保留在 `--` 后。当前 Runner 接收并记录原命令，实际执行 profile 的 target/args，尚未自动执行或转发原命令。启动项始终引用稳定 Runner 路径，而不是安装包或 portable 解压路径。

Windows 路线先完成配置保真、启动闭环和安装/更新/卸载；首个预览可手动复制启动项，随后优先做带备份的一键应用与恢复，再评估跨平台。复制成功不代表已经应用到 Steam。详见 [路线](docs/roadmap.md)与 [技术评估](docs/winui3-assessment.md)。

## 当前实现

Windows 预览由 `SteamWrapper.Manager`（原生窗口、文件选择、剪贴板）调用 `SteamWrapper.Application`（保真 TOML 编辑、本地 Steam 扫描、稳定 Runner 安装）。C# / Rust 契约测试验证配置的实际消费，不引入 FFI 或后台服务。运行说明见 [Windows 开发](docs/windows-development.md)。以下是保留的 Dioxus 管理链：

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

WinUI 预览在保存配置时检查随包 Runner，将其原子安装到稳定目录。校验失败、文件占用或无法判断新旧时保留已有文件，配置仍可保存；兼容的较新 Runner 不会降级。现有 Dioxus 的首次启动/设置页安装行为保持原样。

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

## 当前 Dioxus 封面策略

优先读取本机 Steam 缓存：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

缓存缺失时，Manager 仅用本地 manifest 已有的 AppID 请求公开 Steam CDN 的 `library_600x900.jpg`。不查询玩家资料、不上传游戏库、不需要 API Key；CDN 的正常 HTTP 缓存会复用封面响应。离线、限流或该 App 没有该资源时，卡片改为友好的“封面暂不可用”占位，不影响扫描或配置。

## WinUI 预览开发

完成 [mise 环境准备](docs/windows-development.md) 后：

```powershell
mise run winui:test       # C# 服务回归
mise run winui:contracts  # C# 编辑 → Rust 读取及真实 Runner 进程验证
mise run winui:publish    # target/winui/publish 自包含目录
mise run winui:sandbox    # 一次性 Steam/用户目录中的原生交互预览
```

预览支持本地扫描/搜索、手动添加、原生选择程序、保真保存、高级参数和启动项复制。请先记录 Steam 的原启动选项，再粘贴新值；需要恢复时粘贴原值。安装器、真实 Steam 时长和干净系统验收仍待完成。不要仅复制发布目录中的 EXE，运行需要同目录依赖。

## Dioxus Manager 开发

Windows 优先使用 [mise 开发环境](docs/windows-development.md)：先执行 `mise install`、`mise run windows:setup` 和 `mise run windows:doctor`。`windows:verify` 验证 Dioxus 基线；`windows:winui-smoke` 保留为独立模板环境诊断。

前置条件：稳定 Rust 工具链、Dioxus CLI `0.7.10`、WebKitGTK 桌面依赖（Linux）以及 pnpm（仅 Native E2E）。根目录 `justfile` 是本地入口：

```bash
just dev          # 使用真实本机 Steam / 用户数据启动，并开启热重载
just dev-sandbox  # 使用一次性 Steam / 用户数据沙箱启动
just verify       # Rust、Dioxus、Native E2E 全量门禁
just bundle-linux # stage Runner 并产出 release-artifacts/*.AppImage
```

执行 `just --list` 查看完整命令。日常本地验证按 [改动范围](docs/testing.md#按改动选择验证) 选择；CI / release 保留完整门禁。需要手工执行各层门禁时：

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

当前 Dioxus 分发文档中的候选发布物（不代表已全部交付）：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
SteamWrapper-v2.x.x-win-x64-portable.zip
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

现有 Dioxus Windows 配置使用 CurrentUser NSIS 安装器；WinUI 的部署方式需单独验证。Linux / SteamOS 后续分发暂缓。GitHub / CNB 双渠道仍是待验收的交付目标。

## 安全边界

SteamWrapper v2 不做：

- DLL 注入；
- Steam 或游戏二进制补丁；
- DRM 绕过；
- 隐藏后台服务；
- 用户数据上传；
- 第三方在线封面服务或玩家库数据上传。

## 品牌资源

统一项目图标为 `assets/brand/steamwrapper.svg`。它是 SteamWrapper 的原创 Rust 齿轮与启动链路意象，不是 Steam 官方 Logo。

## 文档

- `AGENTS.md`
- `docs/architecture.md`
- `docs/tech-stack.md`
- `docs/distribution.md`
- `docs/testing.md`
- `docs/roadmap.md`
- [Windows v2 产品与架构重设计](docs/windows-v2-design.md)

## License

Apache-2.0

## 状态

`v2` 仍处于早期开发阶段；`main` 上的 C# 版本仍是旧版稳定实现。
