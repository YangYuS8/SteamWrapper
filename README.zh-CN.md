# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="128" height="128" />
</p>

[English](README.md) | 简体中文

**在 Manager 配置一次，以后仍从 Steam 正常启动游戏。** SteamWrapper 帮助 Windows 玩家启动汉化版游戏或自定义启动器，让 Steam 状态和时长尽可能跟随实际游戏生命周期。

[Windows v2 设计](docs/windows-v2-design.zh-CN.md)采用 **WinUI 3/C# Manager、C# 配置服务和独立 Rust Runner**，通过既有 TOML/CLI 配合。原生配置预览已在 `apps/manager-winui` 实现；Dioxus 与现有发布工作流保留为迁移基线，默认交付链尚未切换。

日常游玩时，Steam Launch Options 调用无界面 Runner。它从稳定数据目录读取配置，启动选定的 EXE／启动器并按模式等待，Manager 可以保持关闭。仅凭进程测试不能证明每款游戏的 Steam 状态或时长兼容性。

保留官方安装供 Steam 更新和校验，将完整汉化版放到 Steam 库外。WinUI 分别显示 Steam 安装位置和实际运行文件夹。迁移、存档及成就限制见[目录分离说明](docs/translated-games.zh-CN.md)。SteamWrapper 不会补出缺失的成就逻辑。

## 产品目标

- 玩家无需手动准备运行环境；自包含 C# Manager 可携带 .NET，Runner 保持 Rust 原生程序。
- 默认不依赖 SteamEdit，不修改 Steam 客户端，不向每个游戏目录复制完整 wrapper。
- Manager 负责配置；日常游玩使用独立无界面 Runner。
- Windows 优先；保留已有 Linux 代码和契约，暂缓 Linux／SteamOS 扩展与发布承诺。
- WinUI 首版读取本地 Steam 元数据和封面缓存，缺失时友好占位；保留的 Dioxus 仍有公开 Steam CDN 回退。
- 配置、安装、更新和恢复流程应让普通玩家理解。
- 项目主语言为英语，提供完整简体中文界面资源和文档。

## 产品形态

```text
SteamWrapper.Manager.exe       # WinUI 原生 Windows 配置预览
SteamWrapperManager(.exe)       # 保留的 Dioxus Desktop 配置器
SteamWrapperRunner(.exe)        # Steam Launch Options 调用的无界面 Runner
profiles.toml                   # 共用游戏配置
ui-settings.json                # Manager 界面语言偏好
logs/                           # 运行日志
backups/                        # 配置备份；后续 Steam 应用功能的备份
cache/                          # 本地元数据／缓存
```

## Windows 玩家流程

```text
安装 SteamWrapper
→ 打开 SteamWrapper Manager
→ 扫描本地 Steam 游戏
→ 选择需要修改启动行为的游戏
→ 选择真正启动的 EXE／启动器和运行文件夹
→ 保存配置，保留高级参数与工作目录
→ 复制生成的启动选项
→ 保留原启动项，再在 Steam 属性中粘贴新值
→ 关闭 Manager，以后直接从 Steam 启动
```

生成的 Launch Options 保持如下兼容格式：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

`%command%` 必须位于 `--` 后。当前 Runner 接收并记录原 Steam 命令，实际执行配置的 target/args，不会自动执行或转发原命令。启动项始终引用稳定 Runner，不指向安装包、临时解压目录或 Manager。

Windows 路线先完成配置保真、启动闭环和安装／更新／卸载，再扩展跨平台。首个预览使用手动复制，随后做带备份的一键应用／恢复。复制不代表已应用到 Steam。详见[路线](docs/roadmap.zh-CN.md)和[技术评估](docs/winui3-assessment.zh-CN.md)。

## 当前实现

WinUI 的 `SteamWrapper.Manager`（原生界面、选择器、剪贴板）调用 `SteamWrapper.Application`（保留语法的 TOML 编辑、本地 Steam 发现、稳定 Runner 安装）。跨语言契约验证实际 Rust 消费，不引入 FFI 或后台服务。见 [Windows 开发环境](docs/windows-development.zh-CN.md)。

