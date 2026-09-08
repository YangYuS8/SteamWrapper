---
title: "Maintain the documentation"
description: "Develop, translate, check, and deploy the bilingual SteamWrapper documentation site."
---

The `docs/` directory is an independent package in the repository's pnpm workspace, using **Astro 7.3.1 and Starlight 0.42.0**. It builds a static documentation site. Node and pnpm are development/build tools; they are not added to Manager or Runner's runtime requirements. Exact dependencies live in [docs/package.json](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/package.json) and the root lockfile.

## Local setup and preview

Run these commands from the repository root. mise reads the pinned Node and pnpm versions from the project configuration:

```sh
mise install node pnpm
mise exec -c "pnpm install --frozen-lockfile"
mise run docs:dev
```

Open the local URL printed by Astro, using `/SteamWrapper/` for English and `/SteamWrapper/zh-cn/` for Simplified Chinese. The development server reloads content edits. Keep dependencies in the shared lockfile; update version pins and the lockfile together when intentionally changing the site toolchain.

Before submitting a documentation change, run:

```sh
mise run docs:check
mise run docs:build
mise run docs:preview
```

| Command | Purpose |
| --- | --- |
| `docs:dev` | Edit with the local development server. |
| `docs:check` | Check English/Chinese page pairs, required frontmatter, and Astro types. Missing Chinese counterparts are rejected. |
| `docs:build` | Generate static output in `docs/dist/`, then check the generated HTML's internal links, anchors, and local resources. |
| `docs:preview` | Serve the latest production build for review. Build again after changes that need to appear in this preview. |

Review both languages in the production preview, including navigation, long tables, code blocks, and narrow screens. Content checks can detect a missing counterpart; they do not establish that a translation preserves every detail.

## Pages and complete translations

English pages live directly under `docs/src/content/docs/`. Simplified Chinese pages use the same route and filename under `zh-cn/`:

```text
docs/src/content/docs/development/documentation.md
docs/src/content/docs/zh-cn/development/documentation.md
```

Each page needs YAML frontmatter with a nonempty `title` and `description`:

```yaml
---
title: "Page title"
description: "A short description of the page's purpose."
---
```

Start the body with an introduction or a second-level heading. Starlight supplies the page title, language selector, and edit link, so do not repeat a first-level heading, manual language navigation, or an edit link in the body. When adding a page to the navigation, update the corresponding sidebar entry and Chinese label in [astro.config.mjs](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/astro.config.mjs).

Maintain a complete translation at the same time as the English page. Keep commands, field names, literal paths, measurements, and evidence boundaries consistent. Translate explanations rather than shortening them into a summary. Both versions must be reviewable together.

## Links, anchors, and assets

Site UI overrides live in `docs/src/content/i18n/en.json` and `zh-CN.json`. These complete the framework's search messages and heading-link accessibility labels. Keep their keys and interpolation placeholders paired; `docs:check` validates both.

Use absolute paths that include the project base for links within the site:

```md
[Testing](/SteamWrapper/development/testing/)
[测试](/SteamWrapper/zh-cn/development/testing/)
```

Chinese pages should normally link to Chinese destinations. Within the same page, use `#section-anchor`. Preserve explicit anchors when changing headings, especially in dated records. Links to repository source, community files, or scripts use `https://github.com/YangYuS8/SteamWrapper/blob/v2/` followed by the repository-relative path; keep any required fragment. Starlight manages the page's edit destination separately.

Keep [legacy-routes.json](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/legacy-routes.json) aligned with the destinations of old Markdown links. It maps legacy documentation filenames to site routes without the `/SteamWrapper/` base. Retain the anchors those old links use. Put site assets in the appropriate site asset location and let `docs:build` verify their generated URLs. Generated `docs/dist/` output is not source content to commit.

## Search

Starlight uses Pagefind to generate a local search index during the production build. Search works in `docs:preview` after `docs:build`, and in the deployed static site; it is not available as a working index in `docs:dev`. Rebuild before checking search after content edits. No external search account, API key, or hosted search service is required.

## Current guides and historical evidence

User guides describe the current supported flow. Project decisions and validation records retain their original dates, commands, failures, measurements, and limits. Add later evidence with its own scope instead of replacing an earlier observation with a broader success claim. A package inspection, native UI check, and real Steam acceptance are different results.

Preserve complete historical content and useful anchors when reorganizing it. Local records under ignored `target/` paths may be cited as local evidence, but they are not included in a checkout or uploaded as site assets. The [validation records](/SteamWrapper/project/validation/steam/) illustrate how to separate dates and per-game conclusions.

## GitHub Pages deployment

The production URL is `https://yangyus8.top/SteamWrapper/`: project Pages inherits the account's existing custom domain. [site.config.mjs](https://github.com/YangYuS8/SteamWrapper/blob/v2/docs/site.config.mjs) is the shared source for the origin and base used by Astro, redirect generation and output validation. Keep repository documentation links aligned when changing that address. HTTPS is enforced for this project.

The documentation workflow is [`.github/workflows/docs-pages.yml`](https://github.com/YangYuS8/SteamWrapper/blob/v2/.github/workflows/docs-pages.yml). A push to `v2` that matches its documentation-related path filters runs checks, builds the static site, and deploys it. Pull requests run checks/builds without deploying. Read the workflow for the exact trigger paths and deployment conditions when changing build inputs.

A repository maintainer must set **Settings → Pages → Source** to **GitHub Actions** and allow `v2` in the `github-pages` environment's deployment rules. The default branch remains `main`; documentation deployment does not require changing it. These repository settings and a successful deployment are separate from a passing local build. See [GitHub's custom Pages workflow guidance](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

GitHub exposes manual `workflow_dispatch` execution only when that workflow is present on the default branch. While `docs-pages.yml` exists only on `v2`, use an eligible push or re-run an existing workflow run; do not rely on a Run workflow button. See [GitHub's manual workflow requirements](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

After deployment, check the workflow's reported Pages URL, both language roots, navigation, assets, and search. Report the actual deployment result; adding the workflow or documenting these steps does not establish that the site is already online.
