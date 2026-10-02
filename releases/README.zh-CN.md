# WinUI 发布说明

[English](README.md) | 简体中文

日常拉取请求与 `main` 运行测试、契约和实际 WinUI 编译，不公开发布，也不上传应用包。`.github/workflows/winui-release.yml` 在版本标签或明确的手动预览中构建完整 Windows x64 应用。GitHub Pages 文档部署独立保留。

版本标签运行在完整门禁和包核验通过后公开**未签名 WinUI 预发布**。手动 **Run workflow** 可选择分支／ref，执行完整门禁并上传 `SteamWrapper-WinUI-preview-windows-x64`，不会创建公开发布。安装器、发布者签名、干净系统／更新／卸载验收及可选更新器仍待完成。

## 准备版本

1. 选择尚未使用的新标签，采用严格的 `vMAJOR.MINOR.PATCH[-prerelease]` 格式。数字部分不要带前导零，不使用 build metadata，也不要移动已有标签。保留历史发布。
2. 将 `apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj`、`crates/core/Cargo.toml` 和 `crates/runner/Cargo.toml` 设置为同一个三位基础版本。更新 `Cargo.lock` 中受影响的 workspace 包版本，审阅依赖改动是否符合预期。
3. 将 [TEMPLATE.en.md](TEMPLATE.en.md) 和 [TEMPLATE.zh-CN.md](TEMPLATE.zh-CN.md) 复制为本目录的 `<tag>.en.md` 与 `<tag>.zh-CN.md`。用完整且相互对应的内容替换所有占位。每份文件须非空、不超过 256 KiB，包含带准确标签的 Markdown 标题，标签后为留白或行尾，并有非空正文。
4. 如实说明变更、支持的 Windows／平台、已知限制、未签名预览状态及安装／更新／恢复步骤。英语为项目默认语言，同时提供完整简体中文。不包含凭据、用户设置、诊断、存档或游戏文件。
5. 将经过审阅的版本／说明改动合入 `main`，确认所选提交已通过 CI。标签提交必须在 `main` 的历史中。
6. 对该准确提交创建并推送附注标签。推送后先执行完整 Windows/Linux Runner 门禁、C# 测试／契约、实际 WinUI 编译、自包含发布及全部发布／恢复检查，再进行打包。

当前源码版本为 `0.2.0`。未来的**示例** `v0.2.1-preview.1` 需要将源码版本改为 `0.2.1`，并提供 `v0.2.1-preview.1.en.md` / `v0.2.1-preview.1.zh-CN.md`。示例与模板本身不会创建或发布版本。

## 附件与重试

标签构建生成 `SteamWrapper-<tag>-win-x64.zip`、`<tag>.en.md`、`<tag>.zh-CN.md`、`release.json` 和 `SHA256SUMS`。ZIP 包含完整应用布局、经过核验的 Runner、根目录 `LICENSE` 及 `ReleaseNotes/` 中的双语说明。工作流上传 `SteamWrapper-WinUI-release-assets` 构建产物，再创建 GitHub 草稿，验证附件后公开预发布，不标为最新稳定版。WinUI 交付门槛仍未完成时，普通 `vMAJOR.MINOR.PATCH` 标签也会生成预发布。

发布上传失败时，解决原因后优先使用 **Re-run failed jobs**，发布 job 会复用同一个不可变的 `SteamWrapper-WinUI-release-assets` 构建产物。**Re-run all jobs** 会重新构建和打包；同版本字节不一致时必须拒绝覆盖已有附件。不同内容应使用新版本，不移动已公开标签，也不覆盖已发布附件。所有手动运行都是预览，即使选择标签也不公开发布。

CNB 二进制交付为可选项，需要具有仓库 release 读／写权限的 `CNB_RELEASE_TOKEN`，以及已有的源码／标签同步密钥 `CNB_GIT_TOKEN`。配置后工作流复制同一组附件并验证下载副本的 SHA-256。没有 release token 时跳过二进制交付，常规源码同步独立保留。宣传 CNB 二进制发布前须核对实际上传／下载结果。独立的 CNB 说明发布器已移除。

完整维护者命令和交付边界见[分发说明](https://yangyus8.top/SteamWrapper/zh-cn/development/distribution/)。玩家下载与解压步骤见[安装指南](https://yangyus8.top/SteamWrapper/zh-cn/guides/installation/)。
