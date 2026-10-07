---
title: "SteamWrapper v2 架构设计"
description: "WinUI Manager、C# 配置及 Steam 设置服务、独立 Rust Runner 与稳定契约。"
---

<a id="steamwrapper-v2-架构设计"></a>

## 核心目标

**WinUI 3 是唯一的 Manager 实现。**`apps/manager-winui` 中的 Windows Manager 采用 C#/XAML 与 C# 应用服务，Steam 通过既有 TOML/CLI 契约启动独立 Rust Runner。两者之间没有 Rust FFI、管理 helper 或后台服务。详见 [Windows 设计](/SteamWrapper/zh-cn/project/design/windows-v2/)。

玩家配置一次，之后关闭 Manager，从 Steam 点击开始。公开的 [v0.2.9 正式版](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.9)提供 Setup 安装包和便携 ZIP，支持明确向一个本地 Steam 账号应用启动项，以及恢复其已记录的原设置。真实 Steam 客户端、安装器与公开发行证据保留各自范围。Linux 保留 Rust Runner 兼容性与进程 CI；当前没有 Linux GUI，新增 SteamOS/Proton 工作仍延期。

## 运行流程

```text
Steam 开始游戏
→ 稳定 Runner --appid <appid> -- %command%
→ 读取 profiles.toml
→ 启动配置的目标和参数
→ 按配置等待
→ 退出
```

Steam 状态、时长、成就与云行为分别需要限定范围的验收。

```text
打开 WinUI Manager
→ 扫描本地 Steam manifest 与封面
→ 显示自定义／本地图片、可选缓存／CDN 回退或友好占位
→ 选择实际程序/启动器并保留高级设置
→ 保存配置并安装/检查稳定 Runner
→ 选择/确认本地 Steam 账号，查看当前与拟写入的启动项
→ Steam 正常退出后，备份、应用并读回选中设置
→ 保留手动复制作为替代方式
```

**保存并应用到 Steam**先保存配置、准备 Runner，再请求确认一个账号、AppID 及新旧设置。多个账号需要明确选择；没有可读账号时保留手动复制替代方式。Steam 必须正常退出，重试时重新检查设置。已核验的磁盘写入与配置保存分别报告，不等同于 Steam 客户端已保留该值。Manager 可明确打开 Steam，而不启动游戏。

**恢复之前的启动项**使用成功应用时记录的原设置，区分原键缺失与空值。只有选中账号/AppID 当前仍保存记录中的已应用命令时才恢复，保留其他游戏后来产生的变更。手动粘贴的已识别命令若没有恢复记录，其原值仍未知；单独标注的**恢复正常 Steam 启动**只清除该精确命令，不重建旧参数。撤销编辑继续用于未保存输入。移除一个可编辑配置须完整扫描账号与引用，并确认没有阻塞恢复记录，保留无关 TOML、备份和游戏。详见[实施计划](/SteamWrapper/zh-cn/project/design/steam-launch-options/)及[测试](/SteamWrapper/zh-cn/development/testing/)中的限定证据。

## Launch Options 合约

```text
"<stable-runner-path>" --appid "123456" -- %command%
```

`--appid` 选择配置，Steam 原命令保留在 `--` 后。启动项引用稳定 Runner，不引用 Manager 或临时／带版本的包路径。Runner 接收并记录 `steam_command`，但实际执行 profile 的 target/args，不执行或追加原命令。保留 `%command%` 是兼容边界，不代表 Proton 包装已完成。

## 分层

```text
apps/manager-winui/SteamWrapper.Manager       # C#/XAML、界面状态、选择器、剪贴板
                 ↓ C# 调用
apps/manager-winui/SteamWrapper.Application   # 配置、本地 Steam、日志、Runner 安装
                 ↓ profiles.toml / 稳定 Runner 文件
crates/runner                               # Steam 启动的 CLI 和进程生命周期
                 ↓ Rust 调用
crates/core                                 # 共享配置/路径契约

WinUI Manager / 卸载 Host
                 ↓ C# 调用
apps/deployment-windows/SteamWrapper.Deployment # 受保护的 Steam 设置与恢复；部署
```

