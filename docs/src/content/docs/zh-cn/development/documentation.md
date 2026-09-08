---
title: "维护文档"
description: "开发、翻译、检查和部署 SteamWrapper 双语文档站。"
---

`docs/` 是仓库 pnpm 工作区中的独立包，使用 **Astro 7.3.1 和 Starlight 0.42.0**，构建静态文档站。Node 和 pnpm 属于开发／构建工具，不增加 Manager 或 Runner 的运行时要求。精确依赖记录在 [docs/package.json](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/package.json) 和根目录锁文件中。

## 本地准备与预览

在仓库根目录执行下面的命令。mise 会读取项目配置中固定的 Node 和 pnpm 版本：

```sh
mise install node pnpm
mise exec -c "pnpm install --frozen-lockfile"
mise run docs:dev
```

打开 Astro 输出的本地地址；英语入口为 `/SteamWrapper/`，简体中文入口为 `/SteamWrapper/zh-cn/`。开发服务器会重新加载内容改动。依赖保存在共用锁文件中；有意更新文档工具链时，应同时更新版本固定值和锁文件。

提交文档改动前执行：

```sh
mise run docs:check
mise run docs:build
mise run docs:preview
```

| 命令 | 用途 |
| --- | --- |
| `docs:dev` | 使用本地开发服务器编辑内容。 |
| `docs:check` | 检查英中文档配对、必需 frontmatter 和 Astro 类型；缺失中文对应页会被拒绝。 |
| `docs:build` | 在 `docs/dist/` 生成静态输出，再检查生成 HTML 的站内链接、锚点和本地资源。 |
| `docs:preview` | 提供最近一次生产构建的预览；需要在预览中看到后续改动时，应重新构建。 |

在生产预览中复核两个语言版本，包括导航、长表格、代码块和窄屏显示。内容检查可以发现缺失的对应页，但不能证明译文保留了全部细节。

## 页面与完整翻译

英文页面直接放在 `docs/src/content/docs/` 下，简体中文在 `zh-cn/` 下使用相同路由和文件名：

```text
docs/src/content/docs/development/documentation.md
docs/src/content/docs/zh-cn/development/documentation.md
```

每篇页面都需要 YAML frontmatter，其中 `title` 和 `description` 不能为空：

```yaml
---
title: "页面标题"
description: "简短说明本页用途。"
---
```

正文以介绍段落或二级标题开始。Starlight 会生成页面标题、语言选择器和编辑链接，因此正文不再重复一级标题、手工语言导航或编辑链接。将新页面加入导航时，应同时更新 [astro.config.mjs](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/astro.config.mjs) 中对应的侧栏条目和中文标签。

修改英文页面时同步维护完整中文。命令、字段名、原样路径、测量值和证据边界保持一致。应完整翻译解释，不能缩成摘要。两个版本必须能一起审阅。

## 链接、锚点与资源

站点界面的覆盖翻译位于 `docs/src/content/i18n/en.json` 和 `zh-CN.json`，用于补齐框架的搜索提示及章节链接无障碍标签。两份文件的键和插值占位符须对应，`docs:check` 会检查它们。

站内链接使用包含项目 base 的绝对路径：

```md
[Testing](/SteamWrapper/development/testing/)
[测试](/SteamWrapper/zh-cn/development/testing/)
```

中文页面通常链接到中文目标。跳转同一页面时使用 `#section-anchor`。修改标题时保留显式锚点，尤其是带日期的记录。指向仓库源码、社区文件或脚本的链接使用 `https://github.com/YangYuS8/SteamWrapper/blob/v2/` 加仓库相对路径，并保留需要的片段标识。页面编辑目标单独由 Starlight 管理。

保持 [legacy-routes.json](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/legacy-routes.json) 与旧 Markdown 链接的目标一致。该文件把旧文档文件名映射到不带 `/SteamWrapper/` base 的站点路由，同时应保留旧链接使用的锚点。站点资源放在适用的站点资源位置，由 `docs:build` 验证生成的 URL。生成的 `docs/dist/` 不是需要提交的源内容。

## 搜索

Starlight 在生产构建时通过 Pagefind 生成本地搜索索引。搜索可用于 `docs:build` 后的 `docs:preview`，也可用于部署后的静态站点；`docs:dev` 不提供可工作的索引。内容修改后，应重新构建再检查搜索。不需要外部搜索账号、API Key 或托管搜索服务。

## 当前指南与历史证据

用户指南描述当前支持的流程。技术决策和验收记录保留原始日期、命令、失败、测量值及限制。增加后续证据时分别标明范围，不用更宽泛的成功声明覆盖早先观察。包内容检查、原生界面复核和真实 Steam 验收是不同结果。

重新组织记录时，保留完整历史内容和有用锚点。忽略目录 `target/` 下的记录可以作为本机证据引用，但不随仓库检出提供，也不作为站点资源上传。[验收记录](/SteamWrapper/zh-cn/project/validation/steam/)展示了按日期和逐游戏结论划分证据的方式。

## GitHub Pages 部署

正式地址为 `https://yangyus8.top/SteamWrapper/`：项目 Pages 沿用账号现有的自定义域名。[site.config.mjs](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/site.config.mjs) 统一提供 Astro、跳转页生成和产物校验所用的站点域名与基础路径。修改地址时须同步仓库文档链接；本项目已启用强制 HTTPS。

文档工作流为 [`.github/workflows/docs-pages.yml`](https://github.com/YangYuS8/SteamWrapper/blob/v2/.github/workflows/docs-pages.yml)。推送到 `v2` 且命中文档相关路径过滤时，会检查、构建静态站点并部署。拉取请求只检查和构建，不部署。修改构建输入时，请查看工作流中准确的触发路径和部署条件。

仓库维护者需要将 **Settings → Pages → Source** 设为 **GitHub Actions**，并在 `github-pages` 环境的部署规则中允许 `v2`。默认分支保持 `main`，部署文档不要求修改它。仓库设置和成功部署都需要单独确认，本地构建通过不能替代。参见 [GitHub 自定义 Pages 工作流说明](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

只有工作流已经位于默认分支时，GitHub 才提供手动 `workflow_dispatch` 执行。`docs-pages.yml` 只在 `v2` 中时，应通过符合条件的推送，或重新运行已有工作流记录触发；不要依赖 Run workflow 按钮。参见 [GitHub 手动运行工作流的要求](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

部署后检查工作流报告的 Pages 地址、两个语言入口、导航、资源和搜索。应报告实际部署结果；新增工作流或写下这些步骤，不代表网站已经上线。
