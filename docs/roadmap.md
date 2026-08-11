# SteamWrapper v2 Roadmap

## 路线原则

SteamWrapper v2 是长期支持主线。除非以后出现必须破坏兼容性的架构原因，否则不再单独规划 v3 主线。

v2 的目标平台从一开始就包括：

- Windows 桌面 Steam；
- Linux 桌面 Steam；
- SteamOS / Steam Deck 桌面模式；
- Windows 游戏经 Proton 启动时的自定义 launcher 场景。

开发顺序仍然保持渐进：先让核心闭环可靠，再扩展一键应用、分发和平台兼容性。跨平台能力不再后置到 v3。

## v2.0 - 无感启动基础闭环

目标：完成 Manager / Runner 分离后的最小可用闭环。

- [x] Rust workspace 基础结构
- [x] Manager / Runner 分离
- [x] Manager 改为 Tauri v2 + React + shadcn/ui 布局
- [x] TOML profile 配置模型
- [x] Runner 支持 `--appid <id> -- %command%` 入口
- [x] Manager 生成 Steam Launch Options
- [x] Manager 保存基础 profile 到稳定数据目录
- [x] Runner 从稳定数据目录读取 `profiles.toml`
- [x] Runner 启动目标 exe / launcher 的基础错误处理
- [x] root-process 等待基线
- [x] 日志目录与 Runner 错误日志
- [x] 基础 README 与使用教程

## v2.1 - 本地 Steam 游戏库与 Manager 可用性

目标：让用户能在 Manager 里可靠看到本机 Steam 游戏，并完成基础配置。

- [x] 扫描 Steam 安装目录基础实现
- [x] 读取 `libraryfolders.vdf` 基础实现
- [x] 扫描 Steam Library 与 `appmanifest_<appid>.acf` 基础实现
- [x] 读取本地 Steam 封面缓存基础实现
- [x] 封面缺失时显示占位图，不联网
- [x] 过滤 Proton / Steam Linux Runtime / Steamworks Redistributables 等非游戏条目
- [x] 按 AppID 去重，避免同一 Steam 库被符号链接重复扫描
- [x] Manager 自定义标题栏与可折叠侧边栏
- [x] 已配置游戏列表与 profile 编辑
- [x] 日志页展示最近 Runner 启动记录
- [x] 设置页展示稳定 Runner 路径与数据目录
- [x] 手动添加非 Steam 游戏 / 手动选择目标程序

## v2.2 - Linux / SteamOS 基础支持

目标：把 Linux 与 SteamOS 纳入 v2 基础能力，而不是作为 v3 Preview。

- [x] Linux profile 路径处理与默认数据目录确认
- [x] Linux Steam 安装目录与 Library 扫描基础实现
- [x] Linux 本地 Steam 封面缓存读取基础实现
- [x] Linux Launch Options 生成
- [x] Linux Runner 启动原生目标程序
- [x] 同组派生进程的 `process_group` 基础等待模式
- [ ] SteamOS 用户目录与只读系统约束梳理
- [ ] Steam Deck 桌面模式配置教程
- [ ] AppImage 或 tar.gz 预览分发

## v2.3 - SteamOS / Proton 兼容性

目标：覆盖 Steam Deck、Proton 与 launcher 链式启动场景。

- [ ] Proton 命令包装策略
- [ ] 尽量保留 Steam 展开的 `%command%` 环境
- [ ] Windows 游戏通过 Proton 启动的自定义 launcher 场景
- [ ] 原版 / 汉化版 / mod loader 多目标切换
- [ ] `process_name` 等待模式
- [ ] Linux / SteamOS 日志路径与错误提示优化
- [ ] Steam Deck 用户教程与故障排查文档

## v2.4 - 一键应用到 Steam 与恢复

目标：用户只在 Manager 里操作，不需要手动打开 Steam 属性。

- [ ] 识别 Steam userdata
- [ ] 支持多 Steam 用户选择
- [ ] 读取当前 LaunchOptions
- [ ] 写入新的 LaunchOptions
- [ ] 修改前备份 Steam 本地配置
- [ ] 一键恢复原启动选项
- [ ] 避免在 Steam 运行时直接写入配置
- [ ] Windows / Linux / SteamOS 分平台应用与恢复策略

## v2.5 - 玩家友好的安装、更新与卸载

目标：让普通游戏玩家可以简单下载、安装、更新和卸载，不需要理解项目结构。

- [ ] Windows setup.exe 发布流程
- [ ] Windows portable zip 发布流程
- [ ] Linux AppImage 或 tar.gz 发布流程
- [ ] GitHub Release 与 CNB Release 双渠道发布
- [ ] CNB 国内下载入口与中文下载说明
- [ ] SHA256 校验和与中文更新说明
- [ ] 新版安装包覆盖安装并保留用户配置
- [ ] Manager 内“检查更新”入口
- [ ] 标准卸载入口：默认保留用户数据，可选清理用户数据
- [x] 首次启动复制 Runner 到稳定数据目录

## v2.6 - Windows 分发与进程等待增强

目标：补齐 Windows 安装体验与复杂 launcher 等待模式。

- [x] Tauri NSIS 安装器配置骨架
- [x] 首次启动复制 Runner 到 `%LOCALAPPDATA%\\SteamWrapper\\bin\\`
- [x] Windows Job Object 基础等待模式
- [ ] Manager 内测试启动
- [ ] 配置导入导出

## v2.x 长期方向

- [ ] 跨平台 Manager 发布矩阵：Windows x64 / Linux x86_64 / SteamOS
- [ ] 面向国内玩家的 CNB 镜像发布与下载说明
- [ ] profiles 可迁移
- [ ] 一键恢复所有已修改游戏
- [ ] 安全说明与反误报说明
- [ ] 中英双语文档
- [ ] 面向 Steam Deck 的简化配置流程