保留的 Dioxus 管理链：

```text
apps/manager-dioxus（Dioxus Desktop + CSS）
                ↓ 直接 typed Rust 调用
crates/manager-core（路径、配置、扫描、日志、Runner 安装／修复）
                ↓
crates/core（GUI 无关的 TOML、Steam、封面、启动选项）

crates/runner（独立、无界面、由 Steam 调用）
```

- `crates/core` 不依赖 Dioxus、桌面框架或平台进程 API。
- `crates/runner` 不依赖 GUI、WebView 或前端资源。
- `crates/manager-core` 编排 Manager 服务但不依赖 Dioxus，保留替换 UI 的边界。
- `apps/manager-dioxus` 使用 Dioxus 0.7.10、RSX 和本地 CSS，直接调用 typed service，不模拟 Tauri IPC。

## 语言

Manager 支持英语和简体中文；WinUI 的语言选择器位于侧栏。两套 Manager 共用与 `profiles.toml` 同级的 `ui-settings.json`，以 `language: "en-US"` 或 `"zh-CN"` 保存语言；缺失或未知值回退英语。切换成功后立即更新应用自有文案，并保留到下次启动。用户填写的名称、路径、启动命令和日志内容不变。

语言切换不重新解释 TOML 字段、AppID、参数或等待模式；已有语言设置文件不合法时不会被静默覆盖。英语文档使用 `.md`，完整简体中文对应版本使用 `.zh-CN.md`，并提供返回英语的链接。

## 稳定 Runner 安装

WinUI 保存配置时检查随包 Runner，将其原子安装到稳定目录。摘要失败、文件占用或无法判断版本新旧时保留已有文件，配置仍可保存；较新兼容 Runner 不会降级。Dioxus 保留首次启动／设置页安装行为。

