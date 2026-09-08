# 参与 SteamWrapper 开发

[English](CONTRIBUTING.md) | 简体中文

SteamWrapper v2 由 Windows 优先的配置 Manager 与独立 Rust Runner 组成。修改产品边界前，请阅读 [README](README.zh-CN.md)、[架构](https://yangyus8.top/SteamWrapper/zh-cn/development/architecture/)和[路线](https://yangyus8.top/SteamWrapper/zh-cn/project/roadmap/)。WinUI Manager 仍是预览；在 Windows 交付门槛通过前，Dioxus 与现有工作流保留为迁移基线。

## 问题与提案

请先搜索[现有 issue](https://github.com/YangYuS8/SteamWrapper/issues)。使用缺陷、功能或求助模板，注明版本或提交、分支、平台及 Manager 实现。模板文件在 `v2` 中维护，GitHub 实际模板选择器使用默认分支。项目主语言为英语，也欢迎使用简体中文提交问题。

报告缺陷时说明预期、实际行为及最小复现步骤，只附相关且已脱敏的日志片段。优先提供模拟 Steam 库和小型进程 fixture，不上传游戏、Steam 账号数据或存档。疑似安全漏洞请依照 [SECURITY.zh-CN.md](SECURITY.zh-CN.md)处理，并遵守[行为准则](CODE_OF_CONDUCT.zh-CN.md)。

涉及配置格式、Runner CLI 行为、支持平台、打包或外部服务的较大改动，请先讨论。提案不代表项目承诺交付或接受。

## 分支与开发环境

v2 的拉取请求应以 `v2` 为目标分支。GitHub 默认分支目前是 `main`，创建 PR 时请明确检查 base。不要将 `main` 上的旧版实现混入 v2 改动。

使用仓库的 `mise.toml` 和 `mise.lock` 管理开发工具，保持 .NET 版本与 `global.json` 一致。官方 MSVC/SDK 前置条件及 mise 命令见 [Windows 开发环境](https://yangyus8.top/SteamWrapper/zh-cn/development/windows/)。WinUI 改动先执行：

```powershell
mise run winui:test
mise run winui:contracts
```

根据[测试文档](https://yangyus8.top/SteamWrapper/zh-cn/development/testing/)选择其他检查。纯文档改动需要翻译及链接复核，不必人为执行全量构建。现有 CI 和发布门禁仍适用，不应削弱检查来掩盖失败。请准确区分通过、失败、受阻和未运行。

## 实现边界

文档站改动须运行 `mise run docs:check` 和 `mise run docs:build`，在生产预览中检查两种语言的搜索与导航。完整流程见[文档维护指南](https://yangyus8.top/SteamWrapper/zh-cn/development/documentation/)；纯文字编辑无需构建桌面应用。

- Manager 负责配置；Steam 启动独立无界面 Runner，正常游戏启动不得显示 Manager。
- 保持 TOML 兼容性、稳定数据路径、Runner CLI 含义及 `"<stable-runner-path>" --appid "<appid>" -- %command%`。
- 保留未编辑和未知配置字段，不要把保留语法的编辑替换为全模型序列化。
- 进程生命周期行为及真实进程测试应放在 Runner／平台代码中。
- 默认界面和文档使用英语，维护完整简体中文对应版本。含义变化时同时更新语言资源和文档对；标识符、协议字段、命令和原始证据保持准确。
- 保持统一 SVG／PNG／ICO 资源与 Dioxus 副本一致。修改源 SVG 后执行 `mise run brand:generate` 和 `mise run brand:check`。pnpm／`@resvg/resvg-js` 仅是开发期资源工具，不是应用运行时依赖。使用原创图形并尊重第三方商标。

## 保护玩家数据

自动化测试必须使用一次性 Steam 和用户数据 fixture。未得到明确授权，不得用他人的真实游戏库测试。日常测试不得修补、替换、通过 Steam 校验、卸载或清理游戏文件；Steam 校验可能覆盖第三方汉化。

经授权进行真实验收时，保存所选游戏原有 Launch Options，测试后恢复，并按[真实验收流程](https://yangyus8.top/SteamWrapper/zh-cn/project/validation/steam/)比较文件清单和哈希。遇到未解决的存档或云冲突必须停止。不要上传凭据、账号配置、存档、游戏二进制或未脱敏的个人路径。生成的用户数据和本机证据不得提交。

## 拉取请求

保持 PR 聚焦，说明用户遇到的问题、修改后的行为、相关测试与剩余限制。可见界面改动应附已移除个人信息的截图。同步更新受影响文档的两种语言，并区分现有实现、方案和已验证的平台证据。

请使用[拉取请求模板](.github/PULL_REQUEST_TEMPLATE/zh-CN.md)。不能通过无关测试推定 Steam 时长、成就、Windows 安装或其他平台兼容性。行为修复应按需加入聚焦回归，避免只重复实现字符串的测试。

## 许可证

`v2` 分支沿用现有 [Apache-2.0 许可证](LICENSE)，对该分支的贡献按此许可提交。本指南不改变旧版 `main` 分支的许可证，不增加贡献者许可协议，也不要求新的签署流程。
