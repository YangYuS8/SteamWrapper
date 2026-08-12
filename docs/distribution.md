# v2 分发与安装方案

## 原则

SteamWrapper v2 是 Windows、Linux 与 SteamOS / Steam Deck 的长期支持主线。安装、更新和卸载必须面向普通玩家：少手工步骤、少术语、稳定 Runner 路径、不破坏已有 profile。

- 安装默认不需要管理员权限，也不要求用户理解 Runner / TOML；
- 更新覆盖 Manager 程序，但保留稳定用户数据；
- 卸载默认删除程序本体，清理用户数据必须是明确选择；
- 正式 release 同步 GitHub Release 与 CNB Release；
- 改写 Steam Launch Options 前必须先备份，后续一键应用功能不得在 Steam 运行时盲写配置。

## Dioxus Desktop bundle

Manager 由 Dioxus `0.7.10` 打包，配置位于 `apps/manager-dioxus/Dioxus.toml`：

- Windows：NSIS CurrentUser 安装器，图标和 WebView 安装模式在 `[windows]` 配置；
- Linux：AppImage 预览包，bundle 中携带 WebKitGTK runtime 依赖与 Dioxus Manager 资源；
- Runner：`[bundle].resources` 显式列出两个平台名称，构建机器只填入自己的非空目标文件；空的另一平台占位文件只用于满足 Dioxus manifest，不得进入对应平台发布物的 Runner 使用路径。

Dioxus `asset_dir` 仅解决 Manager CSS / SVG 等 UI 资产；Runner 必须由 `[bundle].resources` 明确包含。目录不被当前 bundler 支持为 resource entry，因此资源以两个文件路径列出。

## Windows

面向普通 Windows 玩家时主推：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

次要发布物：

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

NSIS 安装器使用 Dioxus bundle 的 `CurrentUser` 模式；建议安装位置：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

更新时运行新版 setup.exe 覆盖 Manager，稳定用户数据不随安装目录删除。portable zip 面向高级用户；即便 Manager 被移动或删除，Steam 启动项仍应只引用稳定 Runner。

## Linux / SteamOS

预览发布物：

```text
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

- AppImage：替换旧 AppImage 即可更新；
- tar.gz：解压覆盖程序目录，保留 XDG 数据目录；
- Steam Deck：优先支持桌面模式，不写入只读系统区域；
- Proton：保留 Steam 展开的 `%command%`；专用包装策略仍待平台实机验证。

## 稳定用户数据

Windows：

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
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

`$XDG_DATA_HOME` 未设置时使用 `~/.local/share/SteamWrapper/`。

Steam Launch Options 只能引用稳定 Runner：

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

## Runner 分发与安装

构建时先 stage 当前平台 release Runner：

```bash
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
```

Linux 资源名为 `steamwrapper-runner`，Windows 资源名为 `SteamWrapperRunner.exe`。它们是 bundle 中只读资源，不是 Steam Launch Options 的目标。

首次启动或设置页“安装 / 修复 Runner”执行：

```text
随包 Runner
→ 临时文件
→ flush + SHA-256 校验
→ 原子替换
→ 稳定用户数据目录的 bin/Runner
```

- 摘要一致时不重复复制；
- 缺失、损坏或摘要不一致时安装 / 修复；
- 仅触碰稳定 `bin` 下的 Runner，不覆盖 `profiles.toml`、`logs`、`backups`、`cache`；
- Windows 如旧 Runner 被 Steam 占用，替换失败时保留旧文件并提示玩家退出游戏后重试。

## CI / release 验证

release workflow 应：

1. stage 当前平台 release Runner；
2. 运行 Rust、Dioxus 与 E2E 类型质量门禁；
3. 用 `dx bundle --release --package-types nsis|appimage` 生成当前平台包；
4. 解包 Windows NSIS 并验证非空 `SteamWrapperRunner.exe`；
5. 解包 Linux AppImage 并验证非空 `SteamWrapperManager/steamwrapper-runner`；
6. 证明正式 Rust graph 不含 WDIO / embedded WebDriver；
7. 上传命名一致的 bundle 与 SHA256SUMS。

Linux AppImage 的本机验证不代表 Windows NSIS 或 Steam Deck 已验证；这些必须在各自 CI 或设备中取得实际证据。

## 本地封面策略

第一阶段不接入在线 API。Manager 只读取：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

没有封面时显示占位图即可。

## 发布渠道

```text
GitHub Release：海外用户、开发者与自动化下载
CNB Release：国内玩家的 README 优先下载入口
```

每次正式 release 应包含平台 bundle、SHA256、中文更新说明和简短的安装 / 更新 / 卸载说明。版本命名必须一致，避免玩家在 GitHub 与 CNB 之间困惑。
