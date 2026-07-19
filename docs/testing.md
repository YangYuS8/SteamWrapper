# 测试

SteamWrapper v2 将验证分为三层，避免把桌面端测试做成一团粗鄙的、不可维护的线团。

## 分层

- `cargo test --workspace`：核心配置、VDF/TOML、路径、Steam 过滤和 Launch Options 逻辑。
- `pnpm e2e:browser`：`@wdio/tauri-service` 的 Browser Mode。在 Chrome + Vite 中运行真实 React 渲染层，并 mock `invoke()`；不启动 Rust、Tauri 二进制或 WebDriver server。
- `pnpm e2e:native`：Tauri Native Mode。使用 `@wdio/tauri-service` 1.2.0 的 `embedded` provider，驱动真实 Manager、真实 IPC 和 Rust commands。

Browser Mode 适合 UI 边界、表单和命令参数；它不能使用 `browser.tauri.execute()`，也不能证明 Rust backend。Native Mode 才覆盖真实 IPC、隔离文件写入和假 Steam Library 扫描。

## 本地命令

```bash
pnpm install --frozen-lockfile
pnpm e2e:browser
pnpm e2e:native:build
pnpm e2e:native
```

`e2e:native` 自动创建临时 fixture：包含中文路径、带空格的游戏目录、本地封面、跨库重复 AppID、一个正常 manifest，以及 Proton、Steam Linux Runtime、Steamworks Common Redistributables。测试将 `STEAM_DIR`、`LOCALAPPDATA` 和 `XDG_DATA_HOME` 都指向此临时目录，结束后清理；绝不读取或修改真实 Steam 配置。

失败截图、WDIO 日志、测试生成的 `profiles.toml` 以及 fixture 说明会保存在 `apps/manager-e2e/artifacts/`。它们是忽略的本地诊断产物；CI 在失败或成功时上传，便于复核。

## 测试构建隔离

Native E2E build 显式使用：

```bash
pnpm e2e:native:build
# 等价核心参数：tauri build --debug --no-bundle --features e2e --config src-tauri/tauri.e2e.conf.json
```

`e2e` Cargo feature 才会编译和注册 `tauri-plugin-wdio` 与 `tauri-plugin-wdio-webdriver`。其权限同样只在 `tauri.e2e.conf.json` 中加入。正式 `tauri build` 与 `.github/workflows/release.yml` 不传该 feature/config，因此 Release 不包含嵌入式 WebDriver server 或 WDIO execute bridge。

## CI

`v2-ci.yml` 中 Browser job 在 Ubuntu 执行；Windows Native job 先构建带 `e2e` feature 的 debug binary，再通过 embedded provider 运行真实 IPC 测试。两个 job 都先执行 E2E TypeScript 检查，并上传诊断 artifact。

## 限制

- Windows Native Mode 是合并门禁；Linux 本地 Native Mode 需要已安装 WebKitGTK/WebKitWebDriver，具体以对应环境的 E2E 运行结果为准。
- 不自动驱动 Steam 客户端、不测试 NSIS 安装向导，也不覆盖 Runner 的进程级等待链路。
- Browser Mode 是 renderer 测试，不能替代真实 Rust IPC 验证。

官方依据：Tauri v2 WebDriver 指南与 WebdriverIO `@wdio/tauri-service` 1.2.0 的 Browser Mode、Plugin Setup 文档。