`ProfileStore` 使用 Tomlyn 语法跨度只修改编辑字段，保留其他文本和未知数据。新 Windows 配置显式使用 `job`；旧配置省略 `wait_mode` 时仍为 `root`。保存及删除一个受支持的显式 Windows 配置表采用协作锁、字节版本冲突检查、同目录刷新后的临时文件、原子替换和备份。删除保留全部无关 TOML，并在配置锁内、替换前再次核对 Steam 引用。内联／点号等不支持的布局保持只读。非协作编辑器仍可能在最终检查与替换之间产生竞态。

`SteamScanner` 读取本地元数据／封面。`CoverService` 管理可选图片请求及有界缓存，WinUI 提供图片解码并异步更新可见行。`RunnerInstaller` 在报告就绪前检查摘要绑定的版本元数据与实际共享文件位置，使用稳定路径和原子替换，保留较新兼容版本，拒绝未知替换。GUI 不启动或等待游戏。跨语言测试和受控进程 fixture 验证实际 Rust 消费，不进入发布目录。

Steam 游戏名由有界、只读解析器读取本地 `appcache/appinfo.vdf`，按当前支持的界面语言显示。元数据缺失、不可读或格式不支持时回退本地基础名称／manifest 名称，不发起联网请求。保存的名称匹配已知 Steam 默认名称时，可本地化其显示；自定义名称及保存的 TOML 不变。语言切换保留所选配置和未保存输入，选择器可按本地名称变体及 AppID 搜索。

`ProfileSteamInstallation` 按 AppID 关联只读 Steam 路径用于显示，不序列化，也不覆盖 `game_dir`。后者是实际运行文件夹，可以位于 Steam 库外。详见[汉化目录分离](/SteamWrapper/zh-cn/guides/translated-games/)。

`SteamAccountScanner` 最多发现 128 个目录名为规范正整数、且已有可读 `config/localconfig.vdf` 的 `userdata` 账号。它只从有界、可选的 `config/loginusers.vdf` 元数据中保留 `PersonaName`，核对公开个人 SteamID64 与账号目录的映射，无法获得显示名时回退数字账号标识。它不按最近登录标记选择用户，不暴露登录字段，不创建设置文件，也不查询账号服务。重解析路径及超出有效隔离 fixture 范围的扫描会被拒绝；账号清单超限时不返回部分选择。`SteamIntegrationReadiness` 在提供自动应用前，将已保存配置版本及经过核验的共享 Runner 字节绑定到一个无歧义的 AppID／本地安装。

Deployment 中的 `SteamLaunchIntegration` 负责选中设置的检查、保留字节的 VDF 编辑、应用与原值恢复。它只修改 `UserLocalConfigStore/Software/Valve/Steam/apps/<appid>/LaunchOptions`，仅在已有且受支持的 `apps` 层级内插入缺失游戏或键。注释、编码／BOM、空白、未知字段和无关字节均保留。结构歧义、不安全路径、只读／锁定目标、确认后变化及不支持的恢复数据都会阻止写入。

恢复记录及已核验快照保存在 `backups/steam-launch-options/<operation-id>/`。记录保留账号／AppID／数据目录身份、原键／值／词法文本、已保存配置及 Runner 摘要，以及操作阶段。重复应用保留首次有效集成的原值；相同的手动粘贴命令不会被赋予虚构的历史来源。检查待处理操作不修改 Steam；同一账号文件中的后续变更在未解决恢复状态前会被阻止。明确恢复使用精确前后快照及实际被替换文件的证据；不一致字节保留为需要审查的冲突。

