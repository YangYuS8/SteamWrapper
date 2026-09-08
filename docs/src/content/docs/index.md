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
The WinUI 3 Windows Manager is a preview. The retained Dioxus Manager has a separate release workflow. Start with [installation](/SteamWrapper/guides/installation/) to choose the appropriate artifact; a documented feature or historical test does not guarantee every game's compatibility.
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

[Contributions](https://github.com/YangYuS8/SteamWrapper/blob/v2/CONTRIBUTING.md), [bug reports](https://github.com/YangYuS8/SteamWrapper/issues), and [security reports](https://github.com/YangYuS8/SteamWrapper/blob/v2/SECURITY.md) have separate guidance. English is the primary project language; every documentation page has a complete Simplified Chinese counterpart available from the language selector.

## Understand the project

The [roadmap](/SteamWrapper/project/roadmap/) and [Windows design](/SteamWrapper/project/design/windows-v2/) describe direction and remaining work. Technical decisions and dated [WinUI](/SteamWrapper/project/validation/winui/) / [Steam validation records](/SteamWrapper/project/validation/steam/) retain their original evidence and limitations.
