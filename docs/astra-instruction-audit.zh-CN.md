# Astra 指令审计记录

[English](astra-instruction-audit.md) | 简体中文

日期：2026-09-07。范围：当前 SteamWrapper `v2` 的可编辑指令与相关路线文档；不改产品实现、模型参数、插件安装状态或 CI。

## 材料与阅读范围

完整阅读 OpenAI [Using GPT-6 Astra](https://developers.openai.com/api/docs/guides/latest-model) 的 Markdown 正文，涵盖介绍、新能力、提示建议和迁移参数。与本项目直接相关的是自主完成、指令冲突、沟通、并行分工和验证范围；SteamWrapper 不是 OpenAI API 应用，不需要为此新增 API 或模型依赖。

完整阅读 Eric Provencher 的 [Rethinking skills and prompts for GPT-6 Astra](https://x.com/pvncher/status/2095991462416490862)：27 个文字 block 和两张文内对照图。X 网页直读返回 403，正文经 [公开 FxTwitter JSON 转呈](https://api.fxtwitter.com/status/2095991462416490862) 获取，以 [X 官方 syndication](https://cdn.syndication.twimg.com/tweet-result?id=2095991462416490862&lang=en&token=0) 交叉核验作者、标题、文章 ID、开头和 2026-09-04 发布时间；配图直接读取 X 图片资源。没有用中文扩写或转载摘要代替原文。

本次采用的原则：技能描述限定实际任务，详细资料按需读取；常驻指令保留稳定约束；测试范围与改动相称；明确获授权工作的完成边界。没有把通用提示词整段复制进项目。

## 实际指令来源

| 来源 | 本轮核验 | 处理 |
| --- | --- | --- |
| 仓库根 `AGENTS.md` | 本会话已提供其内容，磁盘原文一致；无项目级 override 或嵌套 AGENTS | 精简为产品契约、协作边界、分层和任务路由 |
| `skills/dioxus-manager/SKILL.md` | 存在于仓库 `skills/`，不在本会话自动发现的技能清单中；本轮已完整读取 | 精简为现有 Dioxus 工作流，在根 AGENTS 中明确按任务引用 |
| `C:\Users\admin\.codex\AGENTS.md` | 空文件；未发现全局 override | 保持为空，避免再次堆入已存在的通用规则 |
| `C:\Users\admin\.codex\config.toml` | 模型为 `gpt-6-astra`；未发现额外 instructions 文件或项目 fallback 配置 | 保留现有模型与 reasoning 配置；API 指南不直接决定桌面 app 的设置值 |
| 本轮使用的系统技能 | 已读 `openai-docs`、其模型迁移参考与 `skill-creator` | 使用当前官方工作流，不修改系统技能或插件缓存 |
| 会话/应用提供的指令、技能目录 | 它们影响本会话，但不是仓库可编辑文件；技能描述可见不等于全部正文已加载 | 不宣称已改写这些来源；不批量修改无关插件 |

本机未发现用户 `.agents/skills`、仓库 `.agents/skills` 或独立 rules 目录。官方说明区分 AGENTS 的启动读取与技能的按需加载；仓库现有 `skills/` 路径通过 AGENTS 显式路由，不冒称已注册到技能选择器，也不创建重复副本。[AGENTS 发现规则](https://learn.chatgpt.com/docs/agent-configuration/agents-md)、[技能发现与加载](https://learn.chatgpt.com/docs/build-skills)

## 具体修正

| 原问题 | 修正 |
| --- | --- |
| 每次修改前要求 workspace 测试，技能再次列出整条构建/E2E/bundle 链 | 根文件定义验证原则，`docs/testing.md` 提供按改动的范围；CI/release 完整门禁保留 |
| 技能要求固定顺序阅读多篇文档并重复根文件规则 | 保留 UI、E2E、打包的必要事实；相关任务才读取现有文档 |
| “任何 Manager-facing 服务/CI 工作”都可能触发 Dioxus 技能 | 限定 Dioxus UI、Native E2E、Dioxus bundle；排除 WinUI 调研与 Runner 生命周期 |
| `AGENTS.md` 禁在线封面，但源码、测试和文档已存在 Steam CDN fallback | 描述实际有限 AppID fallback，保留不上传用户数据、不扩展第三方服务和离线占位边界；不改网络行为 |
| “全 Rust / Dioxus 唯一方向 / Linux LTS 优先”与新的 Windows 目标冲突 | 区分当前实现和 WinUI 目标，暂停 Linux/SteamOS 扩展；保留旧代码与兼容契约 |
| 技能顶层有 `version`、`author`、`platforms` 等非校验器支持字段 | 归入 `metadata`，保留已有元数据，不宣称平台都经过验证 |
| 文档把 CI 声明或源码字符串断言写得像平台验收 | 说明证据限制，纠正 NSIS 检查所在工作流，并列出 WinUI 所需原生验证 |

## 验证与限制

原指令要求的 `cargo test --workspace` 已尝试，因缺少 MSVC `link.exe` 在依赖编译阶段失败，测试未执行。该环境阻塞没有通过修改测试或降低 CI 门禁来掩盖。

验证结果：`git diff --check` 通过；11 个 Markdown 改动文件中的 36 个本地链接/锚点通过；`quick_validate.py` 以 `python -X utf8` 运行通过。校验所需 PyYAML 仅安装到任务临时目录，未加入产品依赖。Windows 默认 GBK 读取 UTF-8 技能的错误通过本次命令的 UTF-8 模式解决，没有修改系统设置或校验器。

独立审阅用文档措辞修改与 Dioxus 行为修复两个场景推演路由/检查范围，未发现阻断问题；已采纳其建议，明确测试表中的 `ui_contract` 只证明源码声明。这些是文档和指令验证，不是 Astra 实际任务成功率或性能提升的量化证据。

文件修改已经保存；本会话已读取修订文本。后续新会话会按加载规则读取仓库 AGENTS；已注入的旧文本不会因磁盘编辑自动从上下文消失。全局空文件、应用配置、系统技能和插件缓存均未修改。

## 同日后续重设计

用户进一步授权根据最初需求重新设计。已追溯仓库初始 README、架构与路线，新增 `docs/windows-v2-design.md`，改为 WinUI/C# 配置服务与独立 Rust Runner，通过既有 TOML/CLI 配合；撤回初次评估中的 FFI 默认建议。AGENTS、Dioxus 技能和相关文档同步该边界，保留本次 Astra 指令精简原则，不新增通用提示词。

上节 11 文件/36 链接是初次审计结果。重设计后的 12 份 Markdown、62 个本地链接/锚点及技能元数据校验通过；独立原始需求核对与架构审阅未发现阻断问题，已采纳 CI 从早期增量建立和路线顺序措辞建议。仍未改运行时代码、CI 或系统工具链，也未把前次受阻测试写成通过。
