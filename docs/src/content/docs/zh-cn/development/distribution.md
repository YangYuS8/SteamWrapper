---
title: "v2 分发与安装方案"
description: "WinUI 预览目录、稳定 Runner 安装及剩余 Windows 交付工作。"
---

<a id="v2-分发与安装方案"></a>

## 原则

WinUI 是唯一当前 Manager。已实现的交付形式为 **Windows 11 24H2 x64 自包含预览目录**，可本地构建，也由 Windows CI 生成。WinUI 每用户安装器、标签发布流水线、应用更新器及自动 Steam 启动项应用／恢复仍未实现。移除 Dioxus 不代表这些门槛已通过。详见[安装指南](/SteamWrapper/zh-cn/guides/installation/)与[路线图](/SteamWrapper/zh-cn/project/roadmap/)。

未来安装不应要求开发工具或日常管理员权限。更新须保留用户数据和兼容的稳定 Runner。卸载应默认移除 Manager、保留 Runner 与用户数据，因为 Steam 可能仍引用它们。完整清理须明确选择并处理已知引用，不能假定手动粘贴或无法枚举的启动项已恢复。这些是验收要求，不是已有安装器行为。

GitHub/CNB 二进制发布须检查实际可下载产物。源码同步或发布说明不等于二进制交付。干净系统安装、更新、恢复和卸载需要单独 Windows 证据。

## WinUI 本地预览目录

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

`target/winui/publish` 包含 Manager、.NET、Windows App SDK、原生／本地化资源、品牌资源及 `Runner/`。Windows 预览工作流将完整目录作为 **SteamWrapper-WinUI-preview-windows-x64** 上传。解压全部文件后从普通资源管理器打开 Manager，不宣称已有单 EXE 或安装向导。

`pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox` 使用一次性隔离数据；普通启动使用真实 `%LOCALAPPDATA%`。开发宿主可能重定向 AppData，因此路径存在不能证明 Steam 看到相同文件。Manager 检查最终共享文件位置，发现重定向时报告未就绪。详见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。

发布构建 Rust Runner，生成包含 schemaVersion 1、contractVersion 2、Cargo 版本与实际 SHA-256 的 `runner-manifest.json`。C# `RunnerInstaller` 服务检查资源字节／元数据并原子安装到稳定 `bin/`；它不是 Windows setup 安装器。较新兼容版本保留，未知版本或同版本不同摘要拒绝覆盖。摘要绑定的 `runner-releases/` 元数据支持二进制／sidecar 提交中断后的识别。摘要只证明一致性，不认证发布者。

相同的已有 Runner 可被识别并采用；未知且不同的二进制会被保留，并提示使用匹配包。文件占用失败保留旧 Runner／配置。Runner 资源缺失不阻止编辑配置，但不显示已就绪的启动项。

统一品牌资源为 `assets/brand/steamwrapper.svg`、`.png`、`.ico`，WinUI 项目包含适用的图标／资源。修改原创 SVG 后执行 `pnpm brand:generate`，用 `pnpm brand:check` 验证派生文件。pnpm 和 `@resvg/resvg-js` 是开发工具，不是运行要求。

<a id="dioxus-desktop-bundle"></a>

## Dioxus 包检查归档 — 2026-09-08

Dioxus Manager、NSIS/AppImage 链与 Native E2E 已从当前开发中移除。[ca6a09e 的旧打包配置](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/apps/manager-dioxus/Dioxus.toml)属于归档，不是当前分发步骤。

2026-09-08 的最终本机 Dioxus NSIS 构建生成 `SteamWrapperManager_0.2.0_x64-setup.exe`，大小为 **5,167,920 字节**，包含英语和简体中文（`English`、`SimpChinese`）安装器资源。安装器及实际随包 Manager PE 均包含统一图标的全部 10 个尺寸（16、20、24、32、40、48、64、96、128、256 像素），每一帧 SHA-256 均与统一 ICO 对应帧一致。检查确认包含 WebView2 下载引导程序，不包含离线运行时安装器，WebView 安装配置为 `silent = true`。随包 Runner 为 **1,180,160 字节**，SHA-256 与 release Runner 一致。本机记录为 `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` 及同一忽略目录中的 `bundle.log`。这只是构建和包内容检查，没有运行安装器，不能证明安装、运行时下载、更新／卸载、干净系统行为或 WinUI 交付已通过。

## Windows

