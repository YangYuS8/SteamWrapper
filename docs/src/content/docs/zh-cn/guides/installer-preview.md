---
title: "Windows 安装器预览"
description: "构建、试用、修复和卸载未签名的按用户安装器，并明确预览版边界。"
---

## 当前边界

Inno Setup 安装器和 C# 部署组件已实现，面向 **Windows 11 24H2 或更新版本、x64**，目前是**没有 Windows Authenticode 签名的技术预览**。包含完整的自包含 WinUI 文件、两种语言和独立 Runner。普通分支 CI 只测试和编译，不生成安装包；明确的手动运行只构建预览产物。版本标签交付通过明确的第 2 版契约同时打包 Setup 与便携 ZIP，并保留原有便携验证器。Authenticode 是可选能力；[执行队列](/SteamWrapper/zh-cn/project/roadmap/#执行队列2026-10-03)中的稳定交付门槛仍待完成。

这不是已签名或稳定发布。开发机或托管 Windows Server 的隔离进程测试不等于干净 Windows 11 验收。干净客户端、正常防护下的下载、多用户、缩放以及真实 Steam 交付门槛仍在[交付方案](/SteamWrapper/zh-cn/project/design/windows-delivery/)中记录。不要为了运行预览关闭 Windows 防护。

当前源码为 `0.2.5`，已具备 `v0.2.5-preview.1` 双语说明。请从 [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases) 下载实际已发布的 Setup 或便携 ZIP；源码更新不代表公开版本已经存在。只有 CNB 的二进制上传与下载核验成功后，才会将其列为可用镜像。

## 构建预览

安装文档要求的 Windows 开发工具后，在仓库根目录运行：

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Install-WinUIInstallerToolchain.ps1
pwsh -NoProfile -File scripts/windows/New-WinUIInstaller.ps1 -Tag v0.2.5-preview.1
```

最后一条命令根据当前 `0.2.5` 源码生成 `target/winui/installers/v0.2.5-preview.1/SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe` 和检查元数据。标签必须匹配源码的三段版本号，仅用于标识本地产物；命令不会创建 Git 标签或发布 Release。已公开版本不能复用于不同字节。此前产物和真实数字版本升级／回滚结果仍作为有日期的历史证据保留。

仅改变预发布后缀不能形成升级路径：部署清单改变、数字版本不变，安装会拒绝同基础版本的不同内容。新的可安装载荷需使用新的协调三段源码／产品版本；重试已有构建时复用完全相同的不可变文件。见[发布版本规则](/SteamWrapper/zh-cn/development/distribution/#准备并触发发布)。

Inno Setup 7.1.0 x64 仅从官方网站下载，检查固定 SHA-256 和发布者签名后安装到 `target/toolchain`。贡献者也可以用 `-Compiler` 提供版本匹配且验证通过的编译器。mise 别名只是可选便利工具。开发 SDK 和 Inno 是构建工具，不是玩家运行要求。

隔离验收命令：

```powershell
pwsh -NoProfile -File scripts/windows/Test-WinUIHostLanguage.ps1
pwsh -NoProfile -File scripts/windows/Test-WinUIInstallerScripts.ps1
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1
```

Host 语言命令在新建的 `target/winui/host-language-acceptance/<id>` 夹具中运行五个真实最终 NativeAOT 维护进程，不提供 CLI 语言覆盖。验证偏好缺失或没有语言字段时跟随实际 Windows 界面语言、显式英语／中文选择及损坏设置回退，保留夹具字节和发布的 Host，不读取真实用户偏好。2026-10-03 本机 `zh-CN` Windows 上五项通过；这不证明所有系统语言或干净客户端验收通过。

后者在仓库 `target` 下新建目录，使用独立测试 AppId 和真实安装、兼容 maintenance 回滚及卸载进程，快捷方式重定向到一次性夹具目录。默认人工构造的下一版本文件只验证部署事务，不代表真实下一版本构建或签名证据。测试不使用真实游戏库；脚本会报告包含日志和 `evidence.json` 的隔离目录，其路径包含中文、空格和单引号，用于验证路径处理。

真实数字版本升级验收应在替换发布目录前冻结完整的旧便携目录，拒绝重解析／私有输入，并记录源文件与副本的哈希。正常编译新的协调源码／产品版本；仅修改旧 Runner 清单或 PE 元数据不构成新版本二进制。下面的历史 `0.2.3` → `0.2.4` 示例需要对应的冻结发布目录；将 `REPLACE_WITH_ID` 替换为证据中记录的基线目录名，新验收应选用实际协调版本：

```powershell
$baseline = 'target/winui/upgrade-baselines/REPLACE_WITH_ID/v0.2.3'
pwsh -NoProfile -File scripts/windows/Test-WinUIInstaller.ps1 `
  -PublishDirectory $baseline `
  -UpgradePublishDirectory target/winui/publish `
  -Tag v0.2.3-installertest.1 `
  -UpgradeTag v0.2.4-installertest.1
