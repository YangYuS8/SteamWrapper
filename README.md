# SteamWrapper

仅支持 Windows 平台（程序使用了 Windows 专用的进程管理 API）。

这是一个小工具，用于让 Steam 正确统计汉化版或使用自定义启动器的 galgame 的游玩时长。

核心思路：把 Steam 指定为游戏启动的可执行替换为本程序，由本程序启动真实的游戏启动器（或汉化启动器），并在需要时等待整个子进程树退出，从而让 Steam 能正确记录时长。

使用场景：当你想要让 Steam 启动一个汉化版启动器（而不是官方 exe），可以把 Steam 的启动配置改为启动本程序（例如配合 SteamEdit 修改启动命令）。

快速使用说明：

1. 把本程序放在游戏目录（与要启动的 exe 同目录）
2. 启动一次，程序会在首次运行时生成 `wrapper.config.json`（和一个使用指南文件）
3. 编辑 `wrapper.config.json` 将 `LauncherExe` 设置为你要实际运行的可执行文件名（相对于本程序目录），例如 `nine_kokoiro_chs.exe`。
4. 将 Steam 的启动命令改为启动本程序（或使用 SteamEdit 修改启动配置）

配置示例（wrapper.config.json）：

```
{
	"LauncherExe": "nine_kokoiro_chs.exe",
	"WaitForChildProcessTree": true
}
```

字段说明：

- `LauncherExe`：要由本程序实际启动的 exe 文件名（必须与本程序同目录或使用相对路径）
- `WaitForChildProcessTree`：如果为 `true`，本程序会等待由启动器衍生出的子进程全部退出后再退出（推荐开启，便于 Steam 正确统计时长）
