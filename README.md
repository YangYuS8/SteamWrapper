# SteamWrapper v2

<p align="center">
  <img src="assets/brand/steamwrapper.svg" alt="SteamWrapper icon" width="112" height="112" />
</p>

English | [简体中文](README.zh-CN.md)

**Configure a game once, then launch it normally from Steam.** SteamWrapper connects a Steam library entry to your chosen game executable or launcher. Manager handles configuration; Steam calls the independent, headless Rust Runner during daily play.

[Documentation](https://yangyus8.top/SteamWrapper/) · [Getting started](https://yangyus8.top/SteamWrapper/guides/getting-started/) · [Installation](https://yangyus8.top/SteamWrapper/guides/installation/) · [Issues](https://github.com/YangYuS8/SteamWrapper/issues)

## Current status

Windows is the priority. The **WinUI 3/C# Manager is a working preview** with local Steam discovery, native pickers, syntax-preserving configuration, advanced arguments and Launch Options copying. The retained Dioxus Manager has its own release workflow; the default delivery chain has not switched. Read the installation guide before choosing an artifact. Clean-system acceptance and a WinUI installer remain unfinished.

Both Managers default to English and include complete Simplified Chinese localization. Language changes preserve game names, paths, arguments and saved profiles. Keep official Steam installations separate from third-party translations; see [translated games, saves and achievements](https://yangyus8.top/SteamWrapper/guides/translated-games/). Compatibility observations are recorded per game and scenario, not promised for every title.

## Documentation

The [Astro Starlight documentation site](https://yangyus8.top/SteamWrapper/) is the primary usage and development reference, with complete [Simplified Chinese](https://yangyus8.top/SteamWrapper/zh-cn/).

| Audience | Start here |
| --- | --- |
| Players | [Getting started](https://yangyus8.top/SteamWrapper/guides/getting-started/), [configuration](https://yangyus8.top/SteamWrapper/guides/configuration/), [troubleshooting](https://yangyus8.top/SteamWrapper/guides/troubleshooting/) |
| Developers | [Windows setup](https://yangyus8.top/SteamWrapper/development/windows/), [architecture](https://yangyus8.top/SteamWrapper/development/architecture/), [testing](https://yangyus8.top/SteamWrapper/development/testing/) |
| Contributors | [Documentation workflow](https://yangyus8.top/SteamWrapper/development/documentation/), [roadmap](https://yangyus8.top/SteamWrapper/project/roadmap/), [contribution guide](CONTRIBUTING.md) |

The editable source is in [docs/](docs/README.md). Historical designs and validation records remain separate from current user instructions.

## Develop locally

Work on `v2`. Use the pinned [mise tools](mise.toml) and follow the Windows setup guide for MSVC/SDK installation. The WinUI preview commands are:

```powershell
mise run winui:test
mise run winui:contracts
mise run winui:publish
mise run winui:sandbox
```

The published directory is `target/winui/publish`; keep it intact. The sandbox uses disposable Steam/user-data fixtures. `just dev` uses real local data; use `just dev-sandbox` for routine Dioxus previews. See the testing guide for retained Dioxus and platform-specific gates.

To work only on the documentation:

```sh
mise install node pnpm
mise exec -c "pnpm install --frozen-lockfile"
mise run docs:dev
mise run docs:check
mise run docs:build
```

Node/pnpm are development and static-site build tools, not desktop application runtime requirements.

## Community and license

Read [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), [Security](SECURITY.md) and [Support](SUPPORT.md). English and Simplified Chinese reports are welcome. Never include credentials, unredacted user data, saves or game binaries in reports. SteamWrapper does not inject DLLs, patch game/Steam binaries, bypass DRM or upload user data.

This `v2` branch uses [Apache-2.0](LICENSE). GitHub's default branch remains `main`, whose legacy implementation and license are separate. Target `v2` for this implementation; GitHub's community-template chooser follows the default branch. Documentation deploys from `v2` through GitHub Pages Actions.

The [original project icon](assets/brand/README.md) combines a Rust-inspired copper gear and a Steam-inspired connecting rod. SteamWrapper is not affiliated with or endorsed by Valve or the Rust project.
