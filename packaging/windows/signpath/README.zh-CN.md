# SignPath 申请准备文件

这些文件是**供服务方审核的草案**，尚未连接真实签名服务。仓库中的生产配置刻意保留未批准和未填写的状态。这里的脚本不会提交或批准签名请求、持有私钥、安装软件或读取玩家数据。

`payload-v1.xml` 仅允许签名 `inventory-policy.v1.json` 中的 7 个精确自有 PE 路径。上传 publish 目录时，这些路径须位于 GitHub artifact ZIP 根目录；第三方文件保留原字节和签名。`uninstaller-v1.xml` 要求 Inno 生成的精确文件名和协调版本；`setup-v1.xml` 仅签最终 Setup 外层，不会签 Inno 内部文件。所有模板都要求显式参数及产品元数据约束。Foundation 必须认可生成卸载器的来源以及 payload、manifest、卸载器、Setup 的完整链。签名改变 payload 字节后须使用新的协调数字版本。

[官方语法](https://docs.signpath.io/artifact-configuration/syntax)和[元数据约束](https://docs.signpath.io/artifact-configuration/reference#file-metadata-restrictions)说明了这些属性。`schema-v1.pin.json` 记录 2026-10-03 下载的官方 XSD；语法验证不代表申请或策略批准。可将相同 XSD 下载至忽略的 `target` 目录，执行可选语法检查。更新 schema hash 前需要审核。

```powershell
pwsh -NoProfile -File scripts/windows/Test-SignPathConfiguration.ps1
# 可选：传入先前下载且 hash 匹配的官方 XSD。
pwsh -NoProfile -File scripts/windows/Test-SignPathConfiguration.ps1 -SchemaPath target/path/to/artifact-configuration-v1.xsd
# 先还原并构建真实协调版本的 publish，确保 cargo 位于 PATH。
pwsh -NoProfile -File packaging/windows/signpath/New-SignPathInventory.ps1
```

清单生成器在忽略的 `target/winui/signpath-dossier/<id>` 创建新目录，不覆盖旧材料。它记录实际 publish 文件 hash、自有与上游文件边界、源码与产物版本一致性、NuGet lock 及缓存中的原始许可证，以及 Windows Runner 非 dev Cargo 依赖闭包和声明许可证。微软 NuGet 分发条款可能不同于源码仓库许可证；不确定的许可证及 System Libraries 例外保持待服务方确认。脚本不会自动还原依赖、下载 schema、签名、安装或清理。

`SignPathConfiguration.ps1` 检查声明的生产前置资料及请求参数，但无法证明服务方真实批准、角色、MFA、token 权限、构建来源或证书信任。只传入表示 token 是否可用的布尔值，不传或打印 token。真实签名还需受保护的服务配置、GitHub-hosted 构建来源、真人审批，以及 `WindowsSigning.ps1` 提供的签后 Windows trust、RFC3161、证书 DER pin 校验。

真人职责及当前申请状态见[签名政策](https://yangyus8.top/SteamWrapper/zh-cn/project/design/code-signing/)。
