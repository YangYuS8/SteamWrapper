# 维护第三方分发声明

`NOTICE.md` 与 `manifest.v1.json` 定义 `scripts/windows/Stage-WinUIThirdPartyNotices.ps1` 暂存的精确法律材料。上游原文位于相邻的 `third-party-licenses` 目录，保留原始语言及格式，包括微软 SDK 的 RTF。

这些原文、带哈希的声明入口及其清单禁用了 Git 文本规范化；更新它们时保持原文字节哈希。

清单包含 Windows Runner 的非 dev 依赖闭包（包括 build/proc-macro 依赖）、分发的 NuGet/runtime 组件，以及生成的 Inno 安装器；独立开发 SDK/编译工具任务不进入清单。.NET 第三方声明和微软包的 NOTICE 与许可证分别保留。这些文件记录分发材料，不代表 Foundation 批准或 System Libraries 例外被接受。

依赖版本变化时，阅读真实锁定包及其上游许可证/声明，仅复制法律文件到规范集合，更新组件引用、原始来源、长度、SHA-256 和玩家可读表格。不要收集整个缓存目录，也不要只根据源码仓库的许可证标记翻译或替换法律条款。

在 PowerShell 7 环境中确保 cargo 位于 PATH，运行聚焦测试：

```powershell
pwsh -NoProfile -File scripts/windows/Test-WinUIThirdPartyNotices.ps1
pwsh -NoProfile -File scripts/windows/Stage-WinUIThirdPartyNotices.ps1 -PublishDirectory target/winui/publish -VerifyOnly
```

暂存离线执行，仅允许仓库 `target/winui` 内的新候选产物。已有一致字节保持不变；不同字节、遗漏材料、非法路径、超限文件及依赖版本漂移会拒绝。脚本不读取玩家数据，也不复制任意凭据。最终便携 ZIP 与安装器均须保留 `THIRD_PARTY_NOTICES.md`、`LICENSES/index.json` 及所有索引中的法律文件。
