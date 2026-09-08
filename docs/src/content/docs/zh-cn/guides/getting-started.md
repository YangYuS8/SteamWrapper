---
title: 开始使用
description: 在 Windows 上配置一次，以后仍从原来的 Steam 游戏库条目启动游戏。
---

SteamWrapper 可以让 Steam 启动你选择的游戏程序或启动器。**Manager 负责配置，独立的 Runner 负责日常启动。** 完成设置后，Manager 可以一直保持关闭。

本指南使用 **WinUI Windows 预览版**，当前面向 Windows 11 24H2 x64。保留的 Dioxus 应用及其发布链是另一套交付方式；新的 WinUI 安装器尚未交付。如果还没有完整的预览版目录，请先阅读[安装指南](/SteamWrapper/zh-cn/guides/installation/)。

## 配置前准备

确认游戏已在 Steam 中安装，并找到你真正想运行的程序。如果使用汉化版或其他版本，先确认它的完整目录可以通过普通文件资源管理器直接启动。

将 Steam 官方安装与完整的第三方汉化版放在两个独立目录中。移动或测试游戏前，单独备份实际存档。SteamWrapper 的配置备份**不是游戏存档备份**。修改官方文件与汉化文件混放的目录前，请先阅读[汉化游戏与存档](/SteamWrapper/zh-cn/guides/translated-games/)。

## 1. 打开 Manager

完整解压预览版，在**文件资源管理器中双击 `SteamWrapper.Manager.exe`**。不要把 EXE 单独拷出目录，也不要直接在下载的 ZIP 中运行它。

没有已保存的语言偏好时，界面以英语显示。在侧栏的 **Language** 中选择 **简体中文** 即可切换。成功切换后，偏好会保存到下一次启动。

## 2. 添加 Steam 游戏

1. 选择 **＋ 添加游戏**。
2. 从本机发现的 Steam 游戏库中选择游戏，可以按名称或 AppID 搜索。
3. 选择 **使用此游戏**。

如果没有找到 Steam，可以使用 **选择 Steam 文件夹…**。也可以选择 **手动填写 AppID**，输入原游戏有效的正整数 Steam AppID。这里应填写你打算从 Steam 游戏库启动的那个条目的 AppID。

如果该游戏已经有唯一匹配的配置，Manager 会打开原配置进行编辑。如果同一个 AppID 匹配了多份配置，需要先解决冲突再保存。

## 3. 选择实际运行的程序

核对下列字段：

| 字段 | 应填写或选择什么 |
| --- | --- |
| 游戏名称 | 便于你识别的名称 |
| Steam 安装位置 | Steam 管理的官方安装位置，仅供查看 |
| 实际运行文件夹 | 你想游玩的完整版本所在目录 |
| 要运行的程序 | 该版本实际使用的游戏或启动器 `.exe` |

例如，官方安装可以继续留在 Steam 库内，将 **实际运行文件夹** 设置为 `G:\OtherGames\Example Game`，并在 **要运行的程序** 中选择其中的汉化启动器。

除非游戏或启动器要求另一个工作目录，否则保持高级设置中的工作目录为空。新 Windows 配置默认使用 **等待程序及其子进程（推荐）**。特殊情况请参考[详细配置](/SteamWrapper/zh-cn/guides/configuration/)与[等待模式](/SteamWrapper/zh-cn/guides/wait-modes/)。

## 4. 保存并准备 Runner

选择 **保存并生成启动项**。Manager 会保存配置、检查随包 Runner，并在允许时将它安装或更新到 SteamWrapper 的稳定用户数据目录。

当成功消息说明启动组件已就绪，且界面显示启动项文本后，再继续下一步。如果提示配置已经保存、但启动组件尚未就绪，说明配置保存成功，运行组件仍需处理。修改 Steam 前先按照[排错指南](/SteamWrapper/zh-cn/guides/troubleshooting/)解决问题。

## 5. 把启动项复制到 Steam

1. 在 Steam 中右键同一个游戏，打开 **属性 → 通用 → 启动选项**。
2. 将原来的完整值复制到以后找得到的位置；原本为空，也要明确记录为空。
3. 在 Manager 中选择 **复制启动项**。
4. 将生成的文本粘贴到 Steam 的启动选项中。

生成的命令格式如下，请使用 Manager 的实际输出，而不是直接照抄示例：

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

保留生成的引号、`--appid`、独立的 `--` 和末尾的 `%command%`。不要把 Runner 换成 Manager EXE，也不要改成临时解压目录中的文件。

**复制不会自动应用到 Steam。** 当前预览版需要手动完成粘贴。Runner 会接收并记录 Steam 展开的原始命令，但实际启动配置中的目标程序和参数，不会自动把原命令追加给游戏。

## 6. 正常启动与退出

关闭 Manager，然后在原来的 Steam 游戏库条目中点击 **开始**。

确认打开的是预期的游戏或汉化版，通过游戏正常的退出方式结束，再检查 Steam 是否回到停止状态。运行状态、显示时长、Overlay 和成就是不同的观察项；其中一项成功，并不能证明其他项也成功。

以后游玩时照常使用 Steam 即可。只有修改配置或处理 Runner 问题时，才需要重新打开 Manager。

## 撤销某个游戏的设置

恢复配置前记录的原启动选项；原本为空就清空该字段。这样会移除该 Steam 条目对 Runner 的引用，但不会移动游戏文件或恢复游戏进度。

如果只是测试，结束后应恢复原启动项。游戏自然更新的存档应继续保留，除非你另行明确决定如何恢复存档。遇到云存档冲突时先停下，不要猜测应该覆盖哪份进度。

接下来可以阅读[详细配置](/SteamWrapper/zh-cn/guides/configuration/)或[排错指南](/SteamWrapper/zh-cn/guides/troubleshooting/)。
