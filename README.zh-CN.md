# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper 图标" width="112" height="112" />
</p>

[English](README.md) | 简体中文

**配置一次，从 Steam 正常启动游戏。** SteamWrapper 将 Steam 库条目关联到你选择的游戏程序或启动器。Manager 负责配置，日常游玩由 Steam 调用独立、无界面的 Rust Runner。

[文档](https://yangyus8.top/SteamWrapper/zh-cn/) · [开始使用](https://yangyus8.top/SteamWrapper/zh-cn/guides/getting-started/) · [安装](https://yangyus8.top/SteamWrapper/zh-cn/guides/installation/) · [问题反馈](https://github.com/YangYuS8/SteamWrapper/issues)

## 当前状态

项目优先做好 Windows。**WinUI 3/C# Manager 已有可用预览**，支持本地 Steam 发现、原生选择器、保留语法的配置编辑、高级参数与启动选项复制。WinUI 是唯一的 Manager；旧 Dioxus 界面与发布链已移除。选择构建产物前请阅读安装指南；干净系统验收和 WinUI 安装器仍待完成。

Manager 默认英语，提供完整简体中文。切换语言保留游戏名称、路径、参数与已保存配置。请将官方 Steam 安装与第三方汉化版分开放置，详见[汉化游戏、存档与成就](https://yangyus8.top/SteamWrapper/zh-cn/guides/translated-games/)。兼容性记录限定于具体游戏和场景，不保证所有游戏均可用。

封面优先使用自定义与本地 Steam 图片。可选的官方 Steam CDN 补图默认关闭，使用有界的 SteamWrapper 缓存并提供清理入口；缺图不影响配置或启动。详见[封面设置](https://yangyus8.top/SteamWrapper/zh-cn/guides/configuration/#cover-settings)。

## 文档

[Astro Starlight 文档站](https://yangyus8.top/SteamWrapper/)是主要的使用与开发文档入口，提供完整[简体中文](https://yangyus8.top/SteamWrapper/zh-cn/)。

| 读者 | 从这里开始 |
| --- | --- |
| 玩家 | [开始使用](https://yangyus8.top/SteamWrapper/zh-cn/guides/getting-started/)、[游戏配置](https://yangyus8.top/SteamWrapper/zh-cn/guides/configuration/)、[故障排查](https://yangyus8.top/SteamWrapper/zh-cn/guides/troubleshooting/) |
| 开发者 | [Windows 环境](https://yangyus8.top/SteamWrapper/zh-cn/development/windows/)、[架构](https://yangyus8.top/SteamWrapper/zh-cn/development/architecture/)、[测试](https://yangyus8.top/SteamWrapper/zh-cn/development/testing/) |
| 贡献者 | [文档维护](https://yangyus8.top/SteamWrapper/zh-cn/development/documentation/)、[路线图](https://yangyus8.top/SteamWrapper/zh-cn/project/roadmap/)、[贡献指南](CONTRIBUTING.zh-CN.md) |

可编辑源文件位于 [docs/](docs/README.zh-CN.md)。历史设计和验证记录与当前使用说明分开组织。

## 本地开发

请从 `main` 创建聚焦的功能分支，并将拉取请求提交到 `main`。按自己的方式安装改动所需工具；[mise](mise.toml) 是可选的便利工具，不是贡献者要求。SDK 版本与 MSVC/SDK 安装见 Windows 环境指南。在 PATH 中准备好 PowerShell 7、.NET 和 Rust 后，WinUI 预览命令如下：

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test
pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

发布目录为 `target/winui/publish`，请保持整个目录完整。沙盒使用一次性的 Steam／用户数据夹具。日常预览应使用沙盒。WinUI 和各平台 Runner 门禁见测试指南。

仅维护文档时，按自己的方式安装 Node 24.18.0（已验证的参考版本）和 `package.json` 声明的 pnpm 版本，再执行：

```sh
pnpm install --frozen-lockfile
pnpm docs:dev
pnpm docs:check
pnpm docs:build
```

Node/pnpm 用于开发和静态文档构建，不是桌面应用的运行要求。

## 社区与许可证

请阅读[贡献指南](CONTRIBUTING.zh-CN.md)、[行为准则](CODE_OF_CONDUCT.zh-CN.md)、[安全策略](SECURITY.zh-CN.md)和[使用帮助](SUPPORT.zh-CN.md)。欢迎英语和简体中文反馈。报告中不得包含凭据、未脱敏用户数据、存档或游戏二进制。SteamWrapper 不注入 DLL、不修补游戏／Steam 二进制、不绕过 DRM，也不上传用户数据。

默认分支 `main` 包含 v2，使用 [Apache-2.0](LICENSE)。历史 v1 标签和提交保留其原有许可证。拉取请求以 `main` 为目标，社区模板和 GitHub Pages 文档也由该分支提供。合入主线不代表 WinUI 预览已成为稳定版本；后续工作见[交付路线图](https://yangyus8.top/SteamWrapper/zh-cn/project/roadmap/)。

[原创项目图标](assets/brand/README.zh-CN.md)结合了 Rust 风格的铜色齿轮和 Steam 风格的连杆。SteamWrapper 与 Valve 或 Rust 项目没有隶属或背书关系。
