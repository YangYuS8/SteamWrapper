# Windows 开发环境（mise）

使用仓库根的 `mise.toml` 管理项目工具，`global.json` 固定 .NET SDK 选择，`.vsconfig` 声明 MSVC/Windows SDK 组件。WinUI Manager 位于 `apps/manager-winui`；现有 Dioxus 工具链保留供迁移基线验证。独立模板 smoke 继续保留在忽略的 `target/toolchain-smoke/` 下用于环境诊断。

## 版本与管理范围

| 工具 | 固定版本 | 管理方式 |
| --- | --- | --- |
| .NET SDK | 10.0.400 | mise core；global.json 禁止 SDK roll-forward |
| Rust | 1.98.1，rustfmt/clippy | mise 调用现有 rustup，Windows 使用 MSVC host |
| PowerShell | 7.6.5 | mise；任务不依赖 Codex 私有运行时路径 |
| Node / pnpm | 24.18.0 / 11.10.0 | mise；与现有 CI / packageManager 保持一致，仅用于当前 Dioxus 工具 |
| Dioxus CLI / just | 0.7.10 / 1.58.0 | mise；Dioxus 官方 GitHub 二进制 |
| WinUI CLI 模板 | 0.0.6-alpha | `windows:templates` 安装官方 NuGet 模板；这是模板的预览版本 |
| WinUI smoke 依赖 | Windows App SDK 2.4.0、SDK.BuildTools 10.0.26100.7705、WinApp 0.3.1 | 验证脚本固定直接包引用，独立于机器级 Windows SDK |
| WinUI Manager 组件 | WindowsAppSDK.WinUI 2.3.6、InteractiveExperiences 2.1.6、SDK.BuildTools 10.0.26100.7705 | 对应 Windows App SDK 2.4.0 组件集；NuGet 锁定全部传递依赖 |
| MSVC / Windows SDK | VC.Tools.x86.x64 / Windows11SDK.26100 | `windows:setup` 调用 Microsoft 官方安装器；属于系统组件 |

`mise.lock` 记录 Windows x64 可提供的下载地址/摘要；core .NET/Rust 仍委托官方安装脚本/rustup，锁文件不代表它们的完整离线镜像。MSVC bootstrapper 固定为核验过的 18.9.1 URL/SHA-256，实际组件按 Microsoft 通道解析，并非所有组件都可由 mise 隔离或逐字节锁定。

