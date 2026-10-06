---
title: 安装 Windows 版 SteamWrapper
description: 安装或使用完整的 Windows 发行版，保留游戏配置，并安全更新。
---

**Windows 11 24H2 x64** 用户建议使用 **Setup 安装包**。它包含运行 Manager 所需的文件，无需开发工具或单独安装运行时。其他 Windows 版本尚未验证。

**[下载安装包 — v0.2.8](https://github.com/YangYuS8/SteamWrapper/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe)** · [CNB 镜像](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe) · [发布说明与其他下载](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8)

GitHub 和 CNB 提供相同且已核验的安装包，对应 **v0.2.8，最新稳定版**。发行版有三个下载附件：Setup、便携 ZIP 和 `SHA256SUMS`。它没有 Windows Authenticode 签名，因此 Windows 可能显示未知发布者提示。请使用上面的官方下载，并保持正常 Windows 防护开启。

<a id="获取带版本的预览包"></a>
<a id="打开完整应用"></a>

## 安装并打开 Manager

1. 下载 Setup，在**文件资源管理器**中打开。选择 English 或简体中文作为安装器语言。
2. 选择**固定本地磁盘上的空目录**。大多数玩家可保留默认位置 `%LOCALAPPDATA%\Programs\SteamWrapper`。安装位置不支持网络共享或可移动磁盘。
3. 选择快捷方式。**开始菜单快捷方式默认开启**，**桌面快捷方式默认关闭**。
4. 完成安装。可以选择立即打开 Manager，也可以稍后通过快捷方式打开。

请使用**平时运行 Steam 的同一个 Windows 账户**运行 Setup 和 Manager。日常安装和使用不需要“**以管理员身份运行**”或“**以其他用户身份运行**”。

没有已保存的语言选择时，Manager 跟随已支持的系统界面语言，否则使用英语。侧栏的 **English / 简体中文** 选择器可保存手动选择。按照[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)配置一次游戏，之后照常从 Steam 启动。只有修改配置时才需要打开 Manager。

<a id="备选便携-zip"></a>

## 使用便携 ZIP

如果不想安装 Manager，请从[同一发布页](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8)下载 **`SteamWrapper-v0.2.8-win-x64.zip`**。将**完整 ZIP** 解压到准备保留的目录，再通过文件资源管理器打开 `SteamWrapper.Manager.exe`。

请保留全部配套文件。不要在 ZIP 内运行 EXE，也不要只复制 EXE。移动完整目录前先关闭 Manager。单独存放的游戏配置和稳定 Runner 仍在原来的位置，因此移动 Manager 不需要修改 Steam 启动项。

更新便携版时，将新的完整 ZIP 解压到新目录，关闭旧 Manager，再打开新副本。应用内安装器不会覆盖便携目录。

<a id="更新-manager-并准备-runner"></a>

## 更新应用

打开 Manager 的“**更新**”，选择“**检查更新**”。自动检查**默认关闭**；需要时可开启“**打开 SteamWrapper 时检查更新**”。下载和安装仍需要你确认。

“**下载来源**”默认为“**自动**”，先尝试 GitHub，网络失败时可使用已核验的 CNB 镜像。你也可以自行选择 GitHub 或 CNB。更新信息必须通过项目签名验证，下载的安装包必须与记录的大小和摘要一致。项目签名与 Windows 发布者证书不同，玩家无需安装证书。

安装版选择“**下载更新**”，完成后选择“**安装更新**”并确认。先保存或放弃未保存的修改。Manager 会正常退出以便安装，并在成功后重新打开。更新和修复保留已注册的安装目录及独立数据。连接或验证失败时，可以继续使用当前版本，稍后重试。

更新 Manager 不会替换 Steam 使用的稳定 Runner。之后明确选择“**保存并生成启动项**”才会在安全时检查并准备 Runner。如果 Runner 正被占用，请让游戏正常结束后重试；SteamWrapper 不会强制关闭游戏。使用新启动命令前，请先处理界面显示的 Runner 提示，详见 [Runner 排错](/SteamWrapper/zh-cn/guides/troubleshooting/)。

<a id="manager-与-runner-的数据位置"></a>

## 程序文件和用户数据

Manager 的程序目录与持久数据分开存放：

| 位置 | 内容 |
| --- | --- |
| 选择的安装目录，通常为 `%LOCALAPPDATA%\Programs\SteamWrapper` | 安装版 Manager 及配套文件。 |
| 完整 ZIP 的解压目录 | 便携版 Manager 及配套文件。 |
| `%LOCALAPPDATA%\SteamWrapper\` | 游戏配置、Manager 偏好、配置备份、日志和下载缓存。 |
| `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe` | Steam 启动项引用的稳定、独立 Runner。 |

Steam 启动项应始终指向稳定 Runner，不要指向 Manager 程序目录里的副本。配置备份**不是游戏存档备份**；游戏存档有各自的位置。

<a id="移除预览版"></a>

## 卸载或更换安装位置

关闭 Manager，然后打开 **Windows 设置 → 应用 → 安装的应用 → SteamWrapper → 卸载**。默认只移除属于 Manager 的程序文件、快捷方式和注册信息，**保留游戏配置、Runner 及其他独立数据**。

卸载器还提供[七个可选恢复与清理选项](/SteamWrapper/zh-cn/guides/installer-preview/#卸载)，全部默认关闭。只选择你想移除的部分。任何选项都不会删除游戏文件或存档。恢复 Steam 启动命令或删除配置、Runner 前，请先正常退出 Steam；不确定时保留它们。

更换安装版 Manager 的位置时，先在全部可选清理项关闭的情况下卸载，再安装到新的空目录。更新和修复不会迁移安装位置。

便携版可在关闭 Manager 后删除解压的程序目录，独立数据会保留。Steam 启动项仍引用稳定 Runner 时，不要手动删除它。

<a id="获取按需工作流预览"></a>
<a id="可选手动校验下载"></a>
<a id="在本机构建预览版"></a>

## 更多信息

[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)介绍修复和清理细节。[分发说明](/SteamWrapper/zh-cn/development/distribution/)介绍发布文件、下载完整性和预览工作流。从源码构建见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)，安装和游玩不需要这些开发工具。