应用与恢复持有 `profiles.toml.lock`；应用另按数据锁后 Runner 锁的顺序持有 Runner 安装锁，并在替换前再次核对就绪状态。确认对话框及等待正常退出期间不持有变更锁。已打开句柄必须解析到预期的实际文件位置，包括开发宿主重定向 AppData 的情况。已刷新的临时文件与相邻替换备份位于 Steam 所在卷；经过核验的归档副本可存放在另一卷的 LocalAppData。服务核对实际被替换字节和写入目标后才提交记录，替换结果不确定时保留恢复副本。这些检查缩小并发重命名／Steam 启动竞态窗口；普通 `File.Replace` 不提供条件比较并交换，也不保证断电恢复。

### Manager 部署

`apps/deployment-windows` 包含不依赖 GUI 的 C# 部署库和 NativeAOT `SteamWrapper.exe` 启动器／辅助程序。Manager 初始化前取得共享安装锁，保持到进程退出，健康确认绑定当前事务。Inno 和显式修复／回退／卸载共用独占锁及清单／日志引擎。首次安装可选择本地固定磁盘上经过验证的空目录；升级和修复使用已登记的程序位置，稳定数据目录仍独立存放。

辅助程序启动 Manager 或经确认的 SteamWrapper 安装器，不启动游戏。Manager 与明确启用的卸载恢复选项共用 Deployment 的已记录原值恢复规则；没有已知原值的命令继续使用旧版精确命令清除逻辑。卸载持有安装锁，并在恢复、最终引用检查及选定配置／Runner 清理全过程中持续持有数据锁；删除每个受保护文件前再次检查引用。Steam 必须退出，阻塞或未知恢复材料保留，Runner 字节必须匹配受支持元数据。默认卸载保留数据，所有路径都保留游戏、存档、Steam 恢复备份、更新信任状态及未知文件。详见[安装器所有权与恢复](/SteamWrapper/zh-cn/guides/installer-preview/)及[测试](/SteamWrapper/zh-cn/development/testing/)中的限定验收。

`OfficialUpdateService` 使用内嵌公钥验证项目签名的发行元数据，检查有效期和防回退状态，再将受大小限制、通过摘要验证的安装包下载到 SteamWrapper 更新缓存。WinUI 提供手动检查、明确启用的启动检查、进度／取消和安装确认；便携版提供发布页下载入口。现有 NativeAOT 辅助程序等待 Manager 正常退出，复核下载文件后启动同一个 Inno 安装器，成功后重新打开 Manager，不终止游戏，也不替换稳定 Runner。

公开的 `v0.2.9` 在 GitHub 和 CNB 上均有三个经过匿名下载核验的附件。两个来源的稳定／预览更新源均通过真实项目公钥签名、有效期及准确安装包绑定检查，每个通道的两站内容逐字节一致。CNB 发行元数据通过既有已登录 CLI 读取；附件及更新源请求没有使用凭据。GitHub 为主源，已验证的 CNB 可作为备用源；自动检查默认关闭。项目自有 PE 文件和 Setup 仍未使用 Authenticode 签名；Windows 代码签名为可选能力。独立的全新客户端验收通过准确公开 `0.2.8` → `0.2.9` 安装器的 18 步生命周期，与此前 CNB `0.2.5` → `0.2.6` 的真实公开网络更新流程分别记录。各载荷和结果的准确范围见[测试](/SteamWrapper/zh-cn/development/testing/)。

自 `v0.2.8` 起，打包采用内部第 3 版清单：仍校验完整七个包文件，版本发行仅公开 Setup、便携 ZIP 和 `SHA256SUMS`。历史七附件发行保持不可变。独立续期的项目签名更新源仍是必需部分，客户端载荷保留第 2 版格式、既有信任公钥及精确安装器绑定。Release 标题只含标签，已核验 GitHub 正文为英语，CNB 正文为简体中文。

### `crates/core`

Core 是不依赖 GUI 的 Rust 库。Runner 使用其 Profile/TOML 与路径语义。现有 Steam 元数据、封面 URL 和启动项工具不为 WinUI 提供服务：C# 直接实现文件契约。Core 不含平台进程等待 API。

### `crates/runner`