```

提供升级发布目录时，脚本会在调用编译器或安装器前检查两份完整布局中七个自有 PE 的产品和版本字段。成功证据应包含 `numericUpgradeUsesSyntheticMetadataFixture=false`，以及实际 maintenance 进程执行的兼容回滚，随后由真实新版安装器重新激活。检查记录的标签、版本、自有文件保留与用户数据哈希。命令使用隔离测试根目录，不操作生产安装。本地通过仍不等于干净 Windows、原生向导／Explorer、多用户或全部中断／注册表／快捷方式故障门槛通过。2026-10-03 本地准备期间没有可用的干净 VM。

2026-10-03 已完成的 `0.2.3` 本机运行使用冻结 `0.2.2` 和真正编译的 `0.2.3`，完成 **13 个符合预期的真实进程步骤**。实际 maintenance 回滚到 `0.2.2`，保留 1,066 个自有版本文件及维护程序／卸载器／快捷方式状态，再由 Inno 升级回来。自有文件占用和未知文件存在时按预期拒绝卸载；正常卸载、重新安装及最后卸载均成功，六个独立数据夹具的哈希保持不变。证据记录 `numericUpgradeUsesSyntheticMetadataFixture=false`、`unsigned=true` 和 `cleanVm=false`。更早的 `0.2.1` → `0.2.2` 结果仍在[测试](/SteamWrapper/zh-cn/development/testing/)中单独保留为有日期的证据。

2026-10-03 后续冻结 `0.2.3` → 真正编译 `0.2.4` 的运行也完成 **13 个符合预期的真实进程步骤**。实际 maintenance 回滚 `0.2.4 → 0.2.3` 保留 1,204 个自有版本文件及维护程序／卸载器／快捷方式状态，随后 Inno 再升级。迟到的自有文件锁和未知文件正确阻止卸载；后续正常卸载／重装通过，六个数据夹具哈希保持不变。证据为 `target/winui/installer acceptance 中文 ' f9b299a94e654ab78a528bd1ea227c37/evidence.json`，再次记录真实版本、未签名及 `cleanVm=false`。本机结果不代表干净客户端、版本保留或真实签名门槛完成。

## 安装与日常使用

`0.2.5` 已实现以下安装和卸载选项。服务、原生窗口和安装器的验证结果分别记录在[测试说明](/SteamWrapper/zh-cn/development/testing/)中；此前有日期的安装器运行不能证明这些新选项已经通过。

安装时选择 English 或简体中文。按当前用户安装，通常无需提权。首次安装可以选择本地固定磁盘上的空目录，默认布局为：

```text
%LOCALAPPDATA%\Programs\SteamWrapper\
  SteamWrapper.exe
  installation.json
  versions\<tag>\
  maintenance\SteamWrapper.Deployment.exe
```

开始菜单快捷方式默认勾选，桌面快捷方式默认不勾选；安装完成时也可选择打开 Manager。快捷方式指向稳定的 `SteamWrapper.exe` 启动器，启动器只打开 Manager。Steam 仍调用 `%LOCALAPPDATA%\SteamWrapper\bin\SteamWrapperRunner.exe`，不要把 Manager、部署辅助程序或版本目录路径填入 Steam 启动选项。

升级和修复使用已登记的安装目录。如果要更换位置，请先卸载 Manager 并保留数据，再安装到新的空目录；安装器不会迁移已有安装或数据目录。

