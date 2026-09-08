---
title: 安装 Windows 预览版
description: 获取完整 WinUI 预览版，了解数据位置，并在不破坏 Steam 启动项的前提下更新。
---

WinUI Manager 当前提供**面向 Windows 11 24H2 x64 的自包含目录预览版**。应用目录中包含 .NET 与 Windows App SDK 文件，请始终保留完整目录。

目前没有新的 WinUI 安装向导、单文件 EXE，也尚未完成干净系统、更新与卸载的交付保证。Dioxus 及其既有发布工作流仍然保留。WinUI 的程序名是 `SteamWrapper.Manager.exe`，Dioxus 的程序名是 `SteamWrapperManager.exe`。

## 获取 CI 预览包

1. 打开仓库的 [WinUI Windows preview 工作流](https://github.com/YangYuS8/SteamWrapper/actions/workflows/winui-windows.yml)。
2. 选择所需 `v2` 代码版本对应的一次成功运行。
3. 如果该运行的产物仍然可用，下载 **`SteamWrapper-WinUI-preview-windows-x64`**。
4. 将整个压缩包解压到准备保留的目录中。

工作流完成测试和发布检查后上传应用目录。产物是否可下载取决于具体运行及保留期限；没有合适产物时，可以使用下面的本地构建方式。托管 CI 显示绿色，本身不代表所有 Windows 安装环境或游戏都已兼容。

请下载应用产物，不要把单独的 `WinUI-Windows-contract-evidence` 测试结果产物当成应用。

## 打开完整应用

通过普通 Windows 文件资源管理器进入解压目录，双击 **`SteamWrapper.Manager.exe`**。

保留旁边的 DLL、原生 `.pri` 资源、`Assets`、`Runner` 与 `zh-CN` 资源。不要在 ZIP 内运行 EXE，不要把它与支持文件分开，也不要把契约测试驱动当成 Manager。

界面默认使用英语，可通过 **English / 简体中文** 选择器切换。随后按照[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)添加游戏。

如果 Windows 报告下载或安全问题，先确认产物的来源和完整性。SteamWrapper 不要求全局关闭 Windows 防护。摘要校验只能确认文件与某个产物一致，不能代替发布者签名，也不是第三方游戏安全性的结论。

## 在本机构建预览版

这是从源码开发和生成产物的方式，不是每位下载预览版的玩家都需要进行的运行环境准备。

准备 Windows 上的 `v2` 分支工作副本，并安装 [mise](https://mise.jdx.dev/)。在仓库根目录的 PowerShell 中执行：

```powershell
mise trust
mise install
mise run windows:setup
mise run windows:doctor
mise run winui:publish
```

信任前先审阅仓库配置。系统准备任务会通过 Microsoft 安装器安装声明的 MSVC/Windows SDK 组件，可能请求 UAC 权限。如果提示需要重启，请先完成重启，再依赖该环境进行后续操作。

发布目录为：

```text
target\winui\publish\
```

通过文件资源管理器打开完整目录并运行其中的 Manager。实际源码项目不要求额外安装独立的 alpha WinUI 模板。

如果只想预览配置界面，不使用真实 Steam 或用户数据，可以运行：

```powershell
mise run winui:sandbox
```

沙盒包含示例 manifest 和隔离的用户目录，没有你的真实游戏库，也没有可玩的游戏。沙盒中创建的配置不是实际 Steam 配置。

准确的命令和工具版本由 [mise.toml](https://github.com/YangYuS8/SteamWrapper/blob/v2/mise.toml)及 [Windows 构建脚本](https://github.com/YangYuS8/SteamWrapper/blob/v2/scripts/windows/Invoke-WinUI.ps1)维护。

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
| `ui-settings.json` | Manager 的显示语言偏好 |
| `bin\SteamWrapperRunner.exe` | Steam 引用的稳定、独立 Runner |
| `logs` | Runner 诊断，以及能够记录时的 Manager 启动诊断 |
| `backups` | 配置备份，不是自动游戏存档保护 |
| `cache` | SteamWrapper 的缓存位置 |

游戏存档可能位于游戏目录、Windows 用户目录或 Steam 存储中，需要另行识别并保护。

## 更新 Manager 并准备 Runner

替换应用文件前，关闭 Manager，并让正在运行的游戏与 Runner 会话正常结束。将新的完整预览版解压到独立目录，再通过文件资源管理器打开这个 Manager。

保存配置时会检查随包 Runner，并准备稳定目录中的副本。WinUI 服务会保留较新的兼容 Runner；如果遇到未知版本，或同版本但文件内容不同且无法确定安全更新顺序，会拒绝替换。文件占用或校验失败会显示错误，不应通过删除用户配置绕过。

如果 Manager 显示配置已保存、但启动组件尚未就绪，请阅读[Runner 排错](/SteamWrapper/zh-cn/guides/troubleshooting/)。保留的 Dioxus 应用在设置中有自己的 Runner 安装/修复操作，那不是 WinUI 额外隐藏的一页。

Steam 启动项应始终引用稳定的 `bin\SteamWrapperRunner.exe`，而不是解压包内的 `Runner` 目录。完整移动 Manager 目录后，不应仅因为 Manager 位置变化，就需要逐个游戏重写启动项。

## 移除预览版

WinUI 目录预览版尚无经过验收的新卸载器。删除它的应用目录，不会删除另行存放的稳定 Runner 和配置。

移除稳定 Runner 或其数据前，应恢复所有仍然引用它的 Steam 启动选项，并保留所需配置备份。如果 Steam 仍指向已经删除的 Runner，相应游戏条目就无法正确启动。

完整设置流程请继续阅读[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)。
