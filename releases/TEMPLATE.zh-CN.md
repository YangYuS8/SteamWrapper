# <tag> — WinUI Windows x64 预览

SteamWrapper 的 WinUI 3/C# Manager 是**面向 Windows 11 24H2 x64 的未签名预发布**，包含完整自包含 Manager 布局和独立 Rust Runner。它不是 setup 安装器，也不代表 Windows 稳定交付已经通过。

## 变更

- <说明本版本改动及玩家可见的效果。>

## 已知限制

- <说明本版本未解决的问题及验证范围。>
- 发布者签名、WinUI 安装器、干净系统／更新／卸载验收及可选应用更新器仍待完成。
- 在 Manager 配置后，保持 Manager 关闭并从 Steam 启动游戏。Steam 启动项仍需手动复制，不包含自动应用／恢复。
- 游戏、启动器、Overlay 和成就观察只适用于记录中已经验证的具体场景。

## 安装、更新与恢复

从同一发布下载 `SteamWrapper-<tag>-win-x64.zip` 与 `SHA256SUMS`。验证 ZIP 的 SHA-256，完整解压后通过普通文件资源管理器打开 `SteamWrapper.Manager.exe`。保留所有支持资源与 `Runner/` 文件。使用下载的完整应用不需要安装开发 SDK。

替换应用文件前，关闭 Manager，并让正在运行的游戏／Runner 会话正常结束。将更新解压到独立目录。配置、偏好、备份、日志与稳定 Runner 保留在 `%LOCALAPPDATA%\SteamWrapper\`；Steam 应继续引用稳定的 `bin\SteamWrapperRunner.exe`，不能改为 ZIP 内的随包 Runner。如果安装／修复报告文件占用或未知 Runner 版本，保留可用副本与配置，按实际错误提示处理恢复。

详见[安装与恢复](https://yangyus8.top/SteamWrapper/zh-cn/guides/installation/)和[故障排查](https://yangyus8.top/SteamWrapper/zh-cn/guides/troubleshooting/)。校验和只能确认文件与列出的附件一致，不能认证发布者。删除解压的 Manager 目录不会恢复 Steam 启动项，也不会删除另行存放的稳定 Runner／数据。
