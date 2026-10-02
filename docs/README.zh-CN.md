# 文档源文件

[English](README.md) | 简体中文

阅读已发布的 [SteamWrapper 英文文档](https://yangyus8.top/SteamWrapper/)或[简体中文文档](https://yangyus8.top/SteamWrapper/zh-cn/)。

此目录是 Astro Starlight 工作区。唯一正文源位于 `src/content/docs/`，对应的 `zh-cn/` 子树存放完整翻译。`guides/` 面向玩家，`development/` 介绍实现与维护，`project/` 保留设计决策及带日期的证据。根 README 不重复维护完整指南。

按自己的方式安装 Node 24.18.0（已验证的参考版本）与根 `package.json` 声明的 pnpm 版本。mise 是可选项，其中的 Node/pnpm 版本可供本地准备参考；站点依赖以工作区清单和锁文件为准。

```sh
pnpm install --frozen-lockfile
pnpm docs:dev
pnpm docs:check
pnpm docs:build
pnpm docs:preview
```

请在仓库根目录运行这些命令。本地地址包含 `/SteamWrapper/`；搜索需在构建后的生产预览中使用。生成的 `.astro/` 与 `dist/` 目录已忽略。

完整的编辑、翻译、链接约定、验证和 GitHub Pages 发布流程见[文档维护指南](src/content/docs/zh-cn/development/documentation.md)。[legacy-routes.json](legacy-routes.json) 将旧文档名映射至新路由；构建生成静态跳转页，在 JavaScript 可用时保留查询参数和章节片段。这些跳转无法改变 GitHub 自身的 `blob/` 地址。
