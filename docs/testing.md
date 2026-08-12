# 测试

SteamWrapper v2 采用分层验证，避免把桌面测试堆成一团粗糙、不可审计的混乱物。

## 分层

| 层 | 命令 | 验证内容 |
| --- | --- | --- |
| Rust domain / service | `cargo test --workspace` | TOML、VDF、路径、Steam 过滤、封面、Launch Options、Manager service、Runner 等待模式 |
| Dioxus contract | `cargo test -p steamwrapper-manager-dioxus --test ui_contract` | 玩家主流程、原生文件选择、canonical 品牌、bundle Runner 声明、启动时 Runner 安装边界 |
| Dioxus build | `dx check` / `dx build --release` | Dioxus 0.7.10 项目、RSX、静态资源和 release 客户端构建 |
| Dioxus Native E2E | `pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native` | 真实 Dioxus binary、真实 `manager-core`、隔离 Steam / profile / Runner fixture |
| 平台 bundle | `dx bundle --release --package-types …` | NSIS / AppImage 随包 Runner resource 与安装器产物 |

## 本地命令

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

Linux 打包前需准备 WebKitGTK、GTK3、AppIndicator、librsvg 与 `patchelf`。平台 bundle 由对应平台运行：

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

## Runner 稳定安装验证

`manager-core` 的 Rust 测试覆盖 Runner 路径、摘要相同不覆盖、缺失 / 损坏修复、原子替换失败与不触碰 `profiles.toml` / `logs` / `backups` / `cache` 的边界。Dioxus Native E2E 从空的稳定目录启动，检查真实 Runner 文件被安装并由设置页显示为健康。

Runner 进程测试覆盖 Linux `process_group`、Windows Job Object，以及两平台的 `process_name` 边界。`process_name` 仅按进程名匹配，无法判断并发同名业务归属；它不是默认等待模式。

## CI

`v2-ci.yml` 在 Windows / Ubuntu Check 矩阵中执行 Rust 格式、check、test、Dioxus check / release build、Native E2E 和各自平台 Runner 进程测试。Linux bundle job 产出 AppImage 并解包验证 Runner resource；Windows job 产出 NSIS 并检查其中的 `SteamWrapperRunner.exe`。

## 限制

- Linux 本机 Native E2E 的通过不能替代 Windows WebView2、NSIS 或 Steam Deck 实机验证。
- 不自动驱动真实 Steam 客户端；一键写入 / 恢复 Launch Options 仍是后续功能。
- Native E2E 覆盖受控本地 fixture，不覆盖真实 Proton、breakaway、Unix daemonize / 新 session 行为。
- Dioxus Browser Mode 不适用于当前直接 Rust service 架构；本项目用 Native E2E 覆盖真实 UI 与 service 边界。

官方依据：Dioxus 0.7.10 Desktop / CLI 文档，`@wdio/dioxus-service` 1.0.0 的 embedded provider 与 bridge setup 文档。
