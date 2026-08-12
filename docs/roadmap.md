# SteamWrapper v2 Roadmap

## 路线原则

SteamWrapper v2 是长期支持主线。Windows、Linux、SteamOS / Steam Deck 与 Windows 游戏经 Proton 启动的 launcher 场景均在 v2 范围内；无必须破坏兼容性的理由时不另开 v3。

开发顺序保持渐进：先守住 Profile / Runner 闭环，再扩展 Steam 一键应用、分发与平台兼容性。

## v2.0 - 无感启动基础闭环

- [x] Rust workspace 基础结构
- [x] Manager / Runner 分离
- [x] TOML profile 配置模型
- [x] Runner 支持 `--appid <id> -- %command%` 入口
- [x] Manager 生成 Steam Launch Options
- [x] Manager 保存 profile 到稳定数据目录
- [x] Runner 从稳定数据目录读取 `profiles.toml`
- [x] Runner 启动目标 exe / launcher 的基础错误处理
- [x] root-process 等待基线
- [x] 日志目录与 Runner 错误日志

## v2.1 - Dioxus Manager 与本地 Steam 游戏库

目标：让玩家在 Rust-native Manager 中看到本机 Steam 游戏并完成可靠配置。

- [x] `manager-core`：从 UI 框架抽离路径、Profile、Launch Options、日志和 Runner 服务
- [x] Dioxus Desktop Manager（Dioxus 0.7.10 + RSX + CSS）
- [x] 本地 Steam 安装目录、`libraryfolders.vdf` 与 `appmanifest_<appid>.acf` 扫描
- [x] 本地 Steam cover cache 读取；缓存缺失时按本地 AppID 使用公开 Steam CDN 封面回退，加载失败保留占位
- [x] 过滤 Proton / Steam Linux Runtime / Steamworks Redistributables
- [x] AppID 去重
- [x] 游戏库、已配置游戏、日志、设置与折叠侧边栏
- [x] 手动添加游戏与本地目标程序选择
- [x] Profile 编辑与 Launch Options 生成
- [x] Runner 首次稳定安装与设置页修复
- [x] Dioxus Native E2E：真实 binary、隔离 fixture、扫描 / profile / Runner 验收
- [x] 删除旧 Tauri / React Manager、其 E2E 与旧构建依赖

## v2.2 - Linux / SteamOS 基础支持

- [x] Linux profile 路径与默认数据目录
- [x] Linux Steam Library 扫描与本地 cover cache
- [x] Linux Launch Options
- [x] Linux Runner 启动原生目标程序
- [x] `process_group` 基础等待模式
- [x] Linux AppImage bundle 与随包 Runner 资源本机验证
- [ ] SteamOS 用户目录与只读系统约束梳理
- [ ] Steam Deck 桌面模式配置教程
- [ ] Steam Deck 实机验证

## v2.3 - SteamOS / Proton 兼容性

- [ ] Proton 命令包装策略
- [ ] 保留 Steam 展开的 `%command%` 环境的实机验收
- [ ] Windows 游戏经 Proton 启动的自定义 launcher
- [ ] 原版 / 汉化版 / mod loader 多目标切换
- [x] `process_name` 基础等待模式
- [ ] Linux / SteamOS 日志路径与错误提示优化
- [ ] Steam Deck 用户教程与故障排查

## v2.4 - 一键应用到 Steam 与恢复

- [ ] 识别 Steam userdata 与多用户选择
- [ ] 读取当前 LaunchOptions
- [ ] 写入新的 LaunchOptions
- [ ] 修改前备份 Steam 本地配置
- [ ] 一键恢复原启动选项
- [ ] Steam 运行时阻止盲写
- [ ] Windows / Linux / SteamOS 平台策略

## v2.5 - 玩家友好的安装、更新与卸载

- [x] Dioxus NSIS / AppImage bundle 配置与 CI 验收路径
- [x] release Runner stage 与 bundle resource 验证路径
- [ ] Windows NSIS 实机 / CI 实际产物验证
- [ ] Windows portable zip 发布流程
- [x] Linux AppImage 本机产物验证
- [ ] Linux tar.gz 发布流程
- [ ] GitHub Release 与 CNB Release 双渠道
- [ ] SHA256 与中文更新说明的正式发布验证
- [ ] 覆盖安装与保留用户数据的实机验证
- [ ] Manager 内“检查更新”入口
- [ ] 标准卸载入口与可选清理用户数据

## v2.x 长期方向

- [ ] Windows x64 / Linux x86_64 / SteamOS 发布矩阵稳定化
- [ ] CNB 国内镜像与中文下载说明
- [ ] Profile 导入、导出与迁移
- [ ] 一键恢复所有已修改游戏
- [ ] 安全说明与反误报说明
- [ ] 中英双语文档
- [ ] Steam Deck 简化配置流程
