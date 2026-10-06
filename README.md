# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper icon" width="112" height="112" />
</p>

English | [简体中文](README.zh-CN.md)

**Configure a game once, then launch it normally from Steam.** SteamWrapper connects a Steam library entry to your chosen game executable or launcher. Manager handles configuration; Steam calls the independent, headless Rust Runner during daily play.

[Documentation](https://yangyus8.top/SteamWrapper/) · [Getting started](https://yangyus8.top/SteamWrapper/guides/getting-started/) · [Installation](https://yangyus8.top/SteamWrapper/guides/installation/) · [Issues](https://github.com/YangYuS8/SteamWrapper/issues)

## Current status

Windows is the priority. The **WinUI 3/C# Manager** supports local Steam discovery, native pickers, syntax-preserving configuration, advanced arguments and Launch Options copying. WinUI is the only Manager. **[v0.2.7](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.7) is the first stable Windows release**, with matching [CNB downloads](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/tag/v0.2.7). Use Windows 11 24H2 x64 and the Windows account you normally use with Steam. Download Setup or the complete portable ZIP and follow the [installation guide](https://yangyus8.top/SteamWrapper/guides/installation/).

Manager initially follows the supported system UI language, with English as the fallback and complete Simplified Chinese localization. A saved manual language choice takes priority. Language changes preserve game names, paths, arguments and saved profiles. Keep official Steam installations separate from third-party translations; see [translated games, saves and achievements](https://yangyus8.top/SteamWrapper/guides/translated-games/). Compatibility observations are recorded per game and scenario, not promised for every title.

Covers prefer custom and local Steam images. Optional official Steam CDN fallback is off by default, with a bounded SteamWrapper cache and a clear action; missing artwork never blocks configuration or launch. See [cover settings](https://yangyus8.top/SteamWrapper/guides/configuration/#cover-settings).

Pull requests and `main` run tests and compile checks. Version tags build and publish Setup and the portable ZIP: pure version tags select stable, prerelease suffixes select preview. Manual workflow runs produce trial artifacts without publishing a Release. Windows Authenticode signing is optional; application updates authenticate project-signed metadata and verify the exact installer. The scoped client/native gates and full v0.2.7 release workflow passed; both download sources and update channels were independently verified. See [release preparation](https://yangyus8.top/SteamWrapper/development/distribution/) and the [code signing policy](https://yangyus8.top/SteamWrapper/project/design/code-signing/).

## Documentation

The [Astro Starlight documentation site](https://yangyus8.top/SteamWrapper/) is the primary usage and development reference, with complete [Simplified Chinese](https://yangyus8.top/SteamWrapper/zh-cn/).

| Audience | Start here |
| --- | --- |
| Players | [Getting started](https://yangyus8.top/SteamWrapper/guides/getting-started/), [configuration](https://yangyus8.top/SteamWrapper/guides/configuration/), [troubleshooting](https://yangyus8.top/SteamWrapper/guides/troubleshooting/) |
| Developers | [Windows setup](https://yangyus8.top/SteamWrapper/development/windows/), [architecture](https://yangyus8.top/SteamWrapper/development/architecture/), [testing](https://yangyus8.top/SteamWrapper/development/testing/) |
| Contributors | [Documentation workflow](https://yangyus8.top/SteamWrapper/development/documentation/), [roadmap](https://yangyus8.top/SteamWrapper/project/roadmap/), [contribution guide](CONTRIBUTING.md) |

The editable source is in [docs/](docs/README.md). Historical designs and validation records remain separate from current user instructions.

## Develop locally

Start a focused feature branch from `main` and target pull requests to `main`. Install the tools needed for your change using your preferred method. [mise](mise.toml) is an optional convenience, not a contributor requirement. Follow the Windows setup guide for SDK versions and MSVC/SDK installation. With PowerShell 7, .NET and Rust on PATH, the WinUI development commands are:

```powershell
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Test
pwsh -NoProfile -File scripts/windows/Test-WinUIContracts.ps1
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish
pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox
```

The published directory is `target/winui/publish`; keep it intact. The sandbox uses disposable Steam/user-data fixtures. Use the sandbox for routine previews. See the testing guide for WinUI and platform-specific Runner gates.

To work only on the documentation, use Node 24.18.0 (the verified reference version) and the pnpm version declared in `package.json`, installed by your preferred method, then run:

```sh
pnpm install --frozen-lockfile
pnpm docs:dev
pnpm docs:check
pnpm docs:build
```

Node/pnpm are development and static-site build tools, not desktop application runtime requirements.

## Community and license

Read [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), [Security](SECURITY.md) and [Support](SUPPORT.md). English and Simplified Chinese reports are welcome. Never include credentials, unredacted user data, saves or game binaries in reports. SteamWrapper does not inject DLLs, patch game/Steam binaries, bypass DRM or upload user data.

The default `main` branch contains v2 and uses [Apache-2.0](LICENSE). Historical v1 tags and commits retain their original license. Pull requests target `main`, which also supplies the community templates and GitHub Pages documentation. Future work follows the [delivery roadmap](https://yangyus8.top/SteamWrapper/project/roadmap/).

The [original project icon](assets/brand/README.md) combines a Rust-inspired copper gear and a Steam-inspired connecting rod. SteamWrapper is not affiliated with or endorsed by Valve or the Rust project.
