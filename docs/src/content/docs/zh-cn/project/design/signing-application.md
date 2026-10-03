---
title: "SignPath 申请材料"
description: "Foundation 申请的软件事实与真实人员／服务方前置条件。"
---

本材料准备[官方 Foundation 申请表](https://signpath.org/apply.html)中的软件部分，**不代表申请已经提交或获批**。[代码签名政策（Code signing policy）](/SteamWrapper/zh-cn/project/design/code-signing/)记录当前信任与批准状态。

## 软件字段

| 申请字段 | 已准备内容 |
| --- | --- |
| 项目名称 | SteamWrapper |
| 源码仓库 | [YangYuS8/SteamWrapper](https://github.com/YangYuS8/SteamWrapper) |
| 主页 | [SteamWrapper 文档](https://yangyus8.top/SteamWrapper/) |
| 简介 | Configure a game once, then launch it normally from Steam. |
| 构建系统 | GitHub Actions，使用 GitHub 托管执行器和锁定的 .NET／Rust 依赖 |
| 下载页 | [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases)；当前产品形态的 [v0.2.3-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.3-preview.1) 已于 2026-10-03 公开发布并下载核验，后续 WinUI 预览使用独立不可变标签 |
| 许可证 | 当前源码为 Apache-2.0；重新分发的依赖／运行时条款独立清点 |
| 隐私政策 | [隐私与用户信任](/SteamWrapper/zh-cn/project/design/code-signing/#隐私与用户信任) |
| 声誉 | 公开维护的小型项目，具有源码、问题跟踪、双语文档及有日期的本地验证；不宣称独立审计、广泛使用或干净客户端批准 |

用途描述的中文对应内容：

> SteamWrapper 是 Windows 游戏启动配置工具。原生 WinUI 3／C# Manager 让玩家选择已有 Steam AppID 和单独的游戏程序或启动器。Steam 通过生成的启动选项调用独立、无界面的 Rust Runner，日常启动不经过 Manager。工具不注入 DLL、不修补 Steam 或游戏二进制、不绕过 DRM、不安装隐藏服务，也不上传玩家文件。配置与本地 Steam 封面可离线使用；可选官方 Steam CDN 封面请求默认关闭，需明确启用偏好。每用户安装器只管理 Manager，保留用户数据和稳定 Runner，并提供卸载。当前交付为技术预览，文档记录仍未完成的干净客户端与原生交互门槛。

联系人姓名和邮箱不进入提交的软件材料，除非维护者明确选择公开。申请表需要真实联系人姓、名、邮箱和发现渠道，包含 reCAPTCHA，并要求同意处理个人资料。维护者需要提供这些事实并完成个人步骤，不能编造公司、外部背书或 Wikipedia 页面。

首次当前形态的公开预览来自提交 `c457f16b8ea8167c9ef4b8bd67b38a5030455bce`，对应成功的[托管发行运行 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907)。七个公开附件均独立下载，并核对第 2 版契约和 GitHub 摘要／长度。下载包的七个自有 PE 产品版本均为 `0.2.3`，Setup 正确标识为未签名，五个真实 NativeAOT 恢复语言进程在维护者的中文 Windows 上通过。这是公开交付及限定本机结果，不等于干净客户端或签名批准。CNB 二进制镜像因未配置而跳过，GitHub 为已核验下载渠道。

## 技术附件

已审阅模板与清单工具位于 `packaging/windows/signpath/`。`payload-v1.xml` 精确列出七个自有 PE，限制 `ProductName=SteamWrapper`、协调的数字版本及 SHA-256 签名；`uninstaller-v1.xml` 和 `setup-v1.xml` 为独立草案。XML 有效不代表 Foundation 接受多阶段构建政策。

清单区分自有二进制、上游二进制、运行时包、构建工具和 Windows Runner 依赖闭包。发行包保留准确的第三方许可证／声明原文，尤其不能将微软包条款误标为 MIT，或默认其已通过 Foundation 的 System Libraries 例外。提供清单并请服务方确认分类，上游 DLL 不使用项目证书重新签名。

实际 GitHub 托管产物身份才是构建来源证据。当前官方提交 action 固定于提交 `f6d04783b4569d051e0c80105fe66e82819d0092`（v3）；接入仍需真实组织、项目、获批政策及受限 CI 提交者。[官方 action](https://github.com/SignPath/github-action-submit-signing-request/tree/f6d04783b4569d051e0c80105fe66e82819d0092)、[GitHub 来源验证](https://docs.signpath.io/trusted-build-systems/github)。

请 Foundation 审核以下顺序：签自有载荷；验签并重建 Runner 清单；生成并签同一构建的 Inno 卸载器；嵌入 Setup；签最终 Setup 并验签；最后记录摘要。Inno 支持缓存外部签出的卸载器，服务方仍须接受其来源和多阶段政策。[Inno SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm)、[SignedUninstallerDir](https://jrsoftware.org/ishelp/topic_setup_signeduninstallerdir.htm)。

## 技术先例与边界

Foundation 的 [Nagi 官方项目页](https://signpath.org/projects/nagi/)列出已接纳的 C#／WinUI 3 应用。其已发行的 [2.4.0 版本](https://github.com/Anthonyy232/Nagi/releases/tag/2.4.0)同时启用 [.NET 自包含发布](https://github.com/Anthonyy232/Nagi/blob/2.4.0/src/Nagi.WinUI/Properties/PublishProfiles/win-x64.pubxml)和 [Windows App SDK 自包含部署](https://github.com/Anthonyy232/Nagi/blob/2.4.0/src/Nagi.WinUI/Nagi.WinUI.csproj)，并提供生产 [SignPath 发行工作流](https://github.com/Anthonyy232/Nagi/blob/2.4.0/.github/workflows/release.yml)及 [MSIX bundle 签名配置](https://github.com/Anthonyy232/Nagi/blob/2.4.0/.signpath/artifact-configuration.xml)。

barcodrod.io 是更接近本项目的未打包先例：[v2.1 构建脚本](https://github.com/MarkHopper24/barcodrod.io/blob/v2.1/installer/build-msi.ps1)将 WinUI 3／.NET 自包含应用装入离线 MSI。[签名配置](https://github.com/MarkHopper24/barcodrod.io/blob/v2.1/.signpath/artifact-config-msi.xml)覆盖自有 EXE／DLL 与 MSI，成功发行的 [v2.1 版本](https://github.com/MarkHopper24/barcodrod.io/releases/tag/v2.1)提供 x64 和 ARM64 安装器。

这些先例说明所选技术路线已有实际应用，不代表 SteamWrapper 获批，也不能证明本项目微软依赖的具体版本和许可分类、System Libraries 例外或 Inno 多阶段签名链已被接受。应将这些细节交由服务方独立审核，不能照搬其他项目的身份、政策或证书指纹。

## 必须完成的外部接入

所有人类维护者需要启用 GitHub 和 SignPath MFA，明确实际作者、审核者及签名批准者，每次发行需人工批准。代理和 CI 提交者不能代替此批准。接纳后记录服务方接受的配置、真实公开证书 DER SHA-256 指纹及受保护的提交身份。校验和或未签名预览不能代替已签名信任。[Foundation 条件](https://signpath.org/terms.html)。

公开当前形态预览、联系人／MFA 确认、验证码／个人资料同意、Foundation 接纳及获批产物链都是独立待核验事实，不能因为本地夹具验证通过就改变待完成状态。缺少服务配置时停止要求签名的发行，不退回未签名发布。
