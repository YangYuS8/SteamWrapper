---
title: "v2 分发与安装方案"
description: "WinUI 预览目录、稳定 Runner 安装及剩余 Windows 交付工作。"
---

<a id="v2-分发与安装方案"></a>

## 原则

WinUI 是唯一当前 Manager。交付包含 **Windows 11 24H2 x64 自包含预览目录**和未签名的[每用户安装器预览](/SteamWrapper/zh-cn/guides/installer-preview/)。版本标签将 Setup 与便携 ZIP 打包为未签名技术预发布，手动工作流也构建和测试安装器，但不公开发布。常规拉取请求与 `main` 只检查，不打包应用。源码 `0.2.5` 已包含项目认证的应用更新；公开可用性以实际版本／更新源发布为准。通用的 Steam 启动项自动应用仍未实现；新增卸载选项只移除严格识别的 SteamWrapper 命令。

安装器预览包含运行时文件，按当前用户安装且通常无需提权。`0.2.5` 的安装选项改动允许首次安装选择本地固定磁盘上的空目录，升级和修复仍使用已登记位置；开始菜单快捷方式默认开启、桌面快捷方式默认关闭，完成后可打开 Manager。仅卸载 Manager 时保留稳定 Runner 和数据；七个独立且默认关闭的卸载选项提供严格限定的还原与清理。限定范围的本机安装选项及原生检查已通过；干净客户端及更广泛恢复门槛仍未完成。Manager 占用会阻止变更，不强制结束进程。未知文件保留，复制中断的暂存文件可以隔离后人工排查。注册表／快捷方式／断电整体恢复、干净客户端交付及稳定状态仍是独立门槛。

[已批准的 Windows 交付方案](/SteamWrapper/zh-cn/project/design/windows-delivery/)区分已实现的部署／更新保护与剩余客户端验收。Windows Authenticode 为可选，独立于项目更新密钥。详见[代码签名政策](/SteamWrapper/zh-cn/project/design/code-signing/)，尚无可用生产 Windows 证书。

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

版本标签将完整便携 ZIP 与每用户 Setup 打包为没有 Windows Authenticode 签名的技术预发布；手动运行只生成预览产物，不创建公开 Release。项目签名元数据独立于 Windows 发布者证书验证应用更新，Authenticode 是可选能力。本机隔离验收不完成干净 Windows 11、更广原生交互、旧版本保留或稳定交付门槛。

默认安装根目录为 `%LOCALAPPDATA%\Programs\SteamWrapper`，首次安装可选择本地固定磁盘上其他经过验证的空目录。升级／修复留在已登记位置；迁移位置需先仅卸载 Manager 并保留数据，再重新安装。Steam 只引用独立数据目录中的稳定 Runner。`apps/deployment-windows` 拥有版本目录、清单、启动器和锁／日志恢复，Inno 拥有维护程序副本、卸载注册和快捷方式。[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)列出七项卸载选择及其保护，包括退出 Steam、备份账号文件、拒绝未处理的引用、精确选择自有文件，并始终保留 Steam 恢复备份和更新信任状态。

2026-10-03，冻结 `0.2.2` → 真正编译 `0.2.3` 的隔离运行完成 13 个符合预期的真实进程步骤，包括实际 maintenance 回滚与 Inno 再升级、迟到文件锁／未知文件拒绝、卸载与重新安装。回滚保留 1,066 个自有版本文件，六个数据夹具的哈希保持不变；新载荷包含 601 个文件及已封存的第三方法律材料。证据明确为未签名、非人工下一版本、`cleanVm=false`；更早 `0.2.1` → `0.2.2` 结果仍单独按日期保留。实际记录及剩余门槛见[测试](/SteamWrapper/zh-cn/development/testing/)。

2026-10-03 后续冻结 `0.2.3` → 真正编译 `0.2.4` 的运行完成 13 个符合预期的隔离 Inno／maintenance 步骤。实际回滚保留 1,204 个自有版本文件及维护程序／卸载器／快捷方式，再升级；迟到的自有文件锁和未知文件拒绝卸载，随后正常卸载／重装通过。六个独立数据夹具始终未变，证据记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`unsigned=true`、`cleanVm=false`。当前自有 PE 版本、五项实际 NativeAOT Host 语言和跨语言契约另行通过。这是限定范围的本机交付证据，干净客户端及版本保留门槛仍未完成。

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