Windows：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # 目标 Manager 安装目录
%LOCALAPPDATA%\SteamWrapper\bin\           # 稳定 Runner
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # 用户配置
%LOCALAPPDATA%\SteamWrapper\ui-settings.json # 界面语言
%LOCALAPPDATA%\SteamWrapper\logs\          # 日志
%LOCALAPPDATA%\SteamWrapper\backups\       # 备份
```

Linux／SteamOS：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  ui-settings.json
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

未设置 `XDG_DATA_HOME` 时使用 `~/.local/share/SteamWrapper/`。

## 当前 Dioxus 封面策略

优先读取本地 Steam 缓存：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

封面缺失时，Manager 只使用本地 manifest 已有的 AppID 请求公开 Steam CDN 的 `library_600x900.jpg`，不查询玩家资料、不上传游戏库、不要求 API Key。正常 HTTP 缓存可复用响应。离线、限流或资源不存在时显示友好的封面占位，不阻止扫描或配置。

## WinUI 预览开发

完成 [mise 环境准备](docs/windows-development.zh-CN.md)后：

```powershell
mise run winui:test       # C# 服务回归
mise run winui:contracts  # C# 编辑 → Rust 读取及真实 Runner 进程验证
mise run winui:publish    # target/winui/publish 自包含目录
mise run winui:sandbox    # 一次性 Steam／用户数据中的原生预览
```

预览支持本地扫描／搜索、手动添加、原生选择程序、保真保存、高级参数和启动项复制。粘贴前保留 Steam 原启动项，需要撤销时粘贴原值。必须保留完整发布目录，不能只复制 EXE。

本机真实 Steam 验收已通过一个 Unity galgame 和五部独立汉化 9-nine；具体游戏／场景、中文开场、状态／时长和限制见[真实验收](docs/real-steam-validation.zh-CN.md)。这些结果不保证所有游戏或成就兼容。干净 Windows 11 VM 与 WinUI 安装器仍待验收。

## Dioxus Manager 开发

Windows 使用 [mise 开发环境](docs/windows-development.zh-CN.md)：`mise install`、`mise run windows:setup`、`mise run windows:doctor`。`windows:verify` 检查 Dioxus 基线，`windows:winui-smoke` 保留为独立模板环境诊断。

前置条件包括稳定 Rust、Dioxus CLI `0.7.10`，Linux 还需 WebKitGTK 桌面依赖。pnpm 用于 Native E2E 和开发期资源工具，不是产品 UI 运行时。根目录 `justfile` 提供本地入口：

```bash
just dev          # 真实本机 Steam／用户数据，开启热重载
just dev-sandbox  # 一次性 Steam／用户数据沙箱
just verify       # Rust、Dioxus、Native E2E 门禁
just bundle-linux # stage Runner 并生成 release-artifacts/*.AppImage
```

用 `just --list` 查看所有命令，按[改动范围](docs/testing.zh-CN.md#按改动选择验证)选择本地检查；CI／release 完整门禁保留。各层命令：

```bash
pnpm install --frozen-lockfile
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
```

Native E2E 创建隔离 Steam Library、XDG／LocalAppData 和 profile fixture，不读写真实 Steam 配置：

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Dioxus Native E2E 使用 `@wdio/dioxus-service` embedded provider；Rust bridge 仅在 `e2e` Cargo feature 下构建，正式包不携带测试 WebDriver。

## 分发

保留的 Dioxus 分发计划中的候选产物，不代表已全部交付：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
SteamWrapper-v2.x.x-win-x64-portable.zip
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

现有 Dioxus Windows 配置使用 CurrentUser NSIS 安装器；WinUI 部署需单独验收。后续 Linux／SteamOS 交付暂缓，GitHub／CNB 双渠道仍是待验收目标。详见[分发](docs/distribution.zh-CN.md)。

## 安全边界

SteamWrapper v2 不做 DLL 注入、Steam／游戏二进制补丁、DRM 绕过、隐藏后台服务、用户数据上传、第三方在线封面服务接入或玩家游戏库上传。系统安全设置变更和第三方文件恢复不是应用功能。

自动测试使用一次性 fixture；真实游戏库测试需所有者授权、保留原启动项并保护游戏文件和已有进度。不了解 Steam 校验会替换文件这一后果时，不要对改装汉化版本进行校验。疑似漏洞请依照[安全策略](SECURITY.zh-CN.md)报告。

## 品牌资源

原创统一图标源为 `assets/brand/steamwrapper.svg`，配有生成的 `.png`／`.ico` 和匹配的 Dioxus 副本。Rust 风格齿轮与 Steam 风格启动连杆表达 SteamWrapper；本项目不隶属 Valve 或 Rust 项目，也未得到它们背书。

```powershell
mise run brand:generate
mise run brand:check
```

生成使用开发期 pnpm／`@resvg/resvg-js`，不是应用运行时。修改图标源或随包副本前请阅读[贡献指南](CONTRIBUTING.zh-CN.md)。

## 文档与社区

- [文档索引](docs/README.zh-CN.md)：架构、环境、测试、迁移、分发及注明日期的证据。
- [贡献指南](CONTRIBUTING.zh-CN.md)、[行为准则](CODE_OF_CONDUCT.zh-CN.md)、[安全策略](SECURITY.zh-CN.md)和[使用帮助](SUPPORT.zh-CN.md)。
- [Issues](https://github.com/YangYuS8/SteamWrapper/issues) 接受英语和简体中文报告。`v2` 中提供对应模板文件；实际模板选择器取决于默认分支。
- [Agent 指南](AGENTS.md)记录仓库自动化协作要求。

## 许可证与状态

本 `v2` 分支沿用 [Apache-2.0](LICENSE)。`main` 上的旧版 C# 实现有其自身分支内容和许可证，本次不改变它们。

`v2` 仍在开发。GitHub 默认分支目前是 `main`，因此其社区检查和模板显示可能与本分支不同。针对本实现的贡献应提交到 `v2`；这些文件不会更改默认分支或远程设置。
