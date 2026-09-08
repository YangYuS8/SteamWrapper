# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="112" height="112" />
</p>

[English](README.md) | 简体中文

**配置一次，从 Steam 正常启动游戏。** SteamWrapper 将 Steam 库条目关联到你选择的游戏程序或启动器。Manager 负责配置，日常游玩由 Steam 调用独立、无界面的 Rust Runner。

[文档](https://yangyus8.top/SteamWrapper/zh-cn/) · [开始使用](https://yangyus8.top/SteamWrapper/zh-cn/guides/getting-started/) · [安装](https://yangyus8.top/SteamWrapper/zh-cn/guides/installation/) · [问题反馈](https://github.com/YangYuS8/SteamWrapper/issues)

## 当前状态

项目优先做好 Windows。**WinUI 3/C# Manager 已有可用预览**，支持本地 Steam 发现、原生选择器、保留语法的配置编辑、高级参数与启动选项复制。保留的 Dioxus Manager 使用自己的发布工作流，默认交付链尚未切换。选择构建产物前请阅读安装指南；干净系统验收和 WinUI 安装器仍待完成。

两套 Manager 均默认英语，提供完整简体中文。切换语言保留游戏名称、路径、参数与已保存配置。请将官方 Steam 安装与第三方汉化版分开放置，详见[汉化游戏、存档与成就](https://yangyus8.top/SteamWrapper/zh-cn/guides/translated-games/)。兼容性记录限定于具体游戏和场景，不保证所有游戏均可用。

## 文档

[Astro Starlight 文档站](https://yangyus8.top/SteamWrapper/)是主要的使用与开发文档入口，提供完整[简体中文](https://yangyus8.top/SteamWrapper/zh-cn/)。

| 读者 | 从这里开始 |
| --- | --- |
| 玩家 | [开始使用](https://yangyus8.top/SteamWrapper/zh-cn/guides/getting-started/)、[游戏配置](https://yangyus8.top/SteamWrapper/zh-cn/guides/configuration/)、[故障排查](https://yangyus8.top/SteamWrapper/zh-cn/guides/troubleshooting/) |
| 开发者 | [Windows 环境](https://yangyus8.top/SteamWrapper/zh-cn/development/windows/)、[架构](https://yangyus8.top/SteamWrapper/zh-cn/development/architecture/)、[测试](https://yangyus8.top/SteamWrapper/zh-cn/development/testing/) |
| 贡献者 | [文档维护](https://yangyus8.top/SteamWrapper/zh-cn/development/documentation/)、[路线图](https://yangyus8.top/SteamWrapper/zh-cn/project/roadmap/)、[贡献指南](CONTRIBUTING.zh-CN.md) |

可编辑源文件位于 [docs/](docs/README.zh-CN.md)。历史设计和验证记录与当前使用说明分开组织。

## 本地开发

请在 `v2` 上开发。使用固定版本的 [mise 工具](mise.toml)，按 Windows 环境指南安装 MSVC/SDK。WinUI 预览命令如下：

```powershell
mise run winui:test
mise run winui:contracts
mise run winui:publish
mise run winui:sandbox
```

发布目录为 `target/winui/publish`，请保持整个目录完整。沙盒使用一次性的 Steam／用户数据夹具。`just dev` 会读取真实本地数据；日常 Dioxus 预览应使用 `just dev-sandbox`。保留的 Dioxus 与各平台门禁见测试指南。

仅维护文档时：

```sh
mise install node pnpm
mise exec -c "pnpm install --frozen-lockfile"
mise run docs:dev
mise run docs:check
mise run docs:build
```

Node/pnpm 用于开发和静态文档构建，不是桌面应用的运行要求。

## 社区与许可证

请阅读[贡献指南](CONTRIBUTING.zh-CN.md)、[行为准则](CODE_OF_CONDUCT.zh-CN.md)、[安全策略](SECURITY.zh-CN.md)和[使用帮助](SUPPORT.zh-CN.md)。欢迎英语和简体中文反馈。报告中不得包含凭据、未脱敏用户数据、存档或游戏二进制。SteamWrapper 不注入 DLL、不修补游戏／Steam 二进制、不绕过 DRM，也不上传用户数据。

`v2` 分支使用 [Apache-2.0](LICENSE)。GitHub 默认分支仍为 `main`，其中旧实现及其许可证独立保留。此实现的贡献应提交到 `v2`；GitHub 社区模板入口跟随默认分支。文档通过 GitHub Pages Actions 从 `v2` 部署。

[原创项目图标](assets/brand/README.zh-CN.md)结合了 Rust 风格的铜色齿轮和 Steam 风格的连杆。SteamWrapper 与 Valve 或 Rust 项目没有隶属或背书关系。