日常 Windows CI 测试 C# Application 服务与 Windows 解码器，验证跨语言契约和真实 Runner fixture，并编译实际 WinUI Manager 及仅用于开发的原生 UI 工具。托管服务会话不执行该工具；实际原生运行需要解锁的交互桌面与可丢弃夹具。Rust CI 保留格式／检查／测试门禁和受支持的 Windows/Linux 进程测试。这些运行保留测试证据，但不执行自包含发布，也不上传应用包。GitHub Pages 继续独立从 `main` 自动部署文档。

发布构建对所选源码重跑测试与编译门禁，再执行自包含发布、全部发布／恢复回归及实际包内容检查。portable ZIP 包含两种语言资源和经过验证的 Runner；校验和与发布元数据标识准确版本、提交和 Windows x64 平台。预发布不证明干净系统安装、更新、回滚或卸载通过；签名与 Windows 稳定交付仍是独立门槛。

## 准备并触发发布

[WinUI version release 工作流](https://github.com/YangYuS8/SteamWrapper/blob/main/.github/workflows/winui-release.yml)将应用交付与日常 CI 分开：

| 触发方式 | 结果 |
| --- | --- |
| 拉取请求或推送 `main` | Rust Windows/Linux 检查、C# 测试／契约与实际 WinUI 编译；不生成应用压缩包 |
| 推送版本标签 | 完整构建／测试门禁、完整 Windows x64 Setup 与 portable ZIP、第 2 版校验和／元数据及双语说明；未签名技术 GitHub 预发布 |
| 在所选分支／ref 上 **Run workflow** | 完整门禁、完整 `SteamWrapper-WinUI-preview-windows-x64` 目录，以及通过测试的未签名 `SteamWrapper-WinUI-installer-preview-windows-x64` 产物；不公开发布 |
| `main` 上相关文档变更 | 独立的文档检查与 GitHub Pages 部署 |

发布标签采用 `vMAJOR.MINOR.PATCH`，可带 SemVer 预发布后缀，例如 `v0.2.5-preview.1`。三位基础版本必须与 `SteamWrapper.Manager.csproj` 的 `<Version>` 及 `crates/core/Cargo.toml`、`crates/runner/Cargo.toml` 的包版本一致，生产 Application、Deployment 和 Host 版本也须协调。提交必须在 `main` 的历史中，且对应版本中须包含 `releases/<tag>.en.md` 与 `releases/<tag>.zh-CN.md`。无效标签、版本不匹配或缺失说明均会在交付前失败。WinUI 交付门槛仍未完成时，即使标签没有预发布后缀，也会标为 GitHub 预发布。

当前协调的源码／产品版本为 `0.2.5`，已作为 [v0.2.5-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.5-preview.1) 公开发布并附完整双语说明。未签名的 [v0.2.3-preview.1 技术预览](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.3-preview.1)已由成功的[运行 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907)公开。已下载 GitHub 全部七个公开附件，核对长度、API 摘要和第 2 版清单；七个自有 PE 产品版本及下载后 NativeAOT Host 的五项实际语言用例也通过。具体范围见[测试](/SteamWrapper/zh-cn/development/testing/)。此前升级／回滚及 PE 资源记录保留为有日期的证据。不要覆盖已有标签或发布。未来需协调 Rust、Manager、Application、部署产品版本及锁文件，并提供完整双语说明。打标签前确认所选主线提交已通过 CI；准备说明或合并本身不证明发布。

安装器升级时，每个新可安装载荷／清单都递增三段基础版本，不能只改预发布后缀。`v0.2.1-preview.1` → `v0.2.1-preview.2` 会改变部署清单，但两者数字版本均为 `0.2.1`，会被当前同版本不同内容保护拒绝。手动运行序号产物是独立试用，不是升级序列。真实升级验收使用冻结旧包和真正编译、尚未使用的新基础版本。首次新签名载荷也必须使用尚未使用的基础版本，例如未签名 `0.2.4` 之后使用 `0.2.5`，不能让重新签名／时间戳后的不同 Runner 字节复用此前未签名版本。不可变产物的重试保持原样。

标签流水线现已使用明确的第 2 版未签名可安装产物，同时保留完整的第 1 版便携验证器。[执行队列](/SteamWrapper/zh-cn/project/roadmap/#执行队列2026-10-03)继续保留稳定交付所需的原生、干净客户端／恢复和旧版本保留验收。Foundation 申请被拒后，Windows Authenticode 改为可选；项目签名应用更新使用独立配置的密钥。可选应用更新及 Steam 应用／恢复不阻碍首个 P0–P2 稳定版。

下方已完成的 `0.2.5` 发布操作说明源码／说明审阅及 CI 之后的版本标签交付流程。不要重复现有标签，未来发行必须使用新的协调版本：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git tag -a v0.2.5-preview.1 -m "WinUI Windows preview 0.2.5-preview.1"
git push origin v0.2.5-preview.1
```

这些命令描述明确的发布操作；写在文档中不会创建标签，也不证明已经发布。执行前核对所选提交。工作流检出准确标签并重跑门禁，不沿用之前的分支构建。它先创建草稿，上传并验证全部附件，再公开预发布，不将其标为最新稳定版。

七个附件为 `SteamWrapper-<tag>-win-x64-setup.exe`、`SteamWrapper-<tag>-win-x64.zip`、`<tag>.en.md`、`<tag>.zh-CN.md`、`portable-release.json`、`release.json` 和 `SHA256SUMS`。外层 `release.json` 使用第 2 版结构，明确 `signed=false`、`installer=true`、`portable=true`，绑定两种产物的长度／摘要及部署清单。`portable-release.json` 保留第 1 版便携元数据和未放宽的旧验证门禁；`SHA256SUMS` 覆盖其余六个附件。ZIP 包含 `LICENSE` 及 `ReleaseNotes/` 中的双语说明。打包必须保留随附第三方的适用 notices／许可证和上游签名；第三方组件必须保留实际适用许可证，不能把全部依赖笼统描述为 MIT。

按需预览使用 **Run workflow** 并选择 ref。没有发布模式输入：所有手动运行都只生成预览，即使选择了标签也不公开发布。发布上传失败时，解决原因后优先使用 **Re-run failed jobs**：发布 job 会复用同一个不可变的 `SteamWrapper-WinUI-release-assets` 构建产物。**Re-run all jobs** 会重新构建和打包；如果同版本的字节发生变化，发布必须拒绝覆盖。不同内容应使用新版本，不移动已发布标签，也不覆盖已发布附件。

<a id="发布渠道"></a>

## 发布渠道

GitHub Releases 是版本标签二进制发布渠道。CNB 镜像使用 `CNB_GIT_TOKEN` 同步源码／标签，并优先使用 `CNB_RELEASE_TOKEN` 操作版本发布；未配置独立发布令牌时，复用 `CNB_GIT_TOKEN`，但该令牌还必须具有 `Nesoriel/SteamWrapper` 的 `repo-release` 读写权限。Git 同步成功不代表具有发布权限。发布器对照原始 SHA-256 验证上传后的下载副本；缺少可用凭据时跳过可选二进制步骤。

要为当前已发布预览补充镜像而不重新构建，运行 `gh workflow run cnb-release-mirror.yml --ref main -f tag=v0.2.5-preview.1`。维护工作流核对 GitHub 公开的七个附件、已合入主线的精确源码标签及当前签名授权版本，再发布并核验同一组 CNB 附件。它与发布和续期共用锁，最后把已核验镜像写入更新索引；不能切换到其他历史版本，也不能覆盖版本附件。权限失败时，为现有令牌补充 `repo-release` 读写权限，或配置 `CNB_RELEASE_TOKEN`；不要把令牌写入仓库文件或聊天。

`v0.2.3-preview.1` 的七个 GitHub 下载附件均已核验。CNB 发布凭据未配置，二进制镜像实际跳过，因此不公告 CNB 二进制下载。

2026-10-05，[维护运行 37285639449](https://github.com/YangYuS8/SteamWrapper/actions/runs/37285639449) 已发布 [`v0.2.5-preview.1` CNB 镜像](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.5-preview.1)及公开签名预览索引。CNB 全部七个附件均通过匿名长度／SHA-256 核验，与未改动的 GitHub 附件一致。实际 `0.2.5` 更新服务明确选择 CNB，完成项目签名校验并下载精确的 49,901,116 字节 Setup；同版本检查返回无更新。旧安装标签仅用于版本比较，没有执行 Setup。两站提供相同的签名索引字节，无需重新构建软件或替换不可变附件，当前已配置限定范围的 `CNB_RELEASE_TOKEN`。

随后，[续期运行 37286426643](https://github.com/YangYuS8/SteamWrapper/actions/runs/37286426643) 也通过两站公开索引的签名及字节一致性核验。它推进序列号和有效期，同时保留版本身份、安装包哈希／长度、镜像 URL 及 GitHub 全部七个不可变附件的 ID／哈希／长度。本次验收仅下载元数据，没有执行 Setup。

源码镜像或只有说明的 release 不等于二进制交付。宣传渠道前须检查该标签工作流实际的 GitHub/CNB 上传与下载结果，如实记录失败或跳过的镜像。旧 CNB 独立说明发布器已移除，避免与标签二进制工作流竞争。上传通过仍不完成干净系统、签名、更新器或卸载器验收。

<a id="当前-dioxus-封面策略"></a>

## 项目签名应用更新

Manager 更新流程使用项目元数据认证，不要求 Authenticode 证书。玩家点击**检查更新**，下载提示的新版本后确认安装；自动检查默认关闭。便携版提供下载指引，不自动覆盖任意解压目录。日常从 Steam 启动游戏不涉及更新。

版本标签工作流先发布不可变的 Setup／ZIP 附件，再由 `Publish-UpdateMetadata.ps1` 签署 `SteamWrapper-update.json` 中独立的第 2 版载荷。固定的 `update-preview`／`update-stable` Release 只保存这个可变索引，其标签不匹配软件构建触发条件。`update-metadata.yml` 每周将已有预览／稳定索引续期 28 天，不重建二进制，跳过尚未发布的通道。缺失更新源应提示服务不可用，不能显示为“已是最新版本”。

维护者使用已登录的 `gh` 执行一次 `pwsh -NoProfile -File scripts/releases/Initialize-UpdateSigning.ps1`。脚本生成 ECDSA P-256 密钥，将私钥直接写入 GitHub 的 `STEAMWRAPPER_UPDATE_PRIVATE_KEY` secret，只把公钥写入 `packaging/windows/update-trust.json`，不替换已有密钥。发布客户端前先提交公钥配置。PR/main CI 使用测试密钥，正式签名密钥仅用于发布／续期 job。玩家不需要生成密钥或安装证书。密钥丢失／轮换及下载验证详见[交付设计](/SteamWrapper/zh-cn/project/design/windows-delivery/)。

发布凭据生效、对应二进制及公开签名索引完成核验之前，CNB 不能作为可用更新源；签名元数据为两种来源绑定相同 SHA-256／长度。CLI 登录本身不会配置长期 CI 凭据，公开客户端不含访问令牌。没有更新界面的旧版本需要先手动安装一次新版客户端。Windows 仍可能对未签名程序显示自己的信任提示或实施限制。

## 封面与网络边界

当前 WinUI 优先读取 Steam 本地 `appcache/librarycache/` 和各用户 `config/grid/` 图片，再使用有效的 SteamWrapper 封面缓存。缺失或不可读时保留占位图；网络请求需要下面的明确选项。

官方 Steam CDN 封面回退需明确选择开启，本地优先、默认关闭。仅为本地已发现 AppID 获取缺失封面，采用 HTTPS 主机／重定向白名单与有界传输／解码图片尺寸。下载的图片仅存放在 SteamWrapper 的 `cache/covers/`，提供配额、过期、淘汰与清理入口。关闭后取消下载并阻止新请求，有效缓存仍可离线使用。清理保留自定义图片、Steam／游戏文件、配置和 Runner，不包含账号查询、游戏库上传或第三方元数据服务。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)、[实现限制](/SteamWrapper/zh-cn/development/architecture/#封面与安全边界)及剩余的[原生／玩家验收](/SteamWrapper/zh-cn/project/roadmap/)。
