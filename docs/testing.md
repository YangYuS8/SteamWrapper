# 测试

SteamWrapper v2 按行为、服务、UI 与安装包分层验证。WinUI 预览已有 C#、跨语言与实际 Runner 测试；Dioxus 基线门禁保留。Windows 最终交付仍按 [重设计的阶段门槛](windows-v2-design.md#8-实施顺序与停止条件)验收。

两套 Windows Manager 的同输入配置探针、原生保存补测及资源测量见 [实测比较](windows-manager-comparison.md)。资源复测脚本为 `scripts/windows/Measure-ManagerComparison.ps1`；需先准备两端 release 产物，并在其他构建和测试结束后顺序运行。

## 按改动选择验证

先读取受影响代码和测试，选择能证明本次结果的检查。无需每次编辑前运行整个 workspace，也无需为文档或纯样式调整新增匹配源码字符串的测试。

| 本次改动 | 本地验证范围 |
| --- | --- |
| 文档 / AGENTS / 技能 | 审核 diff、链接、指令冲突和技能元数据；不要求编译 UI 或生成安装包 |
| core / manager-core 行为 | 先写能复现缺失行为的测试并观察预期失败，再修改实现；运行受影响 crate 测试；共享契约或跨 crate 影响时运行 workspace 检查和测试 |
| Runner 启动 / 等待 | 对应平台的真实进程回归测试；CLI / TOML / 公共模块变化再扩展到 workspace |
| Dioxus 交互 / service 接线 | 相关 Rust 测试、`dx check` / 构建，以及覆盖该行为的隔离 Native E2E |
| WinUI / C# 服务 | `mise run winui:test`；配置协议或 Runner 分发变化增加 `winui:contracts`；UI 变化使用 `winui:publish` 与隔离原生交互 |
| 纯视觉调整 | 构建并在隔离 Desktop 预览中检查受影响界面；按影响选择现有测试，不用固定 CSS 字符串代替视觉验收 |
| E2E 工具或依赖 | frozen lockfile 安装、TypeScript 检查、受影响 Native E2E |
| 打包 / 发布 / 工具链或共享构建变化 | 完整质量门禁、当前平台 release Runner staging、实际安装包解包检查 |

CI / release 工作流仍执行各自完整门禁。上表限定日常本地工作量，不删减 CI。已通过的检查只在新改动、失败或未解决疑点出现时重跑；缺少工具时记录阻塞，不把未运行写成通过。

行为回归优先验证外部结果。现有 `ui_contract` 包含源码文本断言，只能证明声明存在，不能证明窗口、可访问性、布局或原生文件选择实际可用。

## WinUI 迁移的新增验收

先验证 C# 配置服务与 Rust Runner 的既有文件协议，再证明 UI 和安装器。已有入口：

```powershell
mise run winui:test
mise run winui:contracts
mise run winui:publish
mise run winui:sandbox
```

`winui:test` 包含配置保真/冲突/替换失败和本地 Steam/稳定 Runner 安装测试。`winui:contracts` 从共享历史 fixture 开始，C# 单字段修改后由 Rust 比较完整 TOML 和 Profile；再用受控父子进程验证 C# 新配置的精确 argv、cwd、job/root 等待差别、退出码和错误日志。详情见 [契约说明](../tests/contracts/README.md)。测试驱动、fixture 及生成的用户目录都不进入发布目录。

新增 Windows CI 保留旧工作流，依次运行上述测试与目录发布；`3d322db` 的 [WinUI CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282718)已实际通过。托管 Windows Server 2025 构建不是 Windows 11 干净系统验收。完整验收范围如下，不能把已实现测试外推到未测平台或真实 Steam；已进行的真实 galgame 对照与尚未解决的 Steam→Runner 失败见 [真实 Steam 验证](real-steam-validation.md)。

| 范围 | 有效证据 |
| --- | --- |
| TOML 兼容 | C# 读取 Rust fixture、只改一个字段、保存后由 Rust 断言未编辑语义；包括省略 wait_mode=root、新建 job、别名键、未知字段/版本和所有现存枚举 |
| 保存安全 | 原子替换失败、备份失败、多写者/外部修改冲突、中断与旧文件保留；不以序列化成功代替无损保存 |
| 配置到运行 | C# 保存的配置驱动真实 Rust Runner fixture，断言 argv、cwd、launcher/child 等待与错误；不能只比较 TOML 文本 |
| WinUI 操作 | 真实原生窗口、原生 picker、取消、中文输入、键盘、缩放及错误恢复；旧 Dioxus DOM/RSX 断言不适用 |
| Windows 发布 | 干净 Windows 11 x64 VM 上自包含安装、稳定 Runner、覆盖更新/占用/降级保护、移动 Manager、卸载后既有启动项仍可用 |
| Steam apply/restore | 脱敏多用户 VDF fixture、Steam 运行保护、备份/复读、冲突和中断恢复、保留其他设置；私有格式需先核验 |
| 最终游玩体验 | 测试者在真实 Steam 人工记录运行状态、退出和时长更新；注明游戏、launcher、系统版本，不能由 fixture 结果替代 |

