# SteamWrapper v2 架构设计

[English](architecture.md) | 简体中文

## 核心目标

v2 当前以 Windows 为优先平台，新的 [产品与架构设计](windows-v2-design.zh-CN.md)采用 WinUI 3/C# Manager、自有 C# 配置服务和独立 Rust Runner，通过既有 TOML/CLI 配合。`apps/manager-winui` 已实现配置预览；Dioxus / Rust 管理链仍作为迁移基线保留。保留已有 Linux 契约，暂缓 Linux / SteamOS / Proton 扩展。

玩家只需在 SteamWrapper Manager 配置一次，之后始终从 Steam 点击“开始游戏”。Manager 不参与日常启动流程。

```text
SteamWrapperManager：配置时可见，WinUI 预览 / Dioxus 基线 GUI
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
Runner 退出；Steam 状态和时长是否符合预期需在客户端实际验收
```

Manager 的配置路径（下面的封面回退仅用于 Dioxus；WinUI 使用本地封面或占位符）：

```text
用户打开 SteamWrapper Manager
↓
扫描本地 Steam Library 与 appmanifest_<appid>.acf
↓
查找本地封面缓存；缺失时按已知 AppID 绑定公开 Steam CDN 封面 URL
↓
选择游戏与真正要启动的 exe / launcher
↓
保存 profile 并生成 Steam Launch Options（应用到 Steam 尚未实现）
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

当前 Runner 接收并记录 `steam_command`，实际执行 profile 的 target/args，不执行或自动追加原命令。不能因 UI 迁移改变该语义。

## 分层

WinUI 预览：

```text
apps/manager-winui/SteamWrapper.Manager       # XAML、窗口状态、原生 picker、剪贴板
                 ↓ C# 调用
apps/manager-winui/SteamWrapper.Application   # 配置、本地 Steam、Runner 安装
                 ↓ profiles.toml / stable Runner 文件
crates/runner                               # 由 Steam 独立启动
```

`ProfileStore` 使用 Tomlyn 语法跨度仅修改编辑字段，保留其他文本和未知数据。新建配置显式写入默认 job；旧缺省 root 不会被补成 job。保存具有协作写锁、字节版本冲突检测、同目录刷新临时文件及原子替换备份。内联/点号 profile 可读但拒绝修改；非协作编辑器仍存在最终检查到替换之间的竞态窗口。

`SteamScanner` 只读本地 VDF 和封面；`RunnerInstaller` 使用摘要绑定的版本清单、稳定路径和原子替换，拒绝无法确认的新旧覆盖。UI 不负责游戏进程控制。`tests/contracts` 与测试专用进程 fixture 验证 C# 编辑和实际 Rust 消费，不进入 Manager 包。

`ProfileSteamInstallation` 按 AppID 关联只读 Steam 安装位置，作为 Manager 的显示信息；它不写入 TOML，也不把发现的目录覆盖到 `game_dir`。后者仍表示实际运行文件夹，可以位于 Steam 库外；Runner 的目标与工作目录解析规则不变。两个位置的用途、迁移及成就边界见 [汉化目录分离](translated-games.zh-CN.md)。

以下保留的 Dioxus 管理链使用独立的旧保存实现：

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

在现有 Rust 管理链中，`core` 提供 Profile、TOML、Steam 目录与 appmanifest 解析、本地优先的封面发现与 AppID 驱动的 Steam CDN 回退 URL、Launch Options。它不得依赖 Dioxus、Tauri、React、WebView 或平台进程等待 API。目标 C# Manager 按同一协议实现配置服务，由跨语言往返与 Runner 消费测试约束兼容性，不通过 FFI 复用该管理链。

### `crates/manager-core`

`manager-core` 是新的 UI 框架无关 Manager service 层，不是 RPC 层。它直接组合 `core`，提供：

- 当前平台稳定数据路径与目录创建；
- Profile 读取、保存和 Launch Options 生成；
- Steam 本地游戏扫描与日志列表；
- Runner 摘要检查、原子安装和修复。

Dioxus UI 直接调用它；不得复制旧 Tauri command 形状或创造伪 IPC。

当前保存服务重建 profile，覆盖高级字段；core 保存使用直接文件写入。这些是已知迁移风险，不是新设计认可的配置语义。WinUI 必须实现保留未编辑字段、未知数据保护、原子写入和冲突处理，详见 [配置保真门槛](windows-v2-design.zh-CN.md#4-配置保真是第一个门槛)。

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

## 界面语言设置

Manager 界面语言独立于 Runner／TOML 契约。两套 Manager 使用稳定数据根中与 `profiles.toml` 同级的 `ui-settings.json`，`language` 为 `en-US` 或 `zh-CN`；接受去除两端空白且不区分大小写的 `en`、`zh-Hans` 别名，缺失或未知值默认英语。保存时保留未知 JSON 字段，不覆盖不合法的已有文件。切换语言必须保留当前表单输入和协议值；用户名称、路径、命令和日志内容保持原样。

WinUI 侧栏选择器在保存成功后刷新应用自有文案，保存失败则保留原语言并显示错误。该界面偏好不改变 Runner 参数、等待模式、游戏路径或原 Steam 命令。

## 等待模式

| 模式 | 用途 |
| --- | --- |
| `root` | 仅等待直接启动的目标进程 |
| `job` | Windows 默认；Job Object 等待未主动脱离的 launcher 派生进程 |
| `process_name` | launcher 退出后等待本次启动出现的指定进程名 |
| `process_group` | Linux / SteamOS 默认；等待同一 POSIX 进程组的派生进程 |
| `none` | 启动后立即退出 |

当前 Manager 新建 profile 的默认值为 Windows `job`、Linux `process_group`；旧 TOML 省略 `wait_mode` 时 Rust 解析器默认 `root`，不能在迁移时重新解释。`process_name` 会排除启动前已存在的同名 `(PID, start_time)`，但无法从名称识别业务归属；只能作为复杂 launcher 的显式兼容方案。Proton 包装留待平台专用策略完善。

## 分发与稳定安装

Windows：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\      # Manager 安装目录
%LOCALAPPDATA%\SteamWrapper\bin\           # Runner 稳定路径
%LOCALAPPDATA%\SteamWrapper\profiles.toml  # 配置
%LOCALAPPDATA%\SteamWrapper\ui-settings.json # 界面语言
%LOCALAPPDATA%\SteamWrapper\logs\          # 日志
%LOCALAPPDATA%\SteamWrapper\backups\       # 备份
```

Linux / SteamOS 使用：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  ui-settings.json
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

旧 Tauri / React Manager 与其 E2E 已移除。`apps/manager-winui` 已提供 Windows 配置预览，`apps/manager-dioxus` 保留为迁移基线。WinUI 在 C# 内实现 Windows 配置服务，不新增 C ABI 或后台 helper；Runner 保持独立 Rust 程序。WinUI 的本地封面策略、旧管理链退役条件和验收顺序以 [Windows 设计](windows-v2-design.zh-CN.md)为准。

Windows NSIS、Linux AppImage 和 SteamOS 实机均需在对应平台的 CI / 设备上继续验证；本机 Linux 通过的检查不能伪装成 Windows 或 Steam Deck 实机证据。
