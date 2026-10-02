# WinUI release notes

English | [简体中文](README.zh-CN.md)

Daily pull requests and `main` run tests, contracts and actual WinUI compilation. They do not publish or upload an application package. `.github/workflows/winui-release.yml` builds the complete Windows x64 application for version tags or an explicit manual preview. GitHub Pages documentation deployment remains independent.

Version-tag runs publish **unsigned WinUI prereleases** after full gates and package verification. A manual **Run workflow** on any selected branch/ref performs the full gates and uploads `SteamWrapper-WinUI-preview-windows-x64`; it never creates a public release. Installer, publisher signing, clean-system/update/uninstall acceptance and the optional updater remain unfinished.

## Prepare a version

1. Choose a new, unused tag in strict `vMAJOR.MINOR.PATCH[-prerelease]` form. Do not use leading numeric zeroes or build metadata, and do not move an existing tag. Historical releases are preserved.
2. Set the same three-number base in `apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj`, `crates/core/Cargo.toml` and `crates/runner/Cargo.toml`. Update the affected workspace package versions in `Cargo.lock` and review that dependency changes are intentional.
3. Copy [TEMPLATE.en.md](TEMPLATE.en.md) and [TEMPLATE.zh-CN.md](TEMPLATE.zh-CN.md) to `<tag>.en.md` and `<tag>.zh-CN.md` in this directory. Replace all template placeholders with complete, matching content. Each file must be nonempty, at most 256 KiB, and contain a Markdown heading with the exact tag followed by whitespace or the end of the line and a nonempty body.
4. Describe changes, supported Windows/platform, known limits, unsigned preview status and installation/update/recovery steps accurately. English is the project default; provide a complete Simplified Chinese counterpart. Never include credentials, user settings, diagnostics, saves or game files.
5. Merge the reviewed version/notes change into `main` and confirm the intended revision passed CI. The tagged commit must be reachable from `main`.
6. Create and push the annotated tag for that exact revision. The push triggers complete Windows/Linux Runner gates, C# tests/contracts, actual WinUI compilation, self-contained publication and all publication/recovery checks before packaging.

The current source versions are `0.2.0`. A future **example** `v0.2.1-preview.1` needs source versions `0.2.1` and both `v0.2.1-preview.1.en.md` / `v0.2.1-preview.1.zh-CN.md`. Neither this example nor the templates create or publish a version.

## Assets and retry

A tag build creates `SteamWrapper-<tag>-win-x64.zip`, `<tag>.en.md`, `<tag>.zh-CN.md`, `release.json` and `SHA256SUMS`. The ZIP contains the entire application layout, verified Runner, root `LICENSE` and both notes under `ReleaseNotes/`. The workflow uploads `SteamWrapper-WinUI-release-assets` as its build artifact, then creates a GitHub draft, verifies attached assets and publishes it as a prerelease without marking it latest stable. A plain `vMAJOR.MINOR.PATCH` tag still produces a prerelease while the WinUI delivery gates remain open.

If a release upload fails, resolve the cause and prefer **Re-run failed jobs**. The publishing jobs then reuse the same immutable `SteamWrapper-WinUI-release-assets` build artifact. **Re-run all jobs** builds and packages again; different bytes for the same version must be rejected rather than overwrite existing assets. Use a new version for changed content, and never move a published tag or overwrite published assets. Every manual dispatch is preview-only, even if a tag is selected.

CNB binary delivery is optional and requires `CNB_RELEASE_TOKEN` with repository-release read/write permissions plus the existing `CNB_GIT_TOKEN` for source/tag synchronization. When configured, the workflow copies the same assets and verifies downloaded SHA-256 values. Without the release token, binary delivery is skipped; ordinary source synchronization remains separate. Check actual upload/download results before advertising a CNB binary release. The independent notes-only CNB publisher is removed.

Full maintainer commands and delivery boundaries: [Distribution](https://yangyus8.top/SteamWrapper/development/distribution/). Player download/extraction instructions: [Installation](https://yangyus8.top/SteamWrapper/guides/installation/).
