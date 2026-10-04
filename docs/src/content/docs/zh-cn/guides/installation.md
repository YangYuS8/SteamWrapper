---
title: 安装 Windows 预览版
description: 获取完整 WinUI 预览版，了解数据位置，并在不破坏 Steam 启动项的前提下更新。
---

WinUI Manager 当前提供**面向 Windows 11 24H2 x64 的自包含目录预览版**。应用目录中包含 .NET 与 Windows App SDK 文件，请始终保留完整目录。

另已提供没有 Windows Authenticode 签名的[每用户安装器预览](/SteamWrapper/zh-cn/guides/installer-preview/)。版本标签同时打包 Setup 与便携 ZIP，干净客户端和更广泛恢复验收仍待完成，WinUI 没有单文件 EXE。WinUI 是唯一的 Manager，程序名为 `SteamWrapper.Manager.exe`。Dioxus 发布属于历史产物，不包含当前 WinUI Manager。本页说明便携 ZIP；安装位置、快捷方式与卸载选择请阅读安装器指南。

## 获取带版本的预览包

1. 打开 [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases)，选择说明中明确标识 **WinUI Windows x64 portable 预览**的发布。
2. 阅读已知限制及英语或简体中文说明。历史 Dioxus 安装包不是当前应用。
3. 下载该发布的 **`SteamWrapper-<tag>-win-x64.zip`** 与 **`SHA256SUMS`**，ZIP 中的标签应与所选发布一致。
4. 对照 `SHA256SUMS` 中对应一行验证 ZIP 的 SHA-256，再将整个 ZIP 解压到准备保留的目录中。

例如，PowerShell 命令 `Get-FileHash -Algorithm SHA256 -LiteralPath '.\SteamWrapper-v0.2.1-preview.1-win-x64.zip'` 会显示待对照的摘要。这只是文件名示例，不表示该版本已经发布。发布附件还包含 `release.json` 和独立的英语／简体中文说明。

如果没有可用 WinUI 发布，可以使用下面的手动工作流预览或本地构建。发布工作流仅在门禁和包检查通过后公开产物；运行成功不代表所有 Windows 安装环境或游戏都已兼容。

## 获取按需工作流预览

常规拉取请求与合入 `main` 只运行 CI，不上传应用包。维护者可以打开 [WinUI version release 工作流](https://github.com/YangYuS8/SteamWrapper/actions/workflows/winui-release.yml)，在 **Run workflow** 中选择所需分支或 ref，按需请求构建。手动运行执行完整构建和门禁，但不会公开创建 Release。

从成功的手动运行下载 **`SteamWrapper-WinUI-preview-windows-x64`**，解压全部文件。不要把单独的测试证据产物当成应用。工作流产物下载可能要求登录 GitHub，且会随保留期限到期；维护者提供预览时应同时标明所选源码提交。

独立的 **`SteamWrapper-WinUI-installer-preview-windows-x64`** 产物包含没有 Windows Authenticode 签名的安装器预览与检查元数据。使用前阅读[安装器指南](/SteamWrapper/zh-cn/guides/installer-preview/)，干净客户端验收尚未通过。

## 打开完整应用

通过普通 Windows 文件资源管理器进入解压目录，双击 **`SteamWrapper.Manager.exe`**。

保留旁边的 DLL、原生 `.pri` 资源、`Assets`、`Runner` 与 `zh-CN` 资源。不要在 ZIP 内运行 EXE，不要把它与支持文件分开，也不要把契约测试驱动当成 Manager。

没有已保存的偏好时，界面跟随已支持的系统界面语言，不支持时回退英语。**English / 简体中文** 选择器可保存手动选择。随后按照[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)添加游戏。

如果 Windows 报告下载或安全问题，先确认产物的来源和完整性。SteamWrapper 不要求全局关闭 Windows 防护。摘要校验只能确认文件与某个产物一致，不能代替发布者签名，也不是第三方游戏安全性的结论。

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
