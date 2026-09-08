---
title: 配置游戏
description: 了解 WinUI Manager 中的游戏目录、程序路径、启动参数、保存和语言偏好。
---

配置用于将一个 Steam AppID 与希望 Runner 启动的程序关联。Manager 负责编辑配置，日常游玩时不需要保持打开。

如果需要完整的 Steam 粘贴与启动流程，请先阅读[开始使用](/SteamWrapper/zh-cn/guides/getting-started/)。

## 选择正确的 Steam 条目

选择 **＋ 添加游戏**，找到本机安装的游戏，然后点击 **使用此游戏**。必要时可以选择 Steam 文件夹，或使用 **手动填写 AppID**。

填写原 Steam 条目的有效正整数 AppID。新 Windows 配置会明确使用 Windows 平台。现有配置保留原有标识，编辑已有条目时 AppID 字段只读。

如果多份配置对应同一个 AppID，Manager 会拒绝不明确的保存。已有唯一匹配配置时，应重新打开它，而不是重复创建。

## 区分两个游戏位置

| 字段 | 含义 |
| --- | --- |
| **Steam 安装位置** | 从 Steam 本机 manifest 发现的官方安装目录，仅供查看 |
| **实际运行文件夹** | Runner 应实际使用的版本所在目录，可以编辑 |
| **要运行的程序** | Runner 启动的现有 `.exe`，可以是游戏本体或启动器 |

汉化游戏可以采用这样的布局：

```text
G:\SteamLibrary\steamapps\common\Example Game\   Steam 官方安装
G:\OtherGames\Example Game\                    完整汉化版
```

将 **实际运行文件夹** 设置为第二个目录，并选择其中正确的程序。两个版本都应完整且相互独立，不要通过硬链接或目录联接共用会变化的游戏资源。详见[汉化游戏与存档](/SteamWrapper/zh-cn/guides/translated-games/)。

**Steam 安装位置** 无法确认时，不会删除或替换你选择的实际运行文件夹。缺失 manifest，或同一 AppID 出现在多个库中，都可能让发现结果不明确。已知实际运行目录时，仍可继续配置。

只有实际运行文件夹为空时，选择程序才会自动填入它。**改选另一个 EXE 不会重置已经填写的实际运行文件夹或工作目录。** 移动游戏后，要检查这两个字段。

## 程序路径与工作目录

实际运行文件夹必须存在，并使用完整路径。WinUI 预览版接受现有 `.exe` 作为目标。

目标可以是绝对路径，也可以相对于实际运行文件夹。例如：

```text
实际运行文件夹：G:\OtherGames\Example Game
要运行的程序：  launcher.exe
实际解析程序：  G:\OtherGames\Example Game\launcher.exe
```

在 **高级设置** 中，**工作目录** 为空时使用实际运行文件夹；绝对工作目录直接使用，相对工作目录则在实际运行文件夹内解析。

```text
工作目录：    resources
实际解析目录：G:\OtherGames\Example Game\resources
```

只有程序需要时才设置不同的工作目录。即使 EXE 存在，工作目录错误仍可能导致缺少资源、显示意外的语言，或使用不同的存档位置。

## 添加启动参数

展开 **高级设置**，选择 **添加参数**。每一行都是**一个参数**；如果有意保留空行，该行代表一个空字符串参数。

假设程序自身说明支持 `--language zh-CN`，应填写两行：

```text
--language
zh-CN
```

如果一个参数是含空格的路径，就把完整路径填在同一行：

```text
G:\Game Data\Example Saves
```

不要为了把一行里的空格连在一起而额外加外层引号。填入行中的引号本身会成为参数值的一部分。只使用所选程序实际支持的选项；SteamWrapper 不解释汉化设置，也不会自动推断游戏专用参数。

Runner 使用这些参数行，不会自动追加原始 Steam 命令或其中的参数。

## 选择 Runner 等待多久

新 Windows 配置默认使用 **等待程序及其子进程（推荐）**，即 `job`。旧配置如果省略了 `wait_mode`，仍然保留 `root` 行为。

其他选项适用于特定启动方式，修改前请阅读[等待模式](/SteamWrapper/zh-cn/guides/wait-modes/)。只有按进程名称等待时才必须填写 **进程名称**。

明确标为其他平台的配置可以在 WinUI 中查看，但不能在这里编辑。Linux/SteamOS 的进程组选项不是 Windows 支持的等待模式。

## 保存并保留已有内容

选择 **保存并生成启动项**。

Manager 先验证路径和 AppID、保存配置，再准备稳定 Runner。保存配置和 Runner 就绪是两个独立结果。如果只有配置成功，应继续处理 Runner 消息；只有 Runner 就绪时，启动项才会显示为可用。

保存后再次编辑字段，会隐藏生成的启动项面板，直到重新保存。单独切换语言不会把配置标为已修改，也不会清除已经成功生成的命令。

离开已修改的配置、重新读取或关闭 Manager 时，选择 **继续编辑** 可以返回尚未保存的内容；确实要放弃时才选择 **放弃修改**。取消原生文件夹或程序选择器会保留当前选择。

编辑器保留未修改的 TOML 值，替换已有文件时会创建配置备份。它会拒绝外部修改冲突、不支持的版本，以及无法安全编辑的布局。不要为了消除冲突，直接覆盖更新的外部文件。

## 复制生成的 Steam 命令

命令始终使用稳定 Runner：

```text
"<stable-runner-path>" --appid "<appid>" -- %command%
```

选择 **复制启动项**，保存游戏原有的 Steam 启动选项，再把生成的命令粘贴到 **Steam → 属性 → 通用 → 启动选项**。复制不会自动修改 Steam。

保留 `%command%` 在 `--` 后的末尾位置。当前 Runner 会接收并记录 Steam 展开的命令，但实际启动配置中的目标和参数；不会同时启动官方 EXE，也不会自动回退到官方程序。

## 选择显示语言

侧栏的 **语言** 选择器提供 **English** 和 **简体中文**。成功切换后，应用自有控件、验证和状态消息立即更新，尚未保存的名称、路径与参数保持不变。

偏好单独保存在 `%LOCALAPPDATA%\SteamWrapper\ui-settings.json`。两套 Manager 使用 `en-US` 或 `zh-CN`，缺失或未知值默认英语；也兼容 `en` 与 `zh-Hans` 别名。语言偏好不进入 `profiles.toml`，也不会修改 Runner CLI。

如果保存偏好失败，界面保留当前语言并显示错误；损坏的设置文件会原样保留。系统 picker 自有文案和原始诊断、日志可能继续使用它们自身的语言。

实现边界见[配置保存服务](https://github.com/YangYuS8/SteamWrapper/blob/v2/apps/manager-winui/SteamWrapper.Application/Profiles/ProfileStore.cs)和 [Runner 配置模型](https://github.com/YangYuS8/SteamWrapper/blob/v2/crates/core/src/profile.rs)。