.NET core backend 使用共享 SDK 根目录，单独固定 mise 版本不能替代 .NET 的 SDK resolver，因此同时提供一致的 `global.json`。[mise .NET 管理](https://mise.jdx.dev/lang/dotnet.html)、[Rust 管理](https://mise.jdx.dev/lang/rust.html)

## 首次准备

在仓库根目录的 Windows 终端执行：

```powershell
mise trust
mise install
mise run windows:setup
mise run windows:templates
mise run windows:doctor
mise run windows:winui-smoke
```

`mise trust` 只信任已审阅的当前仓库配置；`mise install` 安装项目声明的工具。系统组件安装任务会验证 bootstrapper 的 SHA-256 和 Microsoft 签名，按 `.vsconfig` 安装编译器/SDK及其必需依赖；已有完整组件时直接返回。无需安装完整 Visual Studio IDE。[Microsoft MSVC 组件安装](https://learn.microsoft.com/en-us/cpp/overview/acquire-msvc?view=msvc-170)

Microsoft 安装需要正常 UAC 权限。脚本使用 `--norestart`，不会自动重启；若退出码为 3010，会明确报告安装完成但需要重启，不能当成未安装，也不能宣称重启已完成。[官方安装参数](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=visualstudio)

`windows:doctor` 用 vswhere 查找所需组件，再加载官方 Developer PowerShell；不会永久改写系统 PATH，也不会输出全量环境变量。`pwsh` 由 mise 提供，不依赖 Windows PowerShell 5.1 或 Codex 的 PATH 注入。[Developer PowerShell](https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=visualstudio)

## 日常命令

WinUI 实现入口：

```powershell
mise run winui:test       # 配置安全、本地 Steam、Runner 安装服务回归
mise run winui:contracts  # C# / Rust 往返、真实 Runner 受控父子进程验证
mise run winui:build      # Release XAML 编译，stage 当前 Rust Runner
mise run winui:publish    # target/winui/publish 自包含目录，含原生资源索引
mise run winui:sandbox    # 发布并打开一次性 Steam/用户目录中的原生预览
```

NuGet 依赖由各项目 `packages.lock.json` 固定，日常命令使用 locked restore。服务项目显式列出 win-x64 runtime identifier，避免测试与 UI 发布轮换时造成锁文件漂移。更新依赖时才使用 `--force-evaluate` 并审查锁文件差异。

Manager 已从 Windows App SDK 2.4.0 总包改为上述组件包，保留原组件版本与摘要；InteractiveExperiences 显式固定 2.1.6，避免依赖回落到 2.1.3。AI、ML、Search、Widgets、DWrite 及其未使用发布文件不再进入新产物；独立环境 smoke 仍使用总包，不随此次精简改变。

Manager 使用 Windows App SDK 的 [原生 picker API](https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers)。项目直接维护，不依赖 alpha 模板安装；`EnableMsixTooling` 用于生成应用 PRI 资源索引，`WindowsPackageType=None` 并关闭包生成/签名，因此不会注册 MSIX 调试身份。发布检查包含 Manager PRI、.NET、WinUI 和 Runner；只有编译成功不足以证明 XAML 能在启动时加载。

`winui:publish` 先写入 `target/winui/publish-staging-<id>` 的全新目录，验证 Manager 程序/程序集、PRI、.NET、WinUI、picker 投影、Runner 与清单，再替换 `target/winui/publish`。目录操作限于本仓库 `target/winui`，拒绝重解析路径，发布锁串行处理替换；正在运行的该目录预览会阻止替换。校验失败保留旧版，普通替换失败恢复旧目录；恢复或清理受阻时会报告保留位置。目录重命名不构成断电事务，失败候选保留用于排查。

发布回归直接运行真实发布命令，再用隔离目录验证错误恢复，无需额外测试框架：

```powershell
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1
# 只检查目录替换/失败恢复，不重新构建：
mise.exe exec -- pwsh -NoProfile -File scripts/windows/Test-WinUIPublish.ps1 -SkipBuild
```

完整命令包含 5 项检查：旧哨兵文件不残留、缺失资源保留旧版、锁住候选时回滚、成功替换只含新文件、越界路径拒绝。测试文件均在 `target/winui` 中；运行前关闭发布目录中的预览。

沙盒每次在 `target/winui/sandbox/<id>` 创建示例 Steam manifest、LOCALAPPDATA、XDG_DATA_HOME，并设置 STEAMWRAPPER_E2E_ROOT。示例游戏不带真实游戏程序，选择受控测试 exe 即可验证配置。产物普通运行会使用真实用户目录；自动化只使用沙盒入口。不要从发布目录单独拷出 EXE。

旧实现与环境诊断入口：

```powershell
mise run windows:doctor       # 工具版本、link/cl 和 SDK 路径
mise run windows:rust-test    # 当前 Rust workspace 测试
mise run windows:verify       # Rust / Dioxus 构建与隔离 Native E2E，遇错即停
mise run windows:winui-smoke  # 独立 XAML 项目的自包含目录发布验证
```

`windows:verify` 会安装冻结的 pnpm 依赖、stage 随包 Runner，并运行现有质量门禁。它不打 NSIS、不发布版本，也不自动操作真实 Steam。现有 `just` 命令仍可用；Windows 的上述入口直接使用 PowerShell，不执行 Bash 清理脚本。

一次性工具调用可用：

```powershell
mise.exe exec -- dotnet --version
mise.exe exec -- cargo test --locked -p steamwrapper-runner
```

本机 PowerShell 的 `mise` 激活函数会吞掉 `exec` 的裸 `--` 分隔符，因此一次性调用使用 `mise.exe`；`mise run ...` 不受此问题影响。没有为此修改用户 PowerShell 配置。

## WinUI 验证的边界

官方 CLI 模板能够通过 .NET 创建 WinUI/XAML 项目。0.0.6-alpha 的创建后操作会无条件更新三个 NuGet 包，`UseLatestWindowsAppSDK=false` 未约束这些操作；脚本在生成后用 XML 固定实际包引用和最低系统版本，再发布。不能只凭模板参数宣称版本已经固定。[WinUI 官方快速入门](https://learn.microsoft.com/en-us/windows/apps/get-started/start-here)

smoke 使用 `net10.0-windows10.0.26100.0`、x64、unpackaged、.NET/Windows App SDK self-contained，暂不启用 trimming。它验证 XAML 编译与发布目录，不安装/启动 MSIX、不启用 Developer Mode、不启动游戏，也不证明干净系统运行或原生交互已经验收。实际 Manager 已建立独立项目、包锁定、服务和跨语言测试。

## 本机安装与验证记录

2026-09-07：上述 mise 工具已安装。Build Tools 注册版本为 `18.9.12112.369`，检测到 MSVC `14.51.36231` 和 Windows SDK `10.0.26100.0`。安装器返回过 3010；用户随后完成重启。本轮复检 .NET、MSVC、SDK 与项目工具可用。

本机完成的验证：

| 验证 | 结果 |
| --- | --- |
| `mise install`、组件安装任务重复执行、`windows:doctor` | 通过；已安装项不会重复覆盖，当前开发 shell 可用 |
| WinUI 固定依赖后的自包含发布 | 通过；目录包含非空 EXE、`coreclr.dll` 和 `Microsoft.UI.Xaml.dll`；未启用裁剪 |
| Manager 组件精简后的 fresh publish | 通过；171.196 MiB / 179,511,987 字节 / 457 文件，旧 AI/ML 等依赖无残留，Runner 清单摘要匹配 |
| `Test-WinUIPublish.ps1` | 5 项通过；先复现旧发布保留哨兵的失败，再验证新发布与错误恢复 |
| `cargo fmt --all -- --check`、`cargo check --locked --workspace` | 通过 |
| `cargo test --locked --workspace` | 全部通过，包括 Windows Runner 的 6 项测试 |
| 冻结 pnpm 安装、E2E TypeScript 检查 | 通过 |
| `dx check`、`dx build --release`、release Runner staging | 通过；Dioxus 产物在 `target/dx/SteamWrapperManager/release/windows/app` |
| Cargo `e2e` feature 构建、隔离 Native E2E | 通过，3 个 spec / 6 个用例 |
| mise 任务校验、PowerShell AST、JSON/TOML 版本一致性、文档链接和 diff | 通过 |

安装后验证复现并修正了三个现有 Windows 工具/测试问题：Manager service 测试硬编码 Linux wait mode、Native E2E 直接启动 `pnpm.cmd` 的 EINVAL、Runner 路径断言硬编码 `/`。pnpm 也明确禁用了当前 embedded provider 不使用的 Edge/Gecko 下载脚本，保留 esbuild。没有修改产品运行逻辑或降低现有断言要求。

完整验证任务最初遇错停止；最后的路径断言修正后，仅重跑受影响的 TypeScript 和 E2E，其余已通过检查未重复。日志保留在忽略的 `target/windows-verify.log`、`target/windows-runner-test.log`、`target/windows-e2e.log` 和 `target/winui-toolchain-build.log`。

后续实现已通过 C# 配置/服务测试和 `winui:contracts`：C# 单字段编辑由 Rust 全量比较语义，真实 Runner 验证中文路径、精确 argv/cwd、job/root 等待差别、退出码与缺失目标日志。证据位于忽略的 `target/winui-contracts/`；原生预览记录见 [首个切片验收](winui-preview-validation.md)。这些结果不代表新安装器、干净系统运行或真实 Steam 时长已验收。

组件精简与发布保护的证据在 `target/winui-component-study/integrated-publish.json`、`publish-regression-before.log` 和 `publish-regression-after.log`。此次已验证构建、布局与发布恢复；精简后最终产物另行通过沙盒原生窗口、配置读取、picker 打开/取消、保存和稳定 Runner 就绪复核。旧 226.23 MiB 产物的 6 轮启动/内存数据没有作为新产物复测结果，干净 Windows 系统也尚未测试。Windows CI 在上传预览前运行 `Test-WinUIPublish.ps1`，同时完成发布与 5 项发布回归。
