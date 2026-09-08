# SteamWrapper 图标

[English](README.md) | **简体中文**

SteamWrapper 原创图标以 Rust 风格的铜橙色齿轮、让人联想到 Steam 的浅色连杆和
深蓝色轮毂组成，表现 Runner 将 Steam 库条目连接到玩家所选游戏程序的功能。
它不表示 Rust 项目或 Valve 对本项目的背书。

`steamwrapper.svg` 是可编辑源文件，512 像素 PNG 和多尺寸 Windows ICO 由它生成；
Dioxus 中的副本须逐字节一致。ICO 包含分别从矢量渲染的 16、20、24、32、40、48、
64、96、128 和 256 像素图像。透明背景适用于浅色和深色界面。

使用仓库的 mise 工具，执行 `pnpm install --frozen-lockfile` 后：

```sh
mise run brand:generate
mise run brand:check
```

本地预览可执行 `node scripts/generate-brand.mjs --preview`，输出位于忽略的
`target/brand-preview/` 目录。修改源文件后需检查小尺寸效果。
渲染使用固定版本的开发依赖 `@resvg/resvg-js`；分发的应用不依赖 Node.js。

WinUI 将 ICO 嵌入可执行文件并加载为窗口图标；Dioxus 在界面使用同源 SVG，
在安装包中使用 PNG/ICO。文档站生成的 `docs/public/favicon.svg` 与原始 SVG 一致，
供页眉和首页使用。这遵循微软的[图标构建指南](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction)。
