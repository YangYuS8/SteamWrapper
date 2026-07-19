# v2 分发与安装方案

## 原则

SteamWrapper v2 是长期支持主线，分发目标覆盖 Windows、Linux 与 SteamOS / Steam Deck。安装、更新、卸载都必须面向普通游戏玩家设计：少解释、少选择、少手工复制，尽量做到“下载 → 双击 → 下一步”。Runner 路径必须稳定，不能指向临时解压目录。

核心体验原则：

- 安装：默认无需管理员权限，不要求命令行，不要求用户理解 Runner / profiles 细节；
- 更新：新版安装包应能覆盖安装并保留用户配置；Manager 后续应提供“检查更新”入口；
- 卸载：走系统标准卸载入口，卸载程序本体时默认保留用户配置，并提供“同时清理用户数据”的明确选项；
- 国内下载：正式发布时同步 GitHub Release 与 CNB Release，README 优先给国内玩家可用的 CNB 下载入口；
- 失败可恢复：应用 Steam 启动项前必须备份，更新前后都不能破坏已配置游戏。

## Windows

面向普通 Windows 玩家时，主推安装程序。

主推：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

备选：

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

## setup.exe

setup.exe 使用 Tauri 的 NSIS 打包目标。

用户体验目标：

```text
双击安装程序
→ 下一步
→ 选择安装路径
→ 安装
→ 完成
```

更新体验目标：

```text
下载新版 setup.exe
→ 双击运行
→ 自动覆盖旧版本
→ 保留 profiles.toml / logs / backups / cache
→ 完成
```

后续 Manager 内应提供“检查更新”入口：

- 国内玩家默认引导到 CNB Release；
- 海外或开发者可选择 GitHub Release；
- 显示当前版本、最新版本、更新说明和下载按钮；
- 更新不应要求用户重新配置游戏。

卸载体验目标：

```text
系统设置 / 控制面板卸载 SteamWrapper
→ 默认删除程序本体
→ 默认保留用户配置
→ 可选清理 %LOCALAPPDATA%\SteamWrapper\ 用户数据
```

建议安装位置：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

原因：

- 默认不需要管理员权限；
- 符合普通 Windows 用户习惯；
- 升级和卸载路径清晰；
- 不污染游戏目录。

## 发布渠道

正式发布时采用双渠道：

```text
GitHub Release：面向海外用户、开发者和自动化下载
CNB Release：面向国内玩家，作为 README 中文入口的优先下载渠道
```

每次 release 应包含：

- Windows setup.exe；
- Windows portable zip；
- Linux AppImage 或 tar.gz；
- SHA256 校验和；
- 中文更新说明；
- 简短的安装 / 更新 / 卸载说明。

版本命名保持一致，避免 GitHub 与 CNB 产物名称不同导致玩家困惑。

## 用户数据目录

用户配置、日志、备份和 Runner 稳定路径放在：

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Steam Launch Options 应该引用：

```text
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

不要引用安装器临时路径，也不要引用 portable zip 的临时解压路径。

## portable zip

portable zip 面向高级用户和不想安装的玩家，结构大致为：

```text
SteamWrapperManager.exe
SteamWrapperRunner.exe
README.zh-CN.md
```

首次启动 Manager 时，如果检测到 portable 模式，应该提示用户把 Runner 安装到稳定路径：

```text
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

否则用户移动或删除解压目录后，Steam 启动选项会失效。

portable 更新方式应足够直白：下载新版 zip，解压覆盖 Manager；Runner 稳定路径和用户配置不随 portable 解压目录移动。

## Runner 分发策略

Manager 的正式安装包会通过 Tauri v2 官方 `bundle.resources` 机制携带与当前平台匹配的预构建 Runner。构建阶段先显式执行：

```bash
cargo build --release --package steamwrapper-runner
```

官方机制说明：<https://v2.tauri.app/develop/resources/>。`bundle.resources` 适用于随包只读资源；本项目不使用 `externalBin` / sidecar 执行模型，因为 Manager 不负责直接启动 Runner。

再将产物放入仅用于打包的 staging 目录。Windows 资源文件名统一为：

```text
runner/SteamWrapperRunner.exe
```

它是安装包内的只读分发资源，不是 Steam Launch Options 的目标。Manager 首次启动以及设置页的“安装 / 修复 Runner”会执行：

```text
随包 Runner
→ 写入临时文件
→ flush + SHA-256 校验
→ 原子替换
→ %LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

- 摘要一致时不重复复制；缺失、损坏或摘要不一致时才安装/修复。
- 更新过程中只触碰 `bin/SteamWrapperRunner.exe`；`profiles.toml`、`logs/`、`backups/` 与 `cache/` 保持原样。
- Windows 若旧 Runner 正被 Steam 占用，原子替换会失败并保留旧文件；Manager 在设置页显示可理解的错误，用户退出游戏后可重新修复。
- portable 包也复用同一机制：Manager 的位置可移动，稳定 Runner 与用户数据不会依赖解压目录。

Release workflow 会验证 Windows NSIS 安装包解压后存在非空的 `SteamWrapperRunner.exe`，并验证正式前端/Cargo 依赖树不包含 WDIO 或嵌入式 WebDriver。

Runner 不应该做成 Tauri GUI，也不应该依赖 WebView。它是被 Steam 调用的无界面原生程序。

## Linux / SteamOS

Linux 与 SteamOS 不再后置到 v3，而是作为 v2 LTS 的平台目标推进。

预览分发目标：

```text
SteamWrapper-v2.x.x-linux-x64.AppImage
SteamWrapper-v2.x.x-linux-x64.tar.gz
```

Linux 用户数据目录遵循 XDG 约定：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  bin/steamwrapper-runner
  logs/
  backups/
  cache/
```

如果 `$XDG_DATA_HOME` 未设置，则使用：

```text
~/.local/share/SteamWrapper/
```

SteamOS / Steam Deck 需要额外注意：

- 优先支持桌面模式配置；
- 避免依赖写入只读系统区域；
- 文档中明确 Steam Deck 用户目录、权限和恢复路径；
- Proton 场景要尽量保留 Steam 展开的 `%command%` 环境。

Linux / SteamOS 更新体验：

- AppImage：下载新版 AppImage 后替换旧文件；
- tar.gz：解压覆盖程序目录，保留 XDG 数据目录；
- 后续 Manager 内“检查更新”同样优先提供 CNB 与 GitHub 双入口。

## 本地封面策略

第一阶段不接入在线封面 API。

Manager 只读取：

```text
<Steam安装目录>\appcache\librarycache\
<Steam安装目录>\userdata\<steamid>\config\grid\
```

找不到封面时显示占位图即可。