Runner 负责 CLI 解析、目标启动、平台等待和运行日志，不依赖 GUI、WebView 或 .NET。Manager 检查和安装其文件，不参与其进程生命周期。

<a id="cratesmanager-core"></a>
<a id="appsmanager-dioxus"></a>

### 已归档的管理链

Dioxus Manager、`crates/manager-core`、其 E2E 和旧 GUI 发布链已从当前开发中移除。ca6a09e 中的 [UI 源码](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/apps/manager-dioxus)与[服务源码](https://github.com/YangYuS8/SteamWrapper/tree/ca6a09e/crates/manager-core)仅供历史参考。[2026-09-07 比较记录](/SteamWrapper/zh-cn/project/decisions/manager-comparison/)保留测量和限制，不代表第二套受支持的 Manager。

## Profile 示例

```toml
version = 2

[profiles.123456]
name = "Example Game"
app_id = "123456"
platform = "windows"
game_dir = "D:/SteamLibrary/steamapps/common/Example Game"
target = "ExampleGame_CHS.exe"
working_dir = "."
args = []
wait_mode = "job"
```

## 界面语言设置

WinUI 使用与 `profiles.toml` 同级的 `ui-settings.json`。没有 `language` 键时跟随已支持的系统界面文化；`zh-CN`、`zh-SG` 与明确的 `zh-Hans` 文化显示简体中文，其余显示英语。已保存的明确选择优先，无效明确值或无法读取的设置回退英语。规范值为 `en-US` 与 `zh-CN`，兼容去除两端空白、不区分大小写的 `en`、`zh-SG`、`zh-Hans` 别名。读取或仅保存封面偏好不会保存识别出的语言。保存保留未知 JSON 字段，拒绝覆盖不合法的设置。服务诊断仍固定使用英语。

同一文件中的 `steamCdnCovers` 是独立布尔值，缺失时默认 `false`。两种偏好的写入互相保留，并保留未知字段；只有成功持久化的变更才会开启下载。写入失败时保留此前偏好。

侧栏选择器在持久化成功后刷新应用自有文案；失败时保留原语言并报告错误。未保存输入、用户名称、路径、参数、协议标识和日志保持不变。语言不改变 Runner/TOML 行为。

## 等待模式

| 模式 | 用途 |
| --- | --- |
| `root` | 等待直接启动的目标 |
| `job` | 新 Windows 配置默认值；等待未脱离的 Job 成员 |
| `process_name` | 在启动器运行时观察新匹配进程；启动器退出后，继续等待这些匹配进程结束 |
| `process_group` | 保留的 Linux 模式，等待同一 POSIX 进程组的派生进程 |
| `none` | 启动后立即退出 |

旧配置缺少 `wait_mode` 时均解析为 `root`。当前没有创建配置的 Linux Manager。`process_name` 排除启动前已存在的同名 `(PID, start_time)`，但名称不能证明归属。Windows `job` 等待完成后返回启动器状态，不一定是游戏退出码。生命周期结论应由平台进程测试与限定范围的真实证据支持。

## 分发与稳定安装

Windows 提供完整自包含布局、每用户 Inno 安装器及便携 ZIP。版本标签公开发布，手动工作流生成开发预览。日常 CI 只测试和编译，不打包应用。相关路径过滤跳过无关检查，依赖缓存减少重复准备，一次捕获的 Runner 套件提供必需进程证据；版本标签仍须完整门禁通过。CI 冷／热缓存观察见[测试](/SteamWrapper/zh-cn/development/testing/#public-028-and-ci-observations-2026-10-07)，不作为速度保证。正式版支持范围为 Windows 11 24H2 x64，使用与 Steam 相同的 Windows 账户及普通权限。请从普通资源管理器或已安装快捷方式打开 Manager。本地 `v0.2.9` 按账号应用／恢复流程通过限定的第一部真实客户端会话。准确标签交付、公开下载与准确公开安装器的 18 步升级另行通过；这些结果不证明更广游戏／账户／硬件验收。当前下载见[安装指南](/SteamWrapper/zh-cn/guides/installation/)，准确触发方式见[分发说明](/SteamWrapper/zh-cn/development/distribution/)。

```text
%LOCALAPPDATA%\SteamWrapper\
  profiles.toml
  ui-settings.json
  bin\SteamWrapperRunner.exe
  logs\
  backups\
  cache\
```

`%LOCALAPPDATA%\Programs\SteamWrapper` 是 Manager 的默认安装位置；首次安装可以选择本地固定磁盘上另一个经过验证的空目录。Runner 安装保留配置及其他用户数据。

现有 Linux Runner 使用 `$XDG_DATA_HOME/SteamWrapper/`，缺省为 `~/.local/share/SteamWrapper/`，Runner 位于 `bin/steamwrapper-runner`。保留其中已有数据；当前不提供 Linux GUI 或自动安装器。

## 封面与安全边界

WinUI 优先读取各用户的自定义 Steam `config/grid/` 图片，再读取本地 `appcache/librarycache/`，支持带哈希的文件名及嵌套哈希目录；不会写入这些目录。缺失或不可读的图片显示友好占位，不阻塞编辑、保存或 Runner。

官方 Steam CDN 回退是需要明确启用的偏好，默认关闭，仅处理本地已发现 AppID。请求包含单个 AppID 和普通 HTTPS 连接信息，不查询账号、不上传游戏库、不使用 Cookie／身份认证，也不接入第三方元数据服务。仅允许通过 HTTPS 访问 `shared.steamstatic.com` 和 `shared.fastly.steamstatic.com`，每次手工跟随重定向前执行相同检查。固定竖图地址只提供尽力获取：新图片可能需要其他路径，404 时保留占位，不查询其他服务。Valve 文档说明了[库竖图及半尺寸版本](https://partner.steamgames.com/doc/store/assets/libraryassets?l=english)，文件名并不保证解码后一定为 600×900。

`CoverService` 最多同时进行两个下载，每次操作最多十秒，包括响应读取与重定向；最多跟随两次重定向，编码图片数据不超过 4 MiB。图片验证同样限制为两个并发操作。WinUI 使用可用的 Windows codec 解码静态 JPEG、PNG 或 WebP，拒绝损坏内容、单边超过 4096 像素或总计超过八百万像素的图片。请求失败后冷却五分钟，不自动重试。关闭回退会取消当前对话框中进行的请求，并阻止该对话框的新请求。

仅下载的封面由 `%LOCALAPPDATA%\SteamWrapper\cache\covers\` 管理：配额为 32 MiB／64 个文件，三十天过期，并有淘汰与清理入口。缓存变更使用跨进程独占文件锁；缓存被占用时保留占位，或显示可恢复的清理错误。清理不影响自定义图片、Steam 缓存、游戏、配置、Runner 或 SteamWrapper 的其他数据。详见[封面设置](/SteamWrapper/zh-cn/guides/configuration/#cover-settings)及限定范围的[原生验收](/SteamWrapper/zh-cn/development/testing/)。

Steam 设置写入仅限上述经过确认的启动项操作。SteamWrapper 不注入 DLL、不修改 Steam／游戏二进制程序、不绕过 DRM，也不上传用户数据。未解决的存档／云冲突会停止真实验收。

## Manager 技术边界

WinUI/C# Application 与 Rust Runner 是唯一当前产品路径。Dioxus 和 Tauri/React 属于历史实现；Node/pnpm 用于开发资源和静态文档，不是桌面运行时。

验收记录保留准确的产物与环境范围。现有 Steam 用户 SID 下的普通权限证据，不代表全新标准账户的主登录、其他用户桌面、双用户会话或多显示器已经验收。Linux Runner CI 不证明 Linux GUI、Steam Deck 支持或 Proton 集成。详见[测试](/SteamWrapper/zh-cn/development/testing/)和[路线图](/SteamWrapper/zh-cn/project/roadmap/)。
