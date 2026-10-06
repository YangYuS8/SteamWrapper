---
title: SteamWrapper documentation
description: Set up Steam game launching, build the Windows Manager, and understand the independent Runner.
template: splash
hero:
  title: Configure once. Launch from Steam.
  image:
    html: '<img src="/SteamWrapper/favicon.svg" width="420" height="420" alt="SteamWrapper copper gear and connecting rod" />'
  tagline: Usage and development documentation for SteamWrapper — a Windows-first Manager and an independent Rust Runner.
  actions:
    - text: Get started
      link: /SteamWrapper/guides/getting-started/
      icon: right-arrow
    - text: Build on Windows
      link: /SteamWrapper/development/windows/
      variant: secondary
---

SteamWrapper connects a Steam library entry to the game executable or launcher you choose. Configure it in Manager, copy the generated Launch Options into Steam, and keep Manager closed during daily play.

:::note[Current delivery]
**v0.2.8 is the latest stable release**, for **Windows 11 24H2 x64**, using the same Windows account as Steam with ordinary permissions. [Download Setup](https://github.com/YangYuS8/SteamWrapper/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe) · [CNB mirror](https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.8/SteamWrapper-v0.2.8-win-x64-setup.exe) · [Portable ZIP and release notes](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.8).

WinUI 3 is the only Manager. The complete downloads include the required runtimes; no development tools are needed. Setup remains Authenticode-unsigned, while optional application updates verify a separate project signature. Read [installation](/SteamWrapper/guides/installation/) for setup and data-preserving uninstall. Compatibility and acceptance remain specific to the recorded game, package and environment.
:::

## Use SteamWrapper

| What you want to do | Read |
| --- | --- |
| Configure your first game | [Getting started](/SteamWrapper/guides/getting-started/) |
| Choose the executable, arguments and runtime folder | [Configure a game](/SteamWrapper/guides/configuration/) |
| Keep Steam running while a launcher starts the game | [Wait modes](/SteamWrapper/guides/wait-modes/) |
| Keep official and translated game copies separate | [Translated games](/SteamWrapper/guides/translated-games/) |
| Diagnose a launch or configuration problem | [Troubleshooting](/SteamWrapper/guides/troubleshooting/) |

## Develop and contribute

Start with the [Windows development environment](/SteamWrapper/development/windows/), then read the [architecture](/SteamWrapper/development/architecture/) and choose relevant [tests](/SteamWrapper/development/testing/). The [documentation guide](/SteamWrapper/development/documentation/) explains how to edit, translate, preview and publish this site.

[Contributions](https://github.com/YangYuS8/SteamWrapper/blob/main/CONTRIBUTING.md), [bug reports](https://github.com/YangYuS8/SteamWrapper/issues), and [security reports](https://github.com/YangYuS8/SteamWrapper/blob/main/SECURITY.md) have separate guidance. English is the primary project language; every documentation page has a complete Simplified Chinese counterpart available from the language selector.

## Understand the project

The [roadmap](/SteamWrapper/project/roadmap/) and [Windows design](/SteamWrapper/project/design/windows-v2/) describe direction and remaining work. Technical decisions and dated [WinUI](/SteamWrapper/project/validation/winui/) / [Steam validation records](/SteamWrapper/project/validation/steam/) retain their original evidence and limitations.
