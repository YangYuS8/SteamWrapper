---
title: 安装 Windows 预览版
description: 获取完整 WinUI 预览版，了解数据位置，并在不破坏 Steam 启动项的前提下更新。
---

**Windows 11 24H2 x64** 用户建议使用 **Setup 安装包**。它会安装 WinUI Manager 及所需的 .NET、Windows App SDK 文件，无需开发工具或单独下载运行时。

**[下载安装包 — v0.2.6-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/download/v0.2.6-preview.1/SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe)** · [CNB 镜像](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.6-preview.1/SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe) · [发布说明与其他下载](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.6-preview.1)

两个来源提供相同且已核验的安装包。Manager 的下载来源选项也支持 CNB；自动模式先尝试 GitHub，网络失败时可使用已核验的 CNB 镜像。

当前仍是没有 Windows Authenticode 签名的技术预览，干净客户端和更广泛恢复验收尚未完成。便携 ZIP 是备选方式。修复与卸载详情见[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)；历史 Dioxus 安装包不包含当前 WinUI Manager。

## 获取带版本的预览包

1. 打开项目官方 [v0.2.6-preview.1 发布页](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.6-preview.1)，阅读已知限制；其他版本见 [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases)。
2. 下载该发布的 **`SteamWrapper-<tag>-win-x64-setup.exe`**，确认文件名版本与所选发布一致，然后在文件资源管理器中打开。
3. 选择 English 或简体中文、安装目录和快捷方式。大多数玩家保留默认目录即可；更换目录时需选择固定本地磁盘上的空目录。开始菜单快捷方式默认开启，桌面快捷方式默认关闭。
4. 完成安装并打开 Manager。界面跟随已支持的系统语言，否则使用英语。按照[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)配置一次游戏，之后照常从 Steam 启动。

升级和修复留在已注册的安装目录。以后若要更换位置，请先只卸载 Manager 并保留数据，再安装到新位置。安装器不会移动游戏或存档。

如果没有可用 WinUI 发布，可以使用下面的手动工作流预览或本地构建。发布工作流仅在门禁和包检查通过后公开产物；运行成功不代表所有 Windows 安装环境或游戏都已兼容。

## 备选：便携 ZIP

如果不想安装 Manager，可从同一个官方发布下载 **`SteamWrapper-<tag>-win-x64.zip`**，完整解压到准备保留的目录，再在文件资源管理器中打开其中的 `SteamWrapper.Manager.exe`。请保留所有配套文件；WinUI 便携版不是单文件 EXE。便携版更新需下载新的完整 ZIP，不使用安装版的应用内安装流程。

## 获取按需工作流预览