常规自动化使用隔离 Steam/用户数据。真实 Steam 验收须有用户明确授权；本次用户已授权不损坏游戏文件的 galgame 测试。原启动项、文件完整性与存档保护需单独记录，未解决的云同步冲突不能由测试流程自动选择覆盖。真实用户数据、完整 Steam 配置和本机测试备份不进入提交或 CI 产物。具体配置边界见 [主方案](windows-v2-design.md#4-配置保真是第一个门槛)。

## 当前实现分层

| 层 | 命令 | 验证内容 |
| --- | --- | --- |
| Rust domain / service | `cargo test --workspace` | TOML、VDF、路径、Steam 过滤、封面、Launch Options、Manager service、Runner 等待模式 |
| Dioxus contract | `cargo test -p steamwrapper-manager-dioxus --test ui_contract` | 玩家流程、文件选择、service 和 bundle 的源码声明及品牌一致性；不证明真实原生交互 |
| Dioxus build | `dx check` / `dx build --release` | Dioxus 0.7.10 项目、RSX、静态资源和 release 客户端构建 |
| Dioxus Native E2E | `pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native` | 真实 Dioxus binary、真实 `manager-core`、隔离 Steam / profile / Runner fixture |
| 平台 bundle | `dx bundle --release --package-types …` | NSIS / AppImage 随包 Runner resource 与安装器产物 |

## 本地命令

Windows 环境由 mise 管理，使用 `mise run windows:doctor` 检查、`mise run windows:verify` 执行现有质量门禁。安装与 WinUI 编译验证见 [Windows 开发环境](windows-development.md)。以下 `just`/底层命令保留为现有流程；WinUI smoke 不替代应用或 Steam 验收。

优先使用根目录 `justfile`：

```bash
just dev          # 使用真实 Steam / 用户数据启动 Desktop Manager 与热重载
just dev-sandbox  # 使用一次性 Steam / 用户数据沙箱启动
just test         # Rust 格式、检查与测试
just e2e          # Dioxus Native E2E
just verify       # 全部本地质量门禁
just bundle-linux # stage Runner 并打 Linux AppImage
```

`dev-sandbox` 不会展示真实 Steam 库，也不会保留 profile 或 Runner；它只用于安全预览 UI。`just --list` 列出所有 recipe。下列是对应的底层命令：

```bash
pnpm install --frozen-lockfile
pnpm --filter steamwrapper-manager-dioxus-e2e exec tsc --noEmit
pnpm --filter steamwrapper-manager-dioxus-e2e run test:tooling

cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace

cd apps/manager-dioxus
dx check
dx build --release
cd ../..

cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

Linux 构建、测试和打包前需准备 WebKitGTK、GTK3、`libxdo-dev`、AppIndicator、librsvg 与 `patchelf`。当前 Dioxus Desktop 通过 `muda` 的默认 `libxdo` feature 链接 X11 库；Ubuntu 需要安装开发包 `libxdo-dev`，否则 Manager 测试和 AppImage 构建会在链接阶段报 `unable to find library -lxdo`。CI Check、AppImage 和 release 的 Linux 依赖列表均包含该包。[Ubuntu 包说明](https://packages.ubuntu.com/noble/amd64/libxdo-dev)

无桌面会话的 Linux CI 还需安装 `xvfb`、`xauth` 和 `dbus-daemon`，在虚拟 X 显示与临时 D-Bus 会话中运行 Native E2E；仅编译或打包不需要启动显示服务。GTK 初始化需要可用显示，但历史 CI 的退出码 101 没有保留下来的 stderr，不能据此认定具体 panic 原因。Linux Check 使用下列命令，Windows 保留直接运行 pnpm：[xvfb-run](https://manpages.ubuntu.com/manpages/questing/man1/xvfb-run.1.html)、[dbus-run-session](https://manpages.debian.org/unstable/dbus-daemon/dbus-run-session.1.en.html)。

```bash
xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" dbus-run-session -- pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

平台 bundle 由对应平台运行：

```bash
# Linux
STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
cd apps/manager-dioxus
dx bundle --release --package-types appimage --out-dir ../../release-artifacts

# Windows（GitHub Actions Windows runner）
# stage-runner.sh 会从 target/release/steamwrapper-runner.exe 生成
# resources/runner/SteamWrapperRunner.exe，再运行 dx bundle --package-types nsis
```

## Dioxus Native E2E

Native E2E 只在 `e2e` Cargo feature 下引入 `wdio-dioxus-embedded-driver`。正式 release graph 不含 WebDriver bridge 或测试 server。

```bash
cargo build -p steamwrapper-manager-dioxus --features e2e
pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native
```

测试脚本创建一次性临时 fixture，并将下列环境都指向它：

```text
STEAM_DIR
STEAMWRAPPER_E2E_ROOT
XDG_DATA_HOME
LOCALAPPDATA
```

fixture 包含中文路径与空格路径、一个本地 Steam game manifest，且故意不写本地 cover cache。测试启动真实 Manager 后会断言该 AppID 使用公开 Steam CDN 封面 URL；测试只验证 URL 生成与 DOM 绑定，不依赖外网图片加载。

- 默认游戏库和手动添加入口；
- 首次启动把 bundle Runner 安装到稳定 `SteamWrapper/bin/`；
- 本地 Steam 扫描与游戏配置对话框；
- 保存 profile；
- Launch Options 保持 `--appid "123456" -- %command%` 协议。

成功或失败后的 WDIO 日志与脱敏 fixture artifact 位于 `apps/manager-dioxus/e2e/artifacts/`，该目录不提交；CI 负责上传。测试结束会清理临时目录，不能读取或修改用户真实 Steam 配置。

`scripts/dioxus-service.mjs` 继续使用锁定的 Dioxus service，只补充启动失败时的清理：WDIO 在 `onPrepare` 失败后不会调用 `onComplete`，包装会先完成该钩子以刷新 app stdout/stderr 日志，再保留原错误退出。测试 app 启用 `RUST_BACKTRACE=1`。`test:tooling` 用不启动 GUI 的 Node 子进程验证早退 101 的 stdout/stderr 附件，以及失败后再次运行时日志进入新的输出目录；后者已观察旧服务失败、包装后通过。这些工具回归不代替 Linux GTK/WebKit 的真实 Native E2E。

## Runner 稳定安装验证

`manager-core` 的 Rust 测试覆盖 Runner 路径、摘要相同不覆盖、缺失 / 损坏修复、原子替换失败与不触碰 `profiles.toml` / `logs` / `backups` / `cache` 的边界。Dioxus Native E2E 从空的稳定目录启动，检查真实 Runner 文件被安装并由设置页显示为健康。

Runner 进程测试覆盖 Linux `process_group`、Windows Job Object，以及两平台的 `process_name` 边界。`process_name` 仅按进程名匹配，无法判断并发同名业务归属；它不是默认等待模式。

## CI

`v2-ci.yml` 配置了 Windows / Ubuntu Check 矩阵，执行 Rust 格式、check、test、Dioxus check / release build、Native E2E 和各自平台 Runner 进程测试；其 Linux bundle job 构建 AppImage 并解包检查 Runner。Windows NSIS 构建与内容检查配置在 `release.yml`。工作流声明不代表最近一次运行通过，实际结果须另行核验。

## 限制

- Linux 本机 Native E2E 的通过不能替代 Windows WebView2、NSIS 或 Steam Deck 实机验证。
- 不自动驱动真实 Steam 客户端；一键写入 / 恢复 Launch Options 仍是后续功能。
- Native E2E 覆盖受控本地 fixture，不覆盖真实 Proton、breakaway、Unix daemonize / 新 session 行为。
- Dioxus Browser Mode 不适用于当前直接 Rust service 架构；本项目用 Native E2E 覆盖真实 UI 与 service 边界。

官方依据：Dioxus 0.7.10 Desktop / CLI 文档，`@wdio/dioxus-service` 1.0.0 的 embedded provider 与 bridge setup 文档。

2026-09-07 Windows 本机已完成 Rust workspace、Runner 进程测试、Dioxus check/release build 和 3 个 spec / 6 项 Native E2E 验证。提交 `3d322db` 的 [v2 完整 CI](https://github.com/YangYuS8/SteamWrapper/actions/runs/34081282786)也已通过 Windows、Ubuntu 和 Linux AppImage 全部门禁。安装环境、过程中修正的工具/CI 问题及证据范围见 [开发环境记录](windows-development.md#本机安装与验证记录)。这不替代 NSIS 或真实 Steam 验收；[真实游戏对照](real-steam-validation.md)仍存在 Steam 创建 Runner 失败。
