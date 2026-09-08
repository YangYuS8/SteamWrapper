# 文档

[English](README.md) | 简体中文

SteamWrapper 的主文档语言为英语。本目录每一篇文档都有名为 `*.zh-CN.md` 的完整简体中文对应版本，可通过页首语言链接切换。两个版本中的命令、配置键、路径和历史测量值保持相同含义。

先阅读[项目概览](../README.zh-CN.md)，再选择下面相关的指南。当前设计、已实现行为和带日期的验收记录分别说明：方案或早先通过的结果，不能证明后续构建或所有平台均已通过。

## 产品与开发

| 指南 | 用途 |
| --- | --- |
| [架构](architecture.zh-CN.md) | Manager、服务、独立 Runner、文件契约、稳定数据与界面语言设置。 |
| [Windows v2 设计](windows-v2-design.zh-CN.md) | Windows 优先需求、配置保真、交付门槛与暂缓范围。 |
| [技术栈](tech-stack.zh-CN.md) | 当前实现、工具链、保留的 Dioxus 基线与不选的方向。 |
| [Windows 开发](windows-development.zh-CN.md) | mise 管理的环境准备、构建/测试命令与共享数据路径检查。 |
| [测试](testing.zh-CN.md) | 选择相关的自动化、原生、包体和获授权的真实 Steam 检查。 |
| [分发](distribution.zh-CN.md) | 预览打包、稳定 Runner 安装、更新/卸载边界与发布门槛。 |
| [路线图](roadmap.zh-CN.md) | 实现优先级与替换基线前仍需完成的工作。 |
| [汉化游戏分离存放](translated-games.zh-CN.md) | 将 Steam 官方安装与独立汉化分开，了解启动、成就、存档和云同步的限制。 |

## 研究与带日期的证据

这些记录保留原始日期和测量值，后续结果另行标明；忽略目录 `target/` 下的本机证据不会随仓库检出提供。

| 记录 | 用途 |
| --- | --- |
| [WinUI 3 评估](winui3-assessment.zh-CN.md) | 迁移备选方案、依赖、部署与最初验证计划。 |
| [Windows Manager 实测比较](windows-manager-comparison.zh-CN.md) | 同输入配置测试、原生检查与有边界的资源测量。 |
| [WinUI 预览验收](winui-preview-validation.zh-CN.md) | 首个配置切片证据与后续覆盖。 |
| [真实 Steam 验证](real-steam-validation.zh-CN.md) | 获授权的逐游戏观察、历史失败、后续重测与剩余限制。 |
| [Astra 指令审计](astra-instruction-audit.zh-CN.md) | 带日期的指令研究与仓库指导修改记录。 |

## 社区与自动化

按需阅读[贡献指南](../CONTRIBUTING.zh-CN.md)、[行为准则](../CODE_OF_CONDUCT.zh-CN.md)、[安全问题报告](../SECURITY.zh-CN.md)或[支持](../SUPPORT.zh-CN.md)。[AGENTS.md](../AGENTS.md)记录仓库自动化指令，不是用户指南。

本实现在 `v2` 上开发。GitHub 默认分支仍为 `main`，因此 GitHub 展示的社区文件和模板可能与本分支不同。
