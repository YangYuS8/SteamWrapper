---
title: "SteamWrapper v2 架构设计"
description: "WinUI Manager、C# 应用服务、独立 Rust Runner 与稳定契约。"
---

<a id="steamwrapper-v2-架构设计"></a>

## 核心目标

**WinUI 3 是唯一的 Manager 实现。**`apps/manager-winui` 中的 Windows 预览采用 C#/XAML 与 C# 应用服务，Steam 通过既有 TOML/CLI 契约启动独立 Rust Runner。两者之间没有 Rust FFI、管理 helper 或后台服务。详见 [Windows 设计](/SteamWrapper/zh-cn/project/design/windows-v2/)。

玩家配置一次，之后关闭 Manager，从 Steam 点击开始。移除旧 UI 不等于完成安装、更新或稳定发布验收。Linux 保留 Rust Runner 兼容性与进程 CI；当前没有 Linux GUI，新增 SteamOS/Proton 工作仍延期。

## 运行流程

```text
Steam 开始游戏
→ 稳定 Runner --appid <appid> -- %command%
→ 读取 profiles.toml
→ 启动配置的目标和参数
→ 按配置等待
→ 退出
```

Steam 状态、时长、成就与云行为分别需要限定范围的验收。

```text
打开 WinUI Manager
→ 扫描本地 Steam manifest 与封面
→ 显示自定义／本地图片、可选缓存／CDN 回退或友好占位
→ 选择实际程序/启动器并保留高级设置
→ 保存配置并安装/检查稳定 Runner
→ 生成/复制启动项，由用户手动应用
```

自动应用或恢复 Steam 启动项尚未实现。

## Launch Options 合约

```text
"<stable-runner-path>" --appid "123456" -- %command%
```

`--appid` 选择配置，Steam 原命令保留在 `--` 后。启动项引用稳定 Runner，不引用 Manager 或临时／带版本的包路径。Runner 接收并记录 `steam_command`，但实际执行 profile 的 target/args，不执行或追加原命令。保留 `%command%` 是兼容边界，不代表 Proton 包装已完成。

## 分层

```text
apps/manager-winui/SteamWrapper.Manager       # C#/XAML、界面状态、选择器、剪贴板
                 ↓ C# 调用
apps/manager-winui/SteamWrapper.Application   # 配置、本地 Steam、日志、Runner 安装
                 ↓ profiles.toml / 稳定 Runner 文件
crates/runner                               # Steam 启动的 CLI 和进程生命周期
                 ↓ Rust 调用
crates/core                                 # 共享配置/路径契约
```

`ProfileStore` 使用 Tomlyn 语法跨度只修改编辑字段，保留其他文本和未知数据。新 Windows 配置显式使用 `job`；旧配置省略 `wait_mode` 时仍为 `root`。保存采用协作锁、字节版本冲突检查、同目录刷新后的临时文件、原子替换和备份。内联／点号 profile 只读。非协作编辑器仍可能在最终检查与替换之间产生竞态。

`SteamScanner` 读取本地元数据／封面。`CoverService` 管理可选图片请求及有界缓存，WinUI 提供图片解码并异步更新可见行。`RunnerInstaller` 在报告就绪前检查摘要绑定的版本元数据与实际共享文件位置，使用稳定路径和原子替换，保留较新兼容版本，拒绝未知替换。GUI 不启动或等待游戏。跨语言测试和受控进程 fixture 验证实际 Rust 消费，不进入发布目录。

`ProfileSteamInstallation` 按 AppID 关联只读 Steam 路径用于显示，不序列化，也不覆盖 `game_dir`。后者是实际运行文件夹，可以位于 Steam 库外。详见[汉化目录分离](/SteamWrapper/zh-cn/guides/translated-games/)。

### Manager 部署

`apps/deployment-windows` 包含不依赖 GUI 的 C# 部署库和 NativeAOT `SteamWrapper.exe` 启动器／辅助程序。Manager 初始化前取得共享安装锁，保持到进程退出，健康确认绑定当前事务。Inno 和显式修复／回退／卸载共用独占锁及清单／日志引擎。该组件只启动 Manager，不接触游戏、Steam 启动项或稳定 Runner／数据目录。详见[安装器所有权与恢复](/SteamWrapper/zh-cn/guides/installer-preview/)。

应用更新认证是注入信任的内部服务，没有启用生产源或更新界面。SignPath 签名和 D1b 干净客户端交付仍需外部批准／独立验收。

### `crates/core`

Core 是不依赖 GUI 的 Rust 库。Runner 使用其 Profile/TOML 与路径语义。现有 Steam 元数据、封面 URL 和启动项工具不为 WinUI 提供服务：C# 直接实现文件契约。Core 不含平台进程等待 API。

### `crates/runner`

Runner 负责 CLI 解析、目标启动、平台等待和运行日志，不依赖 GUI、WebView 或 .NET。Manager 检查和安装其文件，不参与其进程生命周期。

<a id="cratesmanager-core"></a>
<a id="appsmanager-dioxus"></a>

### 已归档的管理链

Dioxus Manager、`crates/manager-core`、其 E2E 和旧 GUI 发布链已从当前开发中移除。ca6a09e 中的 [UI 源码](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus)与[服务源码](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core)仅供历史参考。[2026-09-07 比较记录](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)保留测量和限制，不代表第二套受支持的 Manager。

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

