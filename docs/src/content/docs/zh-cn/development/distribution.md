---
title: "v2 分发与安装方案"
description: "WinUI 预览目录、稳定 Runner 安装及剩余 Windows 交付工作。"
---

<a id="v2-分发与安装方案"></a>

## 原则

WinUI 是唯一当前 Manager。交付包含 **Windows 11 24H2 x64 自包含预览目录**和未签名的[每用户安装器预览](/SteamWrapper/zh-cn/guides/installer-preview/)。版本标签仍触发便携 ZIP 预发布，手动工作流也构建和测试安装器，但不公开发布。常规拉取请求与 `main` 只检查，不打包应用。尚未启用更新器，自动 Steam 启动项应用／恢复也未实现。

安装器预览包含运行时文件，使用固定每用户目录且通常无需提权；仅卸载 Manager 时保留稳定 Runner 和数据。Manager 占用会阻止变更，不强制结束进程。未知文件保留，复制中断的暂存文件可以隔离后人工排查。注册表／快捷方式／断电整体恢复、干净客户端交付及稳定状态仍是独立门槛。

[已批准的 Windows 交付方案](/SteamWrapper/zh-cn/project/design/windows-delivery/)区分已实现的部署／签名保护与剩余 Foundation 批准、已签名发布及可信客户端更新阶段。详见[代码签名政策](/SteamWrapper/zh-cn/project/design/code-signing/)，尚无可用生产证书。

GitHub/CNB 二进制发布须检查实际可下载产物。源码同步或发布说明不等于二进制交付。干净系统安装、更新、恢复和卸载需要单独 Windows 证据。

## WinUI 本地预览目录

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

`target/winui/publish` 包含 Manager、.NET、Windows App SDK、原生／本地化资源、品牌资源及 `Runner/`。发布工作流将这套完整布局打包为 Windows x64 portable ZIP。解压全部文件后从普通资源管理器打开 Manager；单独的安装器预览也包含这套完整布局，Manager 本身不是单文件应用。

`pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox` 使用一次性隔离数据；普通启动使用真实 `%LOCALAPPDATA%`。开发宿主可能重定向 AppData，因此路径存在不能证明 Steam 看到相同文件。Manager 检查最终共享文件位置，发现重定向时报告未就绪。详见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。

发布构建 Rust Runner，生成包含 schemaVersion 1、contractVersion 2、Cargo 版本与实际 SHA-256 的 `runner-manifest.json`。C# `RunnerInstaller` 服务检查资源字节／元数据并原子安装到稳定 `bin/`；它不是 Windows setup 安装器。较新兼容版本保留，未知版本或同版本不同摘要拒绝覆盖。摘要绑定的 `runner-releases/` 元数据支持二进制／sidecar 提交中断后的识别。摘要只证明一致性，不认证发布者。

相同的已有 Runner 可被识别并采用；未知且不同的二进制会被保留，并提示使用匹配包。文件占用失败保留旧 Runner／配置。Runner 资源缺失不阻止编辑配置，但不显示已就绪的启动项。

统一品牌资源为 `assets/brand/steamwrapper.svg`、`.png`、`.ico`，WinUI 项目包含适用的图标／资源。修改原创 SVG 后执行 `pnpm brand:generate`，用 `pnpm brand:check` 验证派生文件。pnpm 和 `@resvg/resvg-js` 是开发工具，不是运行要求。

<a id="dioxus-desktop-bundle"></a>

## Dioxus 包检查归档 — 2026-09-08

