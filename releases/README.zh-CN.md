# WinUI 发布说明

[English](README.md) | 简体中文

日常拉取请求与 `main` 运行测试、契约和实际 WinUI 编译，不公开发布，也不上传应用包。`.github/workflows/winui-release.yml` 在版本标签或明确的手动预览中构建完整 Windows x64 应用。GitHub Pages 文档部署独立保留。

版本标签运行在构建／测试门禁和包核验通过后公开**同时提供 Setup 与便携 ZIP 的未签名 WinUI 技术预发布**。第 2 版产物结构保留原有便携验证器，不放宽其五产物契约。手动 **Run workflow** 可选择分支／ref，执行完整门禁并上传 `SteamWrapper-WinUI-preview-windows-x64` 和通过测试的未签名 `SteamWrapper-WinUI-installer-preview-windows-x64`，不会创建公开发布。干净客户端／原生交互、更广恢复和旧版本保留验收仍待完成；技术预发布不构成稳定交付，也不代表已经取得发布者证书。

## 准备版本

1. 选择尚未使用的新标签，采用严格的 `vMAJOR.MINOR.PATCH[-prerelease]` 格式。数字部分不要带前导零，不使用 build metadata，也不要移动已有标签。保留历史发布。
2. 将 `apps/manager-winui` 下生产项目 `SteamWrapper.Manager.csproj`、`SteamWrapper.Application.csproj`，`apps/deployment-windows` 下 `SteamWrapper.Deployment.csproj`、`SteamWrapper.Host.csproj`，以及 `crates/core/Cargo.toml`／`crates/runner/Cargo.toml` 设置为同一个三位基础版本。更新 `Cargo.lock` 中两个受影响的 workspace 包版本，审阅依赖改动是否符合预期。新的可安装载荷／清单需使用尚未使用的新数字基础版本，不能仅改预发布后缀；同基础版本的不同内容升级会被拒绝。
3. 将 [TEMPLATE.en.md](TEMPLATE.en.md) 和 [TEMPLATE.zh-CN.md](TEMPLATE.zh-CN.md) 复制为本目录的 `<tag>.en.md` 与 `<tag>.zh-CN.md`。用完整且相互对应的内容替换所有占位。每份文件须非空、不超过 256 KiB，包含带准确标签的 Markdown 标题，标签后为留白或行尾，并有非空正文。
4. 如实说明变更、支持的 Windows／平台、已知限制、未签名预览状态及安装／更新／恢复步骤。英语为项目默认语言，同时提供完整简体中文。不包含凭据、用户设置、诊断、存档或游戏文件。
5. 将经过审阅的版本／说明改动合入 `main`，确认所选提交已通过 CI。标签提交必须在 `main` 的历史中。
6. 对该准确提交创建并推送附注标签。推送后先执行完整 Windows/Linux Runner 门禁、C# 测试／契约、实际 WinUI 编译、自包含发布及全部发布／恢复检查，再进行打包。

当前协调的源码／产品版本为 `0.2.3`，已为未签名技术预览准备两份 `v0.2.3-preview.1` 说明。冻结 `0.2.1` → 真正编译 `0.2.2` 的验收仍保留为有日期的本地证据。说明文件不代表标签或 Release 已经发布。首次新签名载荷必须递增基础版本（本系列采用 `0.2.4`）；签名或时间戳变化后的 Runner 字节不能继续复用未签名的 `0.2.3`。保留已有说明／标签，重试已有产物时复用完全相同的不可变字节。

## 附件与重试

标签构建生成七个附件：`SteamWrapper-<tag>-win-x64-setup.exe`、`SteamWrapper-<tag>-win-x64.zip`、`<tag>.en.md`、`<tag>.zh-CN.md`、`portable-release.json`、`release.json` 和 `SHA256SUMS`。外层 `release.json` 使用第 2 版结构，明确 `signed=false`、`installer=true`、`portable=true`，绑定 Setup／ZIP 的长度与摘要、源码提交和部署清单。`portable-release.json` 保留完整第 1 版便携元数据，继续通过未放宽的旧门禁验证。`SHA256SUMS` 覆盖其余六个附件。

ZIP 包含完整应用布局、经过核验的 Runner、根目录 `LICENSE` 及 `ReleaseNotes/` 中的双语说明。发行打包还必须保留随附第三方的适用 notices／许可证和上游签名。Foundation 审核需确认 Microsoft 系统运行时例外，不能把所有随包依赖笼统描述为 MIT，也不能重新签名上游运行时文件。工作流上传 `SteamWrapper-WinUI-release-assets` 构建产物，再创建 GitHub 草稿，验证附件后公开预发布，不标为最新稳定版。WinUI 交付门槛仍未完成时，普通 `vMAJOR.MINOR.PATCH` 标签也会生成预发布。

发布上传失败时，解决原因后优先使用 **Re-run failed jobs**，发布 job 会复用同一个不可变的 `SteamWrapper-WinUI-release-assets` 构建产物。**Re-run all jobs** 会重新构建和打包；同版本字节不一致时必须拒绝覆盖已有附件。不同内容应使用新版本，不移动已公开标签，也不覆盖已发布附件。所有手动运行都是预览，即使选择标签也不公开发布。

CNB 二进制交付为可选项，需要具有仓库 release 读／写权限的 `CNB_RELEASE_TOKEN`，以及已有的源码／标签同步密钥 `CNB_GIT_TOKEN`。配置后工作流复制同一组附件并验证下载副本的 SHA-256。没有 release token 时跳过二进制交付，常规源码同步独立保留。宣传 CNB 二进制发布前须核对实际上传／下载结果。独立的 CNB 说明发布器已移除。

完整维护者命令和交付边界见[分发说明](https://yangyus8.top/SteamWrapper/zh-cn/development/distribution/)。玩家下载与解压步骤见[安装指南](https://yangyus8.top/SteamWrapper/zh-cn/guides/installation/)。