当前可下载预览为上述 CI 目录压缩包。完整 portable ZIP 与每用户 WinUI 安装器属于规划，名称和签名策略须随标签发布工作流确定。当前没有可运行的 WinUI setup.exe。

未来 Manager 安装位置提案为 `%LOCALAPPDATA%\Programs\SteamWrapper`。无论 Manager 安装或解压到何处，Steam 均只引用稳定 Runner。移动／删除 Manager 不应静默移除 Runner 或用户数据。覆盖更新、文件占用、中断替换和恢复必须先验收，再描述为受支持的交付操作。

<a id="linux--steamos后续交付暂缓"></a>

## Linux / SteamOS 兼容性

仅保留已有 Rust Runner／配置兼容性及 Linux 进程 CI。**当前没有 Linux Manager、AppImage、tar.gz GUI 或 Steam Deck GUI 交付。**保留已有 XDG 数据和稳定 Runner 名称。新增 Linux GUI／SteamOS 支持和 Proton 包装需要独立需求与实际平台证据；Windows 预览通过不证明这些范围。

## 稳定用户数据

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

现有 Linux Runner 使用 `$XDG_DATA_HOME/SteamWrapper/`，缺省为 `~/.local/share/SteamWrapper/`，包括 `profiles.toml`、`bin/steamwrapper-runner` 和 `logs/`。保留已有备份、缓存与旧 UI 设置；保留数据不代表有 Linux UI。

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

启动项不引用带版本的 Manager 目录或随包 `Runner/` 资源。

## Runner 分发与安装

WinUI 发布脚本自动准备 Windows Runner 与验证后的清单。`Runner/SteamWrapperRunner.exe` 是只读随包资源；安装后的稳定 `bin/SteamWrapperRunner.exe` 才是 Steam 的目标。

```text
验证随包 Runner 与版本/摘要元数据
→ 检查现有共享位置及版本兼容性
→ 写入并刷新临时文件
→ 验证字节并原子替换
→ 检查安装后的稳定 Runner
```

不要无谓替换相同或较新的兼容 Runner。未知／冲突版本应拒绝，而非仅因摘要不同就覆盖。安装／修复只改变自身二进制／元数据，保留配置、界面偏好、日志、备份和缓存。文件占用失败时保留可用二进制，让用户结束游戏后重试，不终止游戏。

## CI / release 验证

当前 Windows CI 验证 C# 服务、跨语言契约、真实 Runner fixture、自包含发布和安全产物替换，然后上传完整预览目录。Rust CI 继续 core／Runner 检查及受支持的 Windows/Linux 进程测试。没有 Dioxus bundle 门禁，也没有当前 WinUI 标签发布工作流。

未来 WinUI 发布须构建准确的已审阅标签，检查安装器／portable 内容，验证 Runner 元数据与本地化资源，建立签名／信任机制，发布 SHA-256 和完整双语说明，并验证 GitHub/CNB 下载一致。干净系统安装、更新、回滚和卸载仍是独立验收门槛。上传 CI 预览不等于稳定发布。

<a id="当前-dioxus-封面策略"></a>

## 封面与网络边界

当前 WinUI 读取 Steam 本地 `appcache/librarycache/` 和各用户 `config/grid/` 图片，缺失时显示占位，不下载或持久缓存封面。

官方 Steam CDN 封面回退需明确选择开启，本地优先、默认关闭。仅为本地已发现 AppID 获取缺失封面，采用 HTTPS 主机／重定向白名单与有界传输／解码图片尺寸。下载的图片仅存放在 SteamWrapper 的 `cache/covers/`，提供配额、过期、淘汰与清理入口。关闭后取消下载并阻止新请求，有效缓存仍可离线使用。清理保留自定义图片、Steam／游戏文件、配置和 Runner，不包含账号查询、游戏库上传或第三方元数据服务。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)、[实现限制](/SteamWrapper/zh-cn/development/architecture/#封面与安全边界)及剩余的[原生／玩家验收](/SteamWrapper/zh-cn/project/roadmap/)。

## 发布渠道

GitHub Releases 与 CNB Releases 是 WinUI 的目标发布渠道。源码同步或只有说明的 CNB release 都不能证明二进制交付。正式发布须提供相同二进制与 SHA-256、准确版本／提交／平台标识、签名信息、完整英中说明、已知限制及安装／更新／移除步骤。在实现并验收前，使用明确标注的 Windows CI 预览。
