# SteamWrapper v2 架构设计

## 核心目标

v2 是 SteamWrapper 的长期支持主线。Windows、Linux、SteamOS / Steam Deck 均属于 v2 范围；除非未来有必须破坏兼容性的架构证据，否则不另开 v3。

玩家只需在 SteamWrapper Manager 配置一次，之后始终从 Steam 点击“开始游戏”。Manager 不参与日常启动流程。

```text
SteamWrapperManager：配置时可见，Dioxus Desktop GUI
SteamWrapperRunner：游玩时无感，Rust 原生无界面程序
```

## 运行流程

```text
Steam 启动游戏
↓
Steam Launch Options 调用 SteamWrapperRunner
↓
Runner 读取 profiles.toml
↓
Runner 根据 --appid 找到 profile
↓
Runner 启动真正的 exe / launcher
↓
Runner 等待游戏退出
↓
Runner 退出，Steam 停止统计本次游玩时间
```

Manager 的配置路径：

```text
用户打开 SteamWrapper Manager
↓
扫描本地 Steam Library 与 appmanifest_<appid>.acf
↓
查找本地封面缓存；缺失时按已知 AppID 绑定公开 Steam CDN 封面 URL
↓
选择游戏与真正要启动的 exe / launcher
↓
保存 profile 并生成或应用 Steam Launch Options
↓
以后仍从 Steam 启动游戏
```

## Launch Options 合约

```text
"<stable-runner-path>" --appid "123456" -- %command%
```

- `--appid` 稳定定位 profile；
- `--` 之后保留 Steam 原始命令；
- `%command%` 为未来 Steam / Proton 包装保留；
- Launch Options 只能指向稳定 Runner 路径，不能指向临时安装或解压目录。

`profiles.toml` 的 v2 格式、Runner CLI 和上述启动选项是兼容性边界；迁移 GUI 时不得改变它们。

## 分层

```text
apps/manager-dioxus
  Dioxus Desktop、RSX、原生 CSS、玩家可见 UI
                ↓ 直接 Rust 调用
crates/manager-core
  ManagerServices、稳定路径、profile、扫描、日志、Runner 安装/修复
                ↓
crates/core
  Profile / TOML、Steam Library、封面缓存、Launch Options、跨平台规则

crates/runner
  独立 CLI、目标启动、平台等待、运行日志
```

### `crates/core`

`core` 是唯一的通用数据和业务规则来源：Profile、TOML、Steam 目录与 appmanifest 解析、本地优先的封面发现与 AppID 驱动的 Steam CDN 回退 URL、Launch Options。它不得依赖 Dioxus、Tauri、React、WebView 或平台进程等待 API。

### `crates/manager-core`

`manager-core` 是新的 UI 框架无关 Manager service 层，不是 RPC 层。它直接组合 `core`，提供：

- 当前平台稳定数据路径与目录创建；
- Profile 读取、保存和 Launch Options 生成；
- Steam 本地游戏扫描与日志列表；
- Runner 摘要检查、原子安装和修复。

Dioxus UI 直接调用它；不得复制旧 Tauri command 形状或创造伪 IPC。

### `apps/manager-dioxus`

Dioxus Desktop 0.7.10 配置器承担玩家可见流程：本地游戏扫描、封面卡片、手动添加、目标程序选择、profile 编辑、Launch Options、已配置游戏、日志和设置。CSS 是原生本地资源；品牌 SVG 必须保持 `assets/brand/steamwrapper.svg` 的副本一致。

`Dioxus.toml` 显式声明 `resources/runner`。构建时按平台 stage Runner；Manager 首次启动或设置页修复时才把只读 bundle 资源复制到稳定用户数据位置。

### `crates/runner`

Runner 始终独立、原生、无界面，不能依赖 Dioxus 或 GUI 生命周期。Manager 仅安装和检查其分发资源，绝不把启动、等待或平台进程控制搬进 GUI。

## Profile 示例

```toml
version = 2

[profiles.123456]
name = "Example Game"
app_id = "123456"
platform = "windows"
game_dir = "D:/SteamLibrary/steamapps/common/Example Game"
target = "ExampleGame_CHS.exe"
working_dir = "."
args = []
wait_mode = "job"
```

## 等待模式

| 模式 | 用途 |
| --- | --- |
| `root` | 仅等待直接启动的目标进程 |
| `job` | Windows 默认；Job Object 等待未主动脱离的 launcher 派生进程 |
| `process_name` | launcher 退出后等待本次启动出现的指定进程名 |
| `process_group` | Linux / SteamOS 默认；等待同一 POSIX 进程组的派生进程 |
| `none` | 启动后立即退出 |

新 profile 的默认值为 Windows `job`、Linux `process_group`。`process_name` 会排除启动前已存在的同名 `(PID, start_time)`，但无法从名称识别业务归属；只能作为复杂 launcher 的显式兼容方案。Proton 包装留待平台专用策略完善。

## 分发与稳定安装

Windows：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager 安装目录
%LOCALAPPDATA%\SteamWrapper\bin\           # Runner 稳定路径
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # 配置
%LOCALAPPDATA%\SteamWrapper\logs\          # 日志
%LOCALAPPDATA%\SteamWrapper\backups\       # 备份
```

Linux / SteamOS 使用：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

未设置 `XDG_DATA_HOME` 时使用 `~/.local/share/SteamWrapper/`。Runner 资源校验后原子写入稳定路径；更新只触碰 Runner，不覆盖 profile、日志、备份和缓存。

## 封面与安全边界

Manager 优先读取本机 Steam 缓存：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

本地缓存缺失时，`core` 根据已从本地 manifest 读取的 AppID 生成公开 Steam CDN 的 `library_600x900.jpg` URL；Dioxus 只把该 URL 交给图片控件加载。此请求不含 Steam 用户名、库清单、profile 或 API Key，也不引入第三方封面服务或把新图片写入用户数据。离线、限流、缺失资源或图片加载失败时，UI 退回“封面暂不可用”占位，不阻止扫描或配置。

SteamWrapper 不注入 DLL、不补丁 Steam/游戏、不绕过 DRM、不常驻后台，也不上传用户数据。

## Manager 技术边界

旧 Tauri / React Manager 与其 E2E 已移除。当前唯一的 Manager 实现和交付目标是 `apps/manager-dioxus`；不得重新引入旧 command adapter、Node 前端运行时或第二套 UI 状态模型。

Windows NSIS、Linux AppImage 和 SteamOS 实机均需在对应平台的 CI / 设备上继续验证；本机 Linux 通过的检查不能伪装成 Windows 或 Steam Deck 实机证据。
