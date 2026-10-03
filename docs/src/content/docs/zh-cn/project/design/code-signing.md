---
title: "代码签名政策"
description: "已实现的签名准备与已提交、等待审核的 SignPath Foundation 申请，包含人工批准和发行边界。"
---

## 当前状态

**SignPath Foundation 申请：已于 2026-10-04 提交，等待服务方审核。尚未获得服务订阅、项目证书或生产签名批准。**官方表单已确认提交成功。维护者选择免费 OSS 路线，并接受 Foundation 作为未来证书发布者。当前未签名预览不能宣称签名服务已经可用。

仓库已提供 Windows 签名验证、签后 Runner 清单生成、MSVC Runner PE 资源、精确的产物配置草案、依赖／许可清单工具及生产前置校验器。这些是准备工具，尚未接入签名服务，不导出私钥、不向 SignPath 提交文件，也未建立认证应用更新渠道。剩余外部与交付门槛见[申请材料](/SteamWrapper/zh-cn/project/design/signing-application/)与[交付方案](/SteamWrapper/zh-cn/project/design/windows-delivery/)。

## 人类责任

拟议的人类维护者账号是 [YangYuS8](https://github.com/YangYuS8)，为 [GitHub 源码仓库](https://github.com/YangYuS8/SteamWrapper)所有者。接入时确认并记录真实人员及其 SignPath 角色：

| 角色 | 责任 | 配置状态 |
| --- | --- | --- |
| 作者 | 维护经过审核的源码与构建定义 | 人类仓库维护者；服务方角色映射待完成 |
| 审核者 | 审核其他贡献者的变更，尤其是工作流及打包 | 人类维护者；可另行指定其他审核者 |
| 签名批准者 | 批准前检查提交、测试、产物及签名请求 | 人类维护者，待 Foundation 确认 |
| CI 提交者 | 按获批政策只提交已验证的托管构建 | 最小权限专用服务身份尚未配置 |

AI 编码代理可以准备变更与证据，不是 Foundation 批准的人类审核者或签名批准者。CI 令牌可以提交请求，但不得批准请求。本文不宣称 MFA 已就绪或实际角色分配已经完成。

## 源码与产物政策

未来生产签名只接受经过审核、且精确提交可从 `main` 到达的版本标签。普通 PR/main CI 和未签名手动预览不获取签名凭据。绑定源码提交、工作流运行与上传产物身份；仓库自行提供的 JSON 不构成独立来源证据。

只签从经过审核的源码构建的项目自有 EXE／DLL。重新分发的运行时文件保留上游签名。每个自有 PE 使用 `ProductName=SteamWrapper` 及一个协调一致的产品版本，包括本地化程序集、Runner 和部署组件。拒绝同版本不同 Runner 字节，不放宽稳定 Runner 的清单识别。

载荷／卸载器与最终 Setup 的签名阶段必须获得服务方接受。Inno 生成卸载器的构建来源属于该审核，不导入构建之外人工签出的二进制文件。Runner 签名**之后**重新生成 `runner-manifest.json`，打包时保持该字节不变。只有嵌入已验证载荷后才签最终 Setup。ZIP 内包含已签名 PE 文件；ZIP 本身的真实性由独立的认证元数据及最终摘要确认。

Foundation 接纳取决于外部审核，发行签名要求人工批准。[Foundation 条件](https://signpath.org/terms.html)、[GitHub 来源验证](https://docs.signpath.io/trusted-build-systems/github)。

实际获批后，再将等待审核状态改为已验证细节，并使用此致谢：“Free code signing provided by SignPath.io, certificate by SignPath Foundation.” 目前它描述申请中的未来服务，不代表已经获得证书。

## 当前可用验证

`scripts/windows/WindowsSigning.ps1` 提供：

| 函数 | 行为 |
| --- | --- |
| `Get-WindowsSigningEvidence` | 不执行文件，检查内嵌 Windows 信任、SHA-256 摘要、签名者、RFC3161 时间戳及 PE 产品元数据 |
| `Assert-WindowsSigning` | 要求 Windows 信任验证通过、可信 RFC3161 时间戳、SHA-256、精确 SteamWrapper 产品版本、Foundation 签名者名称及明确证书 DER SHA-256 白名单 |
| `Update-RunnerSigningManifest` | 验证最终暂存 Runner，保持其字节读锁，原子重建相邻清单；失败时保留旧清单 |

默认使用 Windows 缓存信任及 `WTD_CACHE_ONLY_URL_RETRIEVAL`，不获取缺失证书链或吊销证据。证据缺失时安全拒绝。`-OnlineRevocation` 是明确的维护选项，独立于应用日常离线使用，采用 Windows 证书获取机制。原生检查不执行安装器、Runner 或游戏。[Windows 信任标志](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/ns-wintrust-wintrust_data)。

白名单故意不填入猜测的 Foundation 证书。通过受保护的服务接入配置，记录实际获批公开证书的 DER SHA-256；它不是密码或私钥。轮换需要审核新指纹、协调新版本及更新信任政策。不能仅因发布者文字相同，就接受无关的 Foundation 签名应用。

构建当前 Runner 后运行重点本地检查：

```powershell
cargo build --locked --release -p steamwrapper-runner
pwsh -NoProfile -File scripts/windows/Test-RunnerSigningMetadata.ps1
pwsh -NoProfile -File scripts/windows/Test-WindowsSigning.ps1
```

这些检查真实 PE 资源，拒绝实际未签名 Runner 及被修改的内嵌签名 PE 副本，并测试身份／时间戳／哈希策略及原子清单失败。测试夹具通过，不代表获得 Foundation 证书、真实生产签名、干净客户端安装或自动更新服务。

## 申请材料与剩余门槛

[申请材料](/SteamWrapper/zh-cn/project/design/signing-application/)记录本次已提交申请的软件事实。服务方审核期间持续维护以下证据与接入要求；本文不公开个人申请资料：

1. 公开当前形式的技术安装器预览，包含准确源码标签、已验证托管构建、本机安装／恢复证据及仍未完成的干净客户端限制。预览不豁免稳定交付门槛。
2. 许可证／依赖清单，以及自有文件与重新分发运行时的精确划分。
3. 已确认的人类作者、审核者、批准者及 MFA；两种文档语言的隐私和卸载行为。
4. 服务方产物配置，覆盖协调一致的 PE 元数据、生成卸载器、不可变载荷及最终 Setup。
5. 获批签名者指纹、受保护的提交身份、批准流程、超时／重试处理和审计证据。
6. 真实已签名产物测试，包含时间戳、证书到期／吊销、轮换、签后清单及干净 Windows 下载。

申请身份、批准、令牌配置及证书政策仍需服务方／维护者接入。要求签名的发行在缺少这些条件或验证失败时必须停止，不悄悄发布未签名替代物。

`packaging/windows/signpath/` 包含载荷、生成卸载器和 Setup 的独立 XML 草案，精确自有文件目标与元数据限制已按审阅的官方 schema 核验，但服务批准仍待完成。`Test-SignPathConfiguration.ps1` 拒绝未批准／缺失前置条件及扩大的签名范围，不读取令牌或发送请求。本地 `providerApproved` 声明不是接纳、角色、MFA 或证书信任的独立证据。运行时和依赖条款单独清点，微软重新分发组件的 System Libraries 例外分类仍需 Foundation 确认。

## 隐私与用户信任

默认操作使用本地游戏配置与 Steam 元数据，不上传它们。可选官方 Steam CDN 封面请求需要启用偏好，并发送本地已发现的 AppID。未来应用更新检查将需要同意，并联系文档说明的分发端点；该功能尚未实现。签名只提交发行构建产物和来源信息，绝不提交玩家配置、凭据、存档或游戏库内容。应用请求与操作系统证书检查分开看待。

外部服务请求会暴露请求 IP 地址等常规连接信息。相关服务政策见 [Valve 隐私政策](https://store.steampowered.com/privacy_agreement/)、[GitHub 隐私声明](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)及 [SignPath 隐私政策](https://signpath.io/privacy-policy)。SignPath 处理维护者申请和签名服务相关信息，不参与玩家日常游戏启动。

有效签名按信任策略证明来源与完整性，不保证 Defender、SmartScreen 或 Smart App Control 接受每个新发行。下载／启动验收保持防护开启。[微软 SmartScreen 指引](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)。
