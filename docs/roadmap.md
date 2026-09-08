# SteamWrapper v2 Roadmap

## 路线原则

按最早 v2 的 Windows 优先原则重新安排：**Windows 可用配置与启动闭环 → 安全一键应用/恢复与 Windows 稳定化 → 再评估跨平台**。新 Manager 采用 WinUI 3/C# 和 C# 配置服务，Rust Runner 独立；TOML、稳定路径和 CLI 不变。

[Windows v2 重设计](windows-v2-design.md)是当前实施方案，[WinUI 评估](winui3-assessment.md)记录技术依据。WinUI 配置预览已实现，Dioxus 保留作为迁移基线。以下阶段是验收顺序，不重新解释已发布版本号；当前证据见 [预览验收](winui-preview-validation.md)。

## A. Windows 工具链与配置契约

- [x] 追溯原始需求、评估 WinUI、明确产品与架构边界
- [x] mise 固定开发工具，安装 MSVC/Windows SDK，完成独立 WinUI 自包含构建验证
- [x] 在 Windows 跑通现有 Rust Runner 的 6 项测试，包括 Job Object 与进程名等待
- [x] C# 读取/单字段编辑/Rust 消费验证：完整字段、缺省、旧别名键、未知数据、中文与路径参数
- [x] 配置原子保存、替换失败保留、备份和编辑冲突验证（非协作编辑器仍有最终检查竞态）
- [x] C# 生成配置交给真实 Runner fixture，验证 argv、cwd 和等待
- [x] 增量加入 Windows 构建与契约 CI，保留现有工作流；远程运行尚未验证

## B. WinUI 完整配置切片

- [x] 建立 WinUI 窗口与独立可测试的 C# 应用服务，不新增 FFI/helper
- [x] 已配置游戏首页、添加游戏、搜索与手动选择 Steam 路径
- [x] 原生选择 target，保留高级参数与工作目录，保存兼容 TOML
- [x] 本地封面或友好占位，无网络封面前置条件
- [x] 安装/修复稳定 Runner，失败时保留配置与原二进制
- [x] 生成并复制精确启动项，明确原值保留和手动恢复引导
- [ ] 原生交互、中文输入、键盘、缩放、取消及错误恢复验收

## C. Windows 可用预览与替换门槛

- [x] 关闭 Manager 后，从真实 Steam 启动/退出并记录状态与时长；本机 Unity 游戏与 9-nine 五部通过，见 [逐游戏证据与限制](real-steam-validation.md)
- [x] 本机第一部 CHS 启动器先退后，实际游戏与 Runner 继续等待至普通退出；中文开场及 Steam 时长通过，仅覆盖这个实际启动器场景
- [ ] 补齐中文/空格路径、启动失败和日志可诊断的玩家验收；保留 job 返回启动器状态的说明与实际后代退出码边界
- [ ] Windows 11 x64 干净 VM 验证自包含目录及每用户安装器，无手动运行时准备
- [ ] 覆盖更新、Manager 移动、Runner 占用和版本冲突不破坏配置/启动项
- [ ] 卸载默认保留仍被启动项引用的 Runner 和用户数据
- [ ] 记录安装体积、启动时间、已验证游戏及已知限制；提供中文使用与恢复说明
- [ ] 达到以上门槛后切换默认 Manager 与发布链；按依赖退役 Dioxus/旧管理链及被替代的工作流

预览可先采用手动复制启动项。生成/复制不能标记为已写入 Steam，fixture 通过不能标记真实 Steam 时长已验证。

## D. Windows 安全一键应用与恢复

- [ ] 核验 Steam 本地配置，识别游戏和多用户，展示原值与将写入值
- [ ] Steam 运行时阻止写入，并在实际写入前复检
- [ ] 备份、无关数据保留、原子写入、复读验证和中断恢复
- [ ] 检测外部更改，恢复时不覆盖用户后来设置或其他游戏数据
- [ ] 扩大真实 Windows launcher 测试，必要时完善显式等待策略
- [ ] 完成稳定版验收后再将一键应用作为默认玩家流程

此阶段优先于 Linux/SteamOS/Proton 扩展。portable、国内镜像与更新入口可按 Windows 交付需要安排；不因发布矩阵扩展阻塞主流程。

## 后续评估

- Windows 10、ARM64、portable ZIP、MSIX、更新渠道和签名方案；必须分别取得产物/平台证据。
- 导入导出、多目标切换和批量恢复；按玩家实际需求决定。
- Linux、SteamOS、Proton；另立需求和支持矩阵，不作为 Windows 首发门槛。

## 现有实现记录与证据边界

当前源码已有 Rust core/manager-core/Runner、Dioxus 0.7.10 UI、本地 Steam 扫描、CDN 封面回退、TOML 保存、稳定 Runner 安装、启动项生成、平台进程代码及 Dioxus Native E2E/打包工作流。它们构成迁移参考，不证明本次 Windows 已通过。

旧路线的 Dioxus、Linux/AppImage 勾选是历史实现记录，可在 `31a609d:docs/roadmap.md` 查阅；不继续混放在新路线作为当前验收。已有 Linux 代码和 CI 保留，新增范围延期。WinUI 配置预览和契约已实现，详见 [环境记录](windows-development.md)；一键应用/恢复与新安装器仍未实现。