Dioxus Manager、NSIS/AppImage 链与 Native E2E 已从当前开发中移除。[ca6a09e 的旧打包配置](https://github.com/YangYuS8/SteamWrapper/blob/ca6a09e/apps/manager-dioxus/Dioxus.toml)属于归档，不是当前分发步骤。

2026-09-08 的最终本机 Dioxus NSIS 构建生成 `SteamWrapperManager_0.2.0_x64-setup.exe`，大小为 **5,167,920 字节**，包含英语和简体中文（`English`、`SimpChinese`）安装器资源。安装器及实际随包 Manager PE 均包含统一图标的全部 10 个尺寸（16、20、24、32、40、48、64、96、128、256 像素），每一帧 SHA-256 均与统一 ICO 对应帧一致。检查确认包含 WebView2 下载引导程序，不包含离线运行时安装器，WebView 安装配置为 `silent = true`。随包 Runner 为 **1,180,160 字节**，SHA-256 与 release Runner 一致。本机记录为 `target/dioxus-nsis-i18n-verified-20260908T095032Z/inspection.json` 及同一忽略目录中的 `bundle.log`。这只是构建和包内容检查，没有运行安装器，不能证明安装、运行时下载、更新／卸载、干净系统行为或 WinUI 交付已通过。

## Windows

标签预览仍为完整便携 ZIP，明确请求的手动工作流也生成未签名安装器。产物仍未签名，公开发布保持预发布。安装器目前仅有隔离验收，公开安装器／稳定交付前仍需干净 Windows 11 客户端和生产签名。

固定安装根目录为 `%LOCALAPPDATA%\Programs\SteamWrapper`，Steam 只引用独立数据目录中的稳定 Runner。`apps/deployment-windows` 拥有版本目录、清单、启动器和锁／日志恢复，Inno 拥有维护程序副本、卸载注册和快捷方式。修复／回退边界见[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)。

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

日常 Windows CI 测试 C# Application 服务与 Windows 解码器，验证跨语言契约和真实 Runner fixture，并编译实际 WinUI Manager。Rust CI 保留格式／检查／测试门禁和受支持的 Windows/Linux 进程测试。这些运行保留测试证据，但不执行自包含发布，也不上传应用包。GitHub Pages 继续独立从 `main` 自动部署文档。

发布构建对所选源码重跑测试与编译门禁，再执行自包含发布、全部发布／恢复回归及实际包内容检查。portable ZIP 包含两种语言资源和经过验证的 Runner；校验和与发布元数据标识准确版本、提交和 Windows x64 平台。预发布不证明干净系统安装、更新、回滚或卸载通过；签名与 Windows 稳定交付仍是独立门槛。

## 准备并触发发布

[WinUI version release 工作流](https://github.com/YangYuS8/SteamWrapper/blob/main/.github/workflows/winui-release.yml)将应用交付与日常 CI 分开：

| 触发方式 | 结果 |
| --- | --- |
| 拉取请求或推送 `main` | Rust Windows/Linux 检查、C# 测试／契约与实际 WinUI 编译；不生成应用压缩包 |
| 推送版本标签 | 完整门禁、完整 Windows x64 portable ZIP、校验和／元数据及双语说明；未签名 GitHub 预发布 |
| 在所选分支／ref 上 **Run workflow** | 完整门禁与完整 `SteamWrapper-WinUI-preview-windows-x64` 产物；不公开发布 |
| `main` 上相关文档变更 | 独立的文档检查与 GitHub Pages 部署 |

发布标签采用 `vMAJOR.MINOR.PATCH`，可带 SemVer 预发布后缀，例如 `v0.2.1-preview.1`。三位基础版本必须与 `SteamWrapper.Manager.csproj` 的 `<Version>` 及 `crates/core/Cargo.toml`、`crates/runner/Cargo.toml` 的包版本一致。提交必须在 `main` 的历史中，且对应版本中须包含 `releases/<tag>.en.md` 与 `releases/<tag>.zh-CN.md`。无效标签、版本不匹配或缺失说明均会在交付前失败。WinUI 交付门槛仍未完成时，即使标签没有预发布后缀，也会标为 GitHub 预发布。

当前源码版本为 `0.2.1`，因 Runner 新 PE 资源改变字节而递增。不要覆盖已有标签或历史发布。未来需协调 Rust、Manager、Application、部署产品版本及锁文件，并提供完整双语说明。打标签前确认所选主线提交已通过 CI；合并此次工作不会创建公开新版本。

例如，已审阅的改动将三个源码版本都改为 `0.2.1`，并加入两份 `v0.2.1-preview.1` 说明后：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git tag -a v0.2.1-preview.1 -m "WinUI Windows preview 0.2.1-preview.1"
git push origin v0.2.1-preview.1
```

这只是发布操作示例，不是要求现在创建该标签；执行前核对所选提交。工作流检出准确标签并重跑门禁，不沿用之前的分支构建。它先创建草稿，上传并验证全部附件，再公开预发布，不将其标为最新稳定版。附件为 `SteamWrapper-<tag>-win-x64.zip`、`<tag>.en.md`、`<tag>.zh-CN.md`、`release.json` 和 `SHA256SUMS`。ZIP 同时包含根目录 `LICENSE` 及 `ReleaseNotes/` 中的双语说明。

按需预览使用 **Run workflow** 并选择 ref。没有发布模式输入：所有手动运行都只生成预览，即使选择了标签也不公开发布。发布上传失败时，解决原因后优先使用 **Re-run failed jobs**：发布 job 会复用同一个不可变的 `SteamWrapper-WinUI-release-assets` 构建产物。**Re-run all jobs** 会重新构建和打包；如果同版本的字节发生变化，发布必须拒绝覆盖。不同内容应使用新版本，不移动已发布标签，也不覆盖已发布附件。

<a id="发布渠道"></a>

## 发布渠道

GitHub Releases 是版本标签二进制发布渠道。如果仓库配置了具有仓库 release 读／写权限的 `CNB_RELEASE_TOKEN`，以及已有的源码／标签同步密钥 `CNB_GIT_TOKEN`，工作流也能向 CNB 复制同一组附件，并对照生成的 SHA-256 验证上传后的下载副本。没有 release token 时跳过 CNB 二进制步骤；常规 `main` 源码同步独立保留。

源码镜像或只有说明的 release 不等于二进制交付。宣传渠道前须检查该标签工作流实际的 GitHub/CNB 上传与下载结果，如实记录失败或跳过的镜像。旧 CNB 独立说明发布器已移除，避免与标签二进制工作流竞争。上传通过仍不完成干净系统、签名、更新器或卸载器验收。

<a id="当前-dioxus-封面策略"></a>

## 封面与网络边界

当前 WinUI 优先读取 Steam 本地 `appcache/librarycache/` 和各用户 `config/grid/` 图片，再使用有效的 SteamWrapper 封面缓存。缺失或不可读时保留占位图；网络请求需要下面的明确选项。

官方 Steam CDN 封面回退需明确选择开启，本地优先、默认关闭。仅为本地已发现 AppID 获取缺失封面，采用 HTTPS 主机／重定向白名单与有界传输／解码图片尺寸。下载的图片仅存放在 SteamWrapper 的 `cache/covers/`，提供配额、过期、淘汰与清理入口。关闭后取消下载并阻止新请求，有效缓存仍可离线使用。清理保留自定义图片、Steam／游戏文件、配置和 Runner，不包含账号查询、游戏库上传或第三方元数据服务。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)、[实现限制](/SteamWrapper/zh-cn/development/architecture/#封面与安全边界)及剩余的[原生／玩家验收](/SteamWrapper/zh-cn/project/roadmap/)。