安装 Manager 不修改 Steam 启动选项、游戏或稳定 Runner。Manager 原有的 Runner 安装／修复操作仍单独负责 Runner。配置、界面偏好、配置备份、日志和缓存仍在 `%LOCALAPPDATA%\SteamWrapper\`。卸载还原也可能在 Steam 账号文件旁保留恢复备份，详见下文。便携版用户可以直接安装 Manager 并保留已有数据，无需复制游戏。

安装、修复、回退或卸载前，请正常关闭所有 Manager 窗口。部署锁阻止 Manager 运行时替换文件，并在激活期间阻止新的 Manager 启动。占用时显示重试提示，不终止 Manager、Runner 或游戏，也不安排重启后强制替换被占用的启动器。

## 修复与回退

重新运行匹配且验证过的安装包，可以在原有登记位置恢复缺失的稳定 Manager 启动器。也可以关闭 Manager 后运行维护程序。下列命令使用默认目录；自定义安装时请替换成自己选择的程序目录：

```powershell
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --repair --language en
& "$env:LOCALAPPDATA\Programs\SteamWrapper\maintenance\SteamWrapper.Deployment.exe" --rollback --language zh-CN
```

修复会处理支持的中断部署日志，并从已验证版本恢复缺失启动器。遇到未知或被改动的文件会拒绝覆盖；这不是运行时文件损坏的通用修复。回退需要验证完整清单后才能选择保留的兼容上一版本，不回退配置或稳定 Runner。

复制暂存文件中断时，修复将全部不确定字节保留到程序目录下的 `.recovery-<transaction>`，并写入恢复凭据。该目录不会被启动或自动清除，也不妨碍恢复后的有效版本运行；请保留用于排查，人工确认后再删除，卸载也会保留它。完整旧版本目前继续保留，尚未实现自动清理和保留版本磁盘配额。安装现已要求报告的可用空间覆盖完整暂存文件及清单、原子启动器副本、有界状态／事务日志写入，并额外保留 16 MiB。这是开始事务前的空间检查，不会预留空间阻止其他进程写盘。

隔离部署测试在五个安装和两个恢复改名检查点停止真实编译的夹具进程，不执行作用域退出清理；验证持久日志、锁释放、完整版本修复及未知残留字节保留。受控可用空间测试验证新部署日志／版本创建前安全拒绝。这些测试不会填满真实系统盘，也不模拟注册表／快捷方式失败或整机断电。准确证据范围见[测试](/SteamWrapper/zh-cn/development/testing/)。

新增聚焦的 14 项卸载用例在日志／隔离／停用／清理的六个检查点通过，仅让夹具结束自己的进程；原有七项安装／恢复用例另行通过。这不把此前完整的 99 项套件扩展为一次新的完整套件运行。

Manager 初始化完成后才写入绑定本次事务的健康确认。未确认或启动缓慢不会导致强制关闭或无人值守回退，目前提供人工恢复。文件状态日志不能保证注册表、快捷方式和所有断电位置的整个事务原子性。

## 卸载

关闭 Manager 后，从 Windows 已安装应用设置或安装的卸载器卸载。卸载移除清单拥有的 Manager 版本、稳定 Manager 启动器、安装注册和快捷方式。未知或被改动的安装文件会在常规删除前阻止操作，应保留诊断并排查后重试。

移除中断时使用独立卸载日志和隔离的 `.removal-<transaction>` 目录，已停用或部分删除的文件不会被视作可启动版本。报告的占用解除后，重复卸载或使用相同已验证安装包（或更新的基础版本）恢复；未知字节仍保留。这些文件恢复测试不能证明所有 Windows 注册表或快捷方式故障都能恢复。

默认卸载保留独立存放的所有玩家数据。另提供七个相互独立、默认不勾选的选项：

- 移除可识别的 SteamWrapper 启动选项。
- 删除下载的封面和更新缓存。
- 删除 SteamWrapper 日志。
- 重置 Manager 偏好设置。
- 删除游戏配置。
- 删除可识别的配置备份。
- 删除经过验证的稳定 Runner 及匹配元数据。

移除启动选项前需正常退出 Steam，并先备份每个受影响的账号文件。只清空严格匹配本数据目录稳定 Runner 和对应 AppID 的标准生成命令，自定义命令及文件中其他内容保持不变。手动复制命令时没有记录先前参数，因此不能恢复未知的历史值。只有 Steam 已退出，且全部本地账号扫描确认没有残留 Runner 引用，才能删除配置或 Runner；无法识别的引用需人工处理。

还原先将原子替换操作实际替换的文件保存在 Steam 账号文件旁，名称为 `localconfig.vdf.steamwrapper-backup-<guid>`，再校验并复制到 SteamWrapper 数据备份目录，因此兼容 Steam 与 AppData 位于不同磁盘。仅在成功后删除相邻备份；并发编辑或中断会保留它，并阻止删除配置／Runner。请保持 Steam 关闭，同时保留当前文件与备份，检查后再重试，不要直接覆盖当前文件或盲目删除相邻备份。

清理只选择已知文件，保留占用中或无法识别的文件，以及无法验证的 Runner 字节。清理配置备份不会删除 Steam 恢复备份，更新信任状态也始终保留。任何选项都不删除游戏或存档，不跟随文件系统链接，也不递归清空文件夹。“部分文件保留”表示这些文件还需要人工检查。

## 签名与更新

[代码签名政策](/SteamWrapper/zh-cn/project/design/code-signing/)在 Foundation 申请被拒后，将 Windows Authenticode 改为可选改进，不宣称已有 Windows 发布者证书。应用更新使用独立的项目签名密钥，单独的校验和与 PE 产品元数据不等于签名。每次改变可安装载荷都使用新的协调数字版本，并保留第三方许可证／notices 及上游签名。

`0.2.5` 源码已包含手动检查、可选启动检查、验证下载和确认后安装。真实项目密钥已配置，公开更新源是否可用以及下载至安装验收仍取决于成功发布和核验。当前发布契约见[分发说明](/SteamWrapper/zh-cn/development/distribution/)。日常游戏启动继续独立于 Manager 和联网。
