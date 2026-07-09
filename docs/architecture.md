# SteamWrapper v2 架构设计

## 核心目标

用户只需要在 SteamWrapper Manager 里配置一次。以后启动游戏时，用户仍然只从 Steam 点击“开始游戏”。

SteamWrapper 的 GUI 不参与日常启动流程。

```text
SteamWrapperManager：配置时可见，Tauri GUI
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
Runner 根据 --appid 找到对应 profile
↓
Runner 启动真正的 exe / launcher
↓
Runner 等待游戏退出
↓
Runner 退出，Steam 停止统计本次游玩时间
```

## Manager 配置流程

```text
用户打开 SteamWrapper Manager
↓
Manager 扫描本地 Steam Library
↓
Manager 读取 appmanifest_<appid>.acf
↓
Manager 尝试读取本地 Steam 封面缓存
↓
用户选择游戏与真正要启动的 exe / launcher
↓
Manager 生成或应用 Steam Launch Options
↓
用户以后直接从 Steam 启动游戏
```

## 为什么使用 Launch Options

v2 默认不再依赖 SteamEdit，也不再要求把完整 wrapper 放入每个游戏目录。

Manager 生成的启动选项示例：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

其中：

- `--appid` 用于稳定定位 profile；
- `--` 后面保留 Steam 原始命令；
- `%command%` 让 Runner 能在未来兼容原始 Steam / Proton 启动环境；
- Runner 路径应该稳定，不应指向临时解压目录。

## 配置模型

```toml
version = 2

[profiles."123456"]
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
| `root` | 只等待直接启动的目标进程 |
| `job` | Windows 默认目标，使用 Job Object 等待进程组 |
| `process_name` | launcher 启动真正游戏后自己退出时使用 |
| `process_group` | Linux / SteamOS 目标，等待进程组或 session |
| `none` | 启动后立即退出 |

## 项目分层

```text
crates/
  core/
    config
    profile
    launch_option
    steam_library
    local_cover_cache

  runner/
    platform/windows
    platform/unix

apps/
  manager/
    src/                 # React + shadcn/ui frontend
    src-tauri/           # Tauri commands and bundling
```

`core` 不应该依赖 Windows API、Linux API、Tauri 或前端框架。

平台差异集中在：

- Steam 安装位置；
- Steam 用户目录；
- LaunchOptions 写入方式；
- 进程等待方式；
- Proton / SteamOS 启动环境；
- 本地封面缓存路径差异。

## Windows 安装模型

普通用户主推 NSIS 安装程序：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

高级用户提供 portable zip：

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

portable 版首次启动时，也应该引导用户把 Runner 复制到稳定路径，避免 Steam Launch Options 指向被移动或删除的解压目录。

## 本地封面策略

第一阶段只读取本地 Steam 缓存，不接入在线封面服务。

候选来源：

```text
<Steam安装目录>\appcache\librarycache\
<Steam安装目录>\userdata\<steamid>\config\grid\
```

封面读取失败时：

- 不联网；
- 不报错；
- 显示默认占位图；
- 允许用户继续配置游戏。

## 设计边界

SteamWrapper v2 不做：

- 不注入 DLL；
- 不修改 Steam 客户端；
- 不破解游戏；
- 不绕过 DRM；
- 不常驻后台；
- 第一阶段不联网拉取封面。

SteamWrapper v2 只做：

- 配置自定义启动目标；
- 读取本地 Steam 游戏库；
- 读取本地 Steam 封面缓存；
- 生成或应用 Steam Launch Options；
- 运行时启动目标程序；
- 等待目标退出以配合 Steam 统计时间；
- 提供可恢复的配置变更。
