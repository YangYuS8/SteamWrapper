# SteamWrapper v2 Roadmap

## v2.0 - Windows 无感启动闭环

目标：先完成 Windows 用户的核心体验。

- [ ] Rust workspace 基础结构
- [ ] Manager / Runner 分离
- [ ] TOML profile 配置
- [ ] Runner 支持 `--appid <id> -- %command%`
- [ ] Manager 生成 Steam Launch Options
- [ ] Runner 启动目标 exe / launcher
- [ ] Windows root-process 等待
- [ ] 日志目录与错误提示
- [ ] 基础 README 与使用教程

## v2.1 - Windows 一键应用到 Steam

目标：用户只在 Manager 里操作，不需要手动打开 Steam 属性。

- [ ] 扫描 Steam 安装目录
- [ ] 识别 Steam userdata
- [ ] 支持多 Steam 用户选择
- [ ] 扫描 Steam Library 与 appmanifest
- [ ] 读取当前 LaunchOptions
- [ ] 写入新的 LaunchOptions
- [ ] 修改前备份 Steam 本地配置
- [ ] 一键恢复原启动选项
- [ ] 避免在 Steam 运行时直接写入配置

## v2.2 - Windows 兼容性增强

目标：覆盖更多 launcher / 汉化补丁 / mod loader 场景。

- [ ] Windows Job Object 等待模式
- [ ] process_name 等待模式
- [ ] 原版 / 汉化版 / mod loader 多目标切换
- [ ] Manager 内测试启动
- [ ] 查看最近一次启动日志
- [ ] 配置导入导出

## v3.0 - Linux Preview

目标：先支持 Linux 原生游戏和基本 Launch Options 生成。

- [ ] Linux runner
- [ ] Linux profile 路径处理
- [ ] process_group 等待模式
- [ ] Linux Steam Library 扫描
- [ ] Linux Launch Options 生成
- [ ] AppImage 或 tar.gz 发布

## v3.1 - SteamOS / Proton 支持

目标：面向 Steam Deck / SteamOS 逐步适配。

- [ ] SteamOS 用户目录安装方案
- [ ] Steam Deck 桌面模式教程
- [ ] Proton 命令包装策略
- [ ] 尽量保留 Steam 展开的 `%command%` 环境
- [ ] Windows 游戏通过 Proton 启动的自定义 launcher 场景

## 长期方向

- [ ] 跨平台 Manager
- [ ] profiles 可迁移
- [ ] 一键恢复所有已修改游戏
- [ ] 安全说明与反误报说明
- [ ] 中英双语文档