WinUI 使用与 `profiles.toml` 同级的 `ui-settings.json`。没有 `language` 键时跟随已支持的系统界面文化；`zh-CN`、`zh-SG` 与明确的 `zh-Hans` 文化显示简体中文，其余显示英语。已保存的明确选择优先，无效明确值或无法读取的设置回退英语。规范值为 `en-US` 与 `zh-CN`，兼容去除两端空白、不区分大小写的 `en`、`zh-SG`、`zh-Hans` 别名。读取或仅保存封面偏好不会保存识别出的语言。保存保留未知 JSON 字段，拒绝覆盖不合法的设置。服务诊断仍固定使用英语。

同一文件中的 `steamCdnCovers` 是独立布尔值，缺失时默认 `false`。两种偏好的写入互相保留，并保留未知字段；只有成功持久化的变更才会开启下载。写入失败时保留此前偏好。

侧栏选择器在持久化成功后刷新应用自有文案；失败时保留原语言并报告错误。未保存输入、用户名称、路径、参数、协议标识和日志保持不变。语言不改变 Runner/TOML 行为。

## 等待模式

| 模式 | 用途 |
| --- | --- |
| `root` | 等待直接启动的目标 |
| `job` | 新 Windows 配置默认值；等待未脱离的 Job 成员 |
| `process_name` | 启动器退出后，等待本次启动观察到的指定名称 |
| `process_group` | 保留的 Linux 模式，等待同一 POSIX 进程组的派生进程 |
| `none` | 启动后立即退出 |

旧配置缺少 `wait_mode` 时均解析为 `root`。当前没有创建配置的 Linux Manager。`process_name` 排除启动前已存在的同名 `(PID, start_time)`，但名称不能证明归属。Windows `job` 等待完成后返回启动器状态，不一定是游戏退出码。生命周期结论应由平台进程测试与限定范围的真实证据支持。

## 分发与稳定安装

当前 Windows 使用完整自包含预览布局，可本地生成，也可通过版本标签／手动发布工作流构建。日常 CI 只测试和编译，不打包应用。完整解压后从普通资源管理器打开 Manager。每用户安装器、应用更新器及自动 Steam 写入仍未实现；标签包为未签名预发布，交付验收仍待完成。准确触发方式见[分发说明](/SteamWrapper/zh-cn/development/distribution/)。

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

`%LOCALAPPDATA%\Programs\SteamWrapper` 是未来 Manager 安装位置的提案。Runner 安装保留配置及其他用户数据。

现有 Linux Runner 使用 `$XDG_DATA_HOME/SteamWrapper/`，缺省为 `~/.local/share/SteamWrapper/`，Runner 位于 `bin/steamwrapper-runner`。保留其中已有数据；当前不提供 Linux GUI 或自动安装器。

## 封面与安全边界

WinUI 优先读取各用户的自定义 Steam `config/grid/` 图片，再读取本地 `appcache/librarycache/`，支持带哈希的文件名及嵌套哈希目录；不会写入这些目录。缺失或不可读的图片显示友好占位，不阻塞编辑、保存或 Runner。

官方 Steam CDN 回退是需要明确启用的偏好，默认关闭，仅处理本地已发现 AppID。请求包含单个 AppID 和普通 HTTPS 连接信息，不查询账号、不上传游戏库、不使用 Cookie／身份认证，也不接入第三方元数据服务。仅允许通过 HTTPS 访问 `shared.steamstatic.com` 和 `shared.fastly.steamstatic.com`，每次手工跟随重定向前执行相同检查。固定竖图地址只提供尽力获取：新图片可能需要其他路径，404 时保留占位，不查询其他服务。Valve 文档说明了[库竖图及半尺寸版本](https://partner.steamgames.com/doc/store/assets/libraryassets?l=english)，文件名并不保证解码后一定为 600×900。

`CoverService` 最多同时进行两个下载，每次操作最多十秒，包括响应读取与重定向；最多跟随两次重定向，编码图片数据不超过 4 MiB。图片验证同样限制为两个并发操作。WinUI 使用可用的 Windows codec 解码静态 JPEG、PNG 或 WebP，拒绝损坏内容、单边超过 4096 像素或总计超过八百万像素的图片。请求失败后冷却五分钟，不自动重试。关闭回退会取消当前对话框中进行的请求，并阻止该对话框的新请求。

仅下载的封面由 `%LOCALAPPDATA%\SteamWrapper\cache\covers\` 管理：配额为 32 MiB／64 个文件，三十天过期，并有淘汰与清理入口。缓存变更使用跨进程独占文件锁；缓存被占用时保留占位，或显示可恢复的清理错误。清理不影响自定义图片、Steam 缓存、游戏、配置、Runner 或 SteamWrapper 的其他数据。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)及剩余的 [P0 原生验收](/SteamWrapper/zh-cn/project/roadmap/)。

SteamWrapper 不注入 DLL、不修改 Steam／游戏文件、不绕过 DRM，也不上传用户数据。未解决的存档／云冲突会停止真实验收。

## Manager 技术边界

WinUI/C# Application 与 Rust Runner 是唯一当前产品路径。Dioxus 和 Tauri/React 属于历史实现；Node/pnpm 用于开发资源和静态文档，不是桌面运行时。

Windows 预览证据不证明安装器／更新／卸载或干净系统验收。Linux Runner CI 不证明 Linux GUI、Steam Deck 支持或 Proton 集成。详见[分发](/SteamWrapper/zh-cn/development/distribution/)和[路线图](/SteamWrapper/zh-cn/project/roadmap/)。
