---
title: "v2 分发与安装方案"
description: "包内容、稳定 Runner 安装及尚待完成的交付要求。"
---

<a id="v2-分发与安装方案"></a>

## 原则

SteamWrapper v2 当前优先做好 Windows 安装、更新与卸载。WinUI 预览已支持本地自包含目录发布，每用户安装器尚未实现；下文 Dioxus bundle 命令继续描述旧交付链。见 [部署评估](/SteamWrapper/zh-cn/project/decisions/winui3/#部署与稳定路径)与 [Windows 主方案](/SteamWrapper/zh-cn/project/design/windows-v2/#7-安装更新卸载)。Linux / SteamOS 后续交付暂缓。稳定 Runner 路径和已有 profile 必须保留。

- 安装默认不需要管理员权限，也不要求用户理解 Runner / TOML；
- 更新覆盖 Manager 程序，但保留稳定用户数据；
- 卸载默认删除程序本体，清理用户数据必须是明确选择；
- GitHub Release 与 CNB Release 双渠道为待验收的正式交付目标；
- 改写 Steam Launch Options 前必须先备份，后续一键应用功能不得在 Steam 运行时盲写配置。

WinUI 目标安装包同时携带 .NET 与 Windows App SDK，独立 Rust Runner 随包安装到稳定目录，不包含 Rust FFI bridge。实际安装器需在无开发环境的 Windows 11 x64 上验证，项目属性不等于零运行时准备已实现。

默认卸载只移除 Manager，保留仍可能被 Steam 启动项引用的稳定 Runner、配置、日志和备份。完整移除 Runner 前需先解除引用；手动粘贴或无法枚举的启动项不能假定已恢复。更新时也不能仅因摘要不同就让旧 Manager 降级稳定 Runner，需明确版本兼容与占用失败策略。这些是新安装器验收要求，当前 Dioxus 实现不因此获得已验证声明。

## WinUI 本地预览目录

`mise run winui:publish` 在 `target/winui/publish` 生成 Windows 11 24H2 x64 预览。整个目录包括 Manager、.NET、Windows App SDK、品牌资源与 `Runner/`；没有单 EXE 或安装器承诺。`winui:sandbox` 使用一次性隔离目录启动预览，普通运行 EXE 则使用真实 `%LOCALAPPDATA%`。

构建从 Runner Cargo 版本和实际二进制 SHA-256 生成 `runner-manifest.json`（schemaVersion 1 / contractVersion 2）。C# 安装器只接受摘要匹配的资源，原子安装到稳定 `bin/`；较新兼容版本保留，未知版本或同版本不同摘要拒绝覆盖。摘要绑定的 `runner-releases/` 元数据支持二进制/sidecar 提交中断后的识别。摘要用于一致性校验，不是发行者签名；不能据此宣称安装包已认证。

现有 Runner 若与随包字节相同，可被确认并采用；未知且不同的已有 Runner 会提示使用匹配安装包，不能自动删掉强装。更新占用失败保留旧二进制和用户配置。Manager 缺少 Runner 资源仍可编辑和保存配置，但不会给出“已就绪”的启动项。

发布链默认切换、安装器签名/更新/卸载、干净 Windows VM 与适用的真实 Steam 验收门槛留在阶段 C。已记录的本机游戏通过结果单独见[真实验收](/SteamWrapper/zh-cn/project/validation/steam/)。

## Dioxus Desktop bundle

Manager 由 Dioxus `0.7.10` 打包，配置位于 `apps/manager-dioxus/Dioxus.toml`：

- Windows：NSIS CurrentUser 安装器，图标和 WebView 安装模式在 `[bundle.windows]` 配置，安装器设置位于 `[bundle.windows.nsis]`；
- Linux：AppImage 预览包，bundle 中携带 WebKitGTK runtime 依赖与 Dioxus Manager 资源；
- Runner：`[bundle].resources` 显式列出两个平台名称，构建机器只填入自己的非空目标文件；空的另一平台占位文件只用于满足 Dioxus manifest，不得进入对应平台发布物的 Runner 使用路径。

Dioxus `asset_dir` 仅解决 Manager CSS / SVG 等 UI 资产；Runner 必须由 `[bundle].resources` 明确包含。目录不被当前 bundler 支持为 resource entry，因此资源以两个文件路径列出。

统一品牌资源为 `assets/brand/steamwrapper.svg`、`.png` 和 `.ico`，Dioxus 中保留匹配副本。修改原创 SVG 后执行 `mise run brand:generate`，用 `mise run brand:check` 验证已提交的输出。pnpm 和 `@resvg/resvg-js` 仅是开发期资源工具，不是应用运行时依赖；打包时保留资源检查。

2026-09-08 的最终本机 Dioxus NSIS 构建生成 `SteamWrapperManager_0.2.0_x64-setup.exe`，大小为 **5,167,920 字节**，包含英语和简体中文（`English`、`SimpChinese`）安装器资源。安装器及实际随包 Manager PE 均包含统一图标的全部 10 个尺寸（16、20、24、32、40、48、64、96、128、256 像素），每一帧 SHA-256 均与统一 ICO 对应帧一致。检查确认包含 WebView2 下载引导程序，不包含离线运行时安装器，WebView 安装配置为 `silent = true`。随包 Runner 为 **1,180,160 字节**，SHA-256 与 release Runner 一致。本机记录为 `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` 及同一忽略目录中的 `bundle.log`。这只是构建和包内容检查，没有运行安装器，不能证明安装、运行时下载、更新／卸载、干净系统行为或 WinUI 交付已通过。

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

## Linux / SteamOS（后续交付暂缓）

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
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Linux / SteamOS：

```text
$XDG_DATA_HOME/SteamWrapper/
  profiles.toml
  ui-settings.json
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

## 当前 Dioxus 封面策略

Manager 优先读取本机 Steam 缓存：

```text
<Steam 安装目录>/appcache/librarycache/
<Steam 安装目录>/userdata/<steamid>/config/grid/
```

缓存缺失时，它只使用已从本地 manifest 读取的 AppID 访问公开 Steam CDN：

```text
https://cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg
```

该请求不包含 Steam 用户名、库清单、profile 或任何 API Key；公开 CDN 的响应可按其 HTTP 缓存策略复用。应用不写入新封面文件，离线、限流、404 或图片加载失败时保留“封面暂不可用”占位，并继续允许配置游戏。不得把此有限回退扩展为第三方封面 API 或用户库数据上传。

新 WinUI 首版只读取本地封面或显示占位；上述 CDN 描述保留为当前实现事实。

## 发布渠道

```text
GitHub Release：海外用户、开发者与自动化下载
CNB Release：国内玩家的 README 优先下载入口
```

每次正式 release 应包含平台 bundle、SHA256、英语及完整简体中文更新说明和简短的安装 / 更新 / 卸载说明。版本命名必须一致，避免玩家在 GitHub 与 CNB 之间困惑。