常规拉取请求与合入 `main` 只运行 CI，不上传应用包。维护者可以打开 [WinUI version release 工作流](https://github.com/YangYuS8/SteamWrapper/actions/workflows/winui-release.yml)，在 **Run workflow** 中选择所需分支或 ref，按需请求构建。手动运行执行完整构建和门禁，但不会公开创建 Release。

从成功的手动运行下载 **`SteamWrapper-WinUI-preview-windows-x64`**，解压全部文件。不要把单独的测试证据产物当成应用。工作流产物下载可能要求登录 GitHub，且会随保留期限到期；维护者提供预览时应同时标明所选源码提交。

独立的 **`SteamWrapper-WinUI-installer-preview-windows-x64`** 产物包含没有 Windows Authenticode 签名的安装器预览与检查元数据。使用前阅读[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)，干净客户端验收尚未通过。

## 打开完整应用

安装版可通过开始菜单或桌面快捷方式打开。便携 ZIP 则通过普通 Windows 文件资源管理器进入解压目录，双击 **`SteamWrapper.Manager.exe`**。

保留旁边的 DLL、原生 `.pri` 资源、`Assets`、`Runner` 与 `zh-CN` 资源。不要在 ZIP 内运行 EXE，不要把它与支持文件分开，也不要把契约测试驱动当成 Manager。

没有已保存的偏好时，界面跟随已支持的系统界面语言，不支持时回退英语。**English / 简体中文** 选择器可保存手动选择。随后按照[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)添加游戏。

如果 Windows 报告下载或安全问题，先确认产物的来源和完整性。SteamWrapper 不要求全局关闭 Windows 防护。摘要校验只能确认文件与某个产物一致，不能代替发布者签名，也不是第三方游戏安全性的结论。

## 可选：手动校验下载

如需手动检查完整性，从同一发布下载 `SHA256SUMS`，将安装包或 ZIP 的摘要与对应一行比较。PowerShell 命令 `Get-FileHash -Algorithm SHA256 -LiteralPath '.\SteamWrapper-<tag>-win-x64-setup.exe'` 会显示摘要，请把 `<tag>` 换成实际下载版本。附件还包含 `release.json` 和英／中说明。摘要一致表示文件与该发布记录的字节一致，不代表它拥有 Windows 发布者证书。

## 在本机构建预览版

这是从源码开发和生成产物的方式，不是每位下载预览版的玩家都需要进行的运行环境准备。

准备 Windows 上的 `main` 分支工作副本。按自己的方式安装 PowerShell 7、`global.json` 指定的 .NET SDK，以及使用 MSVC host 的 Rust。确保 PATH 中有 `pwsh`、`dotnet` 和 `cargo`；mise 是可选项。在仓库根目录执行：

```powershell
pwsh -NoProfile -File scripts/windows/Install-BuildTools.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
```

系统准备脚本会通过 Microsoft 安装器安装声明的 MSVC/Windows SDK 组件，可能请求 UAC 权限。如果提示需要重启，请先完成重启，再依赖该环境进行后续操作。

发布目录为：

```text
target\winui\publish\
```

通过文件资源管理器打开完整目录并运行其中的 Manager。实际源码项目不要求额外安装独立的 alpha WinUI 模板。

如果只想预览配置界面，不使用真实 Steam 或用户数据，可以运行：

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

沙盒包含示例 manifest 和隔离的用户目录，没有你的真实游戏库，也没有可玩的游戏。沙盒中创建的配置不是实际 Steam 配置。

版本要求的实际清单、可选 mise 别名和完整工具列表见 [Windows 开发环境](/SteamWrapper/zh-cn/development/windows/)。[Windows 构建脚本](https://github.com/YangYuS8/SteamWrapper/blob/main/scripts/windows/Invoke-WinUI.ps1)实现上述直接命令。单独发布 WinUI 不要求 Node、pnpm、Dioxus CLI 或 just。

## Manager 与 Runner 的数据位置

解压的 Manager 目录存放应用文件。Windows 持久数据另行存放在：

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

| 位置 | 用途 |
| --- | --- |
| `profiles.toml` | Runner 使用的游戏配置 |
| `ui-settings.json` | Manager 的语言与可选 Steam 封面下载偏好 |
| `bin\SteamWrapperRunner.exe` | Steam 引用的稳定、独立 Runner |
| `logs` | Runner 诊断，以及能够记录时的 Manager 启动诊断 |
| `backups` | 配置备份，不是自动游戏存档保护 |
| `cache\covers` | 有界的已下载封面缓存；清理会保留 Steam／自定义图片 |

游戏存档可能位于游戏目录、Windows 用户目录或 Steam 存储中，需要另行识别并保护。

## 更新 Manager 并准备 Runner

替换应用文件前，关闭 Manager，并让正在运行的游戏与 Runner 会话正常结束。将新的完整预览版解压到独立目录，再通过文件资源管理器打开这个 Manager。

保存配置时会检查随包 Runner，并准备稳定目录中的副本。WinUI 服务会保留较新的兼容 Runner；如果遇到未知版本，或同版本但文件内容不同且无法确定安全更新顺序，会拒绝替换。文件占用或校验失败会显示错误，不应通过删除用户配置绕过。

如果 Manager 显示配置已保存、但启动组件尚未就绪，请阅读[Runner 排错](/SteamWrapper/zh-cn/guides/troubleshooting/)。

Steam 启动项应始终引用稳定的 `bin\SteamWrapperRunner.exe`，而不是解压包内的 `Runner` 目录。完整移动 Manager 目录后，不应仅因为 Manager 位置变化，就需要逐个游戏重写启动项。

## 移除预览版

对于便携 ZIP，删除解压的应用目录不会删除另行存放的稳定 Runner 和配置。如果使用了 Setup，请通过 Windows 已安装应用设置或它的卸载器卸载。默认卸载保留用户数据；[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)介绍七个可选的恢复／清理选项，限定本机结果及剩余验收单独记录。

移除稳定 Runner 或其数据前，应恢复所有仍然引用它的 Steam 启动选项，并保留所需配置备份。如果 Steam 仍指向已经删除的 Runner，相应游戏条目就无法正确启动。

完整设置流程请继续阅读[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)。
