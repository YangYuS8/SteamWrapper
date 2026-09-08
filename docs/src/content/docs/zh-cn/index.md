---
title: SteamWrapper 文档
description: 配置 Steam 游戏启动、构建 Windows Manager，并了解独立 Runner 的工作方式。
template: splash
hero:
  title: 配置一次，从 Steam 启动。
  image:
    html: '<img src="/SteamWrapper/favicon.svg" width="420" height="420" alt="SteamWrapper 铜色齿轮与连杆图标" />'
  tagline: SteamWrapper 使用与开发文档——Windows 优先的 Manager 和独立 Rust Runner。
  actions:
    - text: 开始使用
      link: /SteamWrapper/zh-cn/guides/getting-started/
      icon: right-arrow
    - text: 在 Windows 上构建
      link: /SteamWrapper/zh-cn/development/windows/
      variant: secondary
---

SteamWrapper 将 Steam 库中的游戏关联到你选择的游戏程序或启动器。在 Manager 中配置后，将生成的启动选项复制到 Steam；日常游玩时可以关闭 Manager。

:::note[当前交付状态]
WinUI 3 Windows Manager 仍是预览版；保留的 Dioxus Manager 使用独立发布工作流。请先阅读[安装指南](/SteamWrapper/zh-cn/guides/installation/)选择合适的构建产物。文档中的功能或历史测试不代表所有游戏均兼容。
:::

## 使用 SteamWrapper

| 你想完成的事 | 阅读 |
| --- | --- |
| 配置第一款游戏 | [开始使用](/SteamWrapper/zh-cn/guides/getting-started/) |
| 选择程序、参数与实际运行文件夹 | [游戏配置](/SteamWrapper/zh-cn/guides/configuration/) |
| 启动器打开游戏后继续保持 Steam 运行状态 | [等待模式](/SteamWrapper/zh-cn/guides/wait-modes/) |
| 分开放置官方版与汉化版 | [汉化游戏](/SteamWrapper/zh-cn/guides/translated-games/) |
| 排查启动或配置问题 | [故障排查](/SteamWrapper/zh-cn/guides/troubleshooting/) |

## 开发与贡献

从 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)开始，再阅读[架构](/SteamWrapper/zh-cn/development/architecture/)，按改动选择相关[测试](/SteamWrapper/zh-cn/development/testing/)。[文档维护指南](/SteamWrapper/zh-cn/development/documentation/)说明本站的编辑、翻译、预览和发布流程。

[代码贡献](https://github.com/YangYuS8/SteamWrapper/blob/v2/CONTRIBUTING.zh-CN.md)、[问题反馈](https://github.com/YangYuS8/SteamWrapper/issues)与[安全报告](https://github.com/YangYuS8/SteamWrapper/blob/v2/SECURITY.zh-CN.md)分别有对应指南。项目主语言为英语，每篇文档均有完整简体中文版本，可通过语言选择器切换。

## 了解项目

[路线图](/SteamWrapper/zh-cn/project/roadmap/)与 [Windows 设计](/SteamWrapper/zh-cn/project/design/windows-v2/)说明方向和待完成工作。技术决策以及带日期的 [WinUI](/SteamWrapper/zh-cn/project/validation/winui/)／[Steam 验证记录](/SteamWrapper/zh-cn/project/validation/steam/)完整保留原始证据及其限制。
