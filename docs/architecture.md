# SteamWrapper v2 架构设计

## 核心目标

用户只需要在 SteamWrapper 里配置一次。以后启动游戏时，用户仍然只从 Steam 点击“开始游戏”。

SteamWrapper 的 GUI 不参与日常启动流程。

```text
SteamWrapperManager：配置时可见
SteamWrapperRunner：游玩时无感
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

## 为什么使用 Launch Options

v2 默认不再依赖 SteamEdit，也不再要求把完整 wrapper 放入每个游戏目录。

Manager 生成的启动选项示例：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

其中：

- `--appid` 用于稳定定位 profile；
- `--` 后面保留 Steam 原始命令；
- `%command%` 让 Runner 能在未来兼容原始 Steam / Proton 启动环境。

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

## 平台分层

```text
core/
  config
  profile
  launch_option

runner/
  platform/windows
  platform/unix

manager/
  gui
  steam_scan
  profile_editor
  launch_options_apply
```

`core` 不应该依赖 Windows API、Linux API 或 GUI 框架。

平台差异集中在：

- Steam 安装位置；
- Steam 用户目录；
- LaunchOptions 写入方式；
- 进程等待方式；
- Proton / SteamOS 启动环境。

## 设计边界

SteamWrapper v2 不做：

- 不注入 DLL；
- 不修改 Steam 客户端；
- 不破解游戏；
- 不绕过 DRM；
- 不常驻后台；
- 不联网。

SteamWrapper v2 只做：

- 配置自定义启动目标；
- 生成或应用 Steam Launch Options；
- 运行时启动目标程序；
- 等待目标退出以配合 Steam 统计时间；
- 提供可恢复的配置变更。
