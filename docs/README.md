# Documentation source

English | [简体中文](README.zh-CN.md)

Read the published [SteamWrapper documentation](https://yangyus8.top/SteamWrapper/) or its [Simplified Chinese version](https://yangyus8.top/SteamWrapper/zh-cn/).

This directory is the Astro Starlight workspace. Canonical Markdown lives in `src/content/docs/`; the matching `zh-cn/` subtree contains complete translations. `guides/` is for players, `development/` covers implementation and maintenance, and `project/` preserves design decisions and dated evidence. Do not duplicate full guides in the root README.

```sh
mise install node pnpm
mise exec -c "pnpm install --frozen-lockfile"
mise run docs:dev
mise run docs:check
mise run docs:build
mise run docs:preview
```

Run these commands from the repository root. The local URL includes `/SteamWrapper/`. Search is available after build in the production preview. Generated `.astro/` and `dist/` directories are ignored.

See the complete [documentation maintenance guide](src/content/docs/development/documentation.md) for authoring, translation, link conventions, validation and GitHub Pages deployment. [legacy-routes.json](legacy-routes.json) maps old document names to the new routes; builds generate static redirect pages that preserve query strings and section fragments when JavaScript is available. These redirects cannot change GitHub's own `blob/` URLs.
