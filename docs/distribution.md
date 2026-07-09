# Windows 分发与安装方案

## 原则

SteamWrapper 面向普通 Windows 玩家时，安装方式必须尽量简单。

主推：

```text
SteamWrapper-v2.x.x-win-x64-setup.exe
```

备选：

```text
SteamWrapper-v2.x.x-win-x64-portable.zip
```

## setup.exe

setup.exe 使用 Tauri 的 NSIS 打包目标。

用户体验目标：

```text
双击安装程序
→ 下一步
→ 选择安装路径
→ 安装
→ 完成
```

建议安装位置：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
```

原因：

- 默认不需要管理员权限；
- 符合普通 Windows 用户习惯；
- 升级和卸载路径清晰；
- 不污染游戏目录。

## 用户数据目录

用户配置、日志、备份和 Runner 稳定路径放在：

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

Steam Launch Options 应该引用：

```text
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

不要引用安装器临时路径，也不要引用 portable zip 的临时解压路径。

## portable zip

portable zip 面向高级用户，结构大致为：

```text
SteamWrapperManager.exe
SteamWrapperRunner.exe
README.zh-CN.md
```

首次启动 Manager 时，如果检测到 portable 模式，应该提示用户把 Runner 安装到稳定路径：

```text
%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe
```

否则用户移动或删除解压目录后，Steam 启动选项会失效。

## Runner 分发策略

Manager 可以通过安装包附带 Runner，后续首次启动时复制到稳定路径。

Runner 不应该做成 Tauri GUI，也不应该依赖 WebView。它是被 Steam 调用的无界面原生程序。

## 本地封面策略

第一阶段不接入在线封面 API。

Manager 只读取：

```text
<Steam安装目录>\appcache\librarycache\
<Steam安装目录>\userdata\<steamid>\config\grid\
```

找不到封面时显示占位图即可。
