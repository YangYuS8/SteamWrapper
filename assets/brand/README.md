# SteamWrapper icon

**English** | [简体中文](README.zh-CN.md)

The original SteamWrapper mark combines a copper gear inspired by Rust with a
cream connecting rod that recalls Steam, on a deep blue hub. It represents the
Runner connecting a Steam library entry to the player's chosen game executable.
It does not indicate endorsement by the Rust project or Valve.

`steamwrapper.svg` is the editable source. The 512 px PNG and multi-image Windows
ICO are generated from it; the Dioxus copies must match byte for byte. The ICO
contains independently rendered 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px images.
The transparent background works on light and dark surfaces.

With the repository's mise tools and `pnpm install --frozen-lockfile`:

```sh
mise run brand:generate
mise run brand:check
```

For local previews, run `node scripts/generate-brand.mjs --preview`; outputs go to
the ignored `target/brand-preview/` directory. Review small sizes when changing
the source. Rendering uses the pinned development dependency `@resvg/resvg-js`;
the distributed applications have no Node.js dependency.

WinUI embeds the ICO in its executable and loads it for the window icon. Dioxus
uses the same SVG in the interface and the PNG/ICO in its bundles. The documentation
site's generated `docs/public/favicon.svg` mirrors the canonical SVG for its
header and home page. This follows
Microsoft's [icon construction guidance](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction).
