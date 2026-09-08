---
title: "Astra instruction audit record"
description: "Dated Astra instruction research and repository-guidance audit record."
---

<a id="astra-instruction-audit-record"></a>

<a id="astra-指令审计记录"></a>



Date: 2026-09-07. Scope: editable instructions and related direction documents for the current SteamWrapper `v2` branch. No product implementation, model parameters, plugin installation state, or CI changes.

<a id="材料与阅读范围"></a>

## Materials and reading scope

Read the complete Markdown body of OpenAI's [Using GPT-6 Astra](https://developers.openai.com/api/docs/guides/latest-model), covering its introduction, new capabilities, prompting advice, and migration parameters. The relevant topics for this project were autonomous completion, instruction conflicts, communication, parallel delegation, and verification scope. SteamWrapper is not an OpenAI API application; no API or model dependency was needed.

Read Eric Provencher's complete [Rethinking skills and prompts for GPT-6 Astra](https://x.com/pvncher/status/2095991462416490862): 27 text blocks and two inline comparison images. Direct X access returned 403. The body was obtained through [public FxTwitter JSON](https://api.fxtwitter.com/status/2095991462416490862), cross-checking the author, title, article ID, opening, and 2026-09-04 publication date against [official X syndication](https://cdn.syndication.twimg.com/tweet-result?id=2095991462416490862&lang=en&token=0). Images were read directly from X image resources. A Chinese expansion or repost summary did not replace the original.

Principles adopted in this audit: skill descriptions should match actual tasks, detailed references should be read as needed, persistent instructions should retain stable constraints, testing should be proportional to the change, and the completion boundary of authorized work should be explicit. Generic prompts were not copied wholesale into the project.

<a id="实际指令来源"></a>

## Actual instruction sources

| Source | Verified in this audit | Treatment |
| --- | --- | --- |
| Root `AGENTS.md` | Its content was supplied in the session and matched the disk file; no project override or nested AGENTS | Reduced to product contracts, collaboration boundaries, layers, and task routing |
| `skills/dioxus-manager/SKILL.md` | Present in repository `skills/`, not in the session's automatically discovered skill list; read completely | Reduced to the existing Dioxus workflow and explicitly routed by root AGENTS for relevant tasks |
| `C:\Users\admin\.codex\AGENTS.md` | Empty file; no global override found | Left empty rather than adding existing generic rules again |
| `C:\Users\admin\.codex\config.toml` | Model was `gpt-6-astra`; no additional instructions file or project fallback configuration found | Preserved model/reasoning settings; API guidance does not directly dictate desktop-app settings |
| System skills used in this audit | Read `openai-docs`, its model-migration reference, and `skill-creator` | Used current official workflows without editing system skills or plugin caches |
| Session/app instructions and skill catalog | Affect the session but are not repository-editable files; visible descriptions do not mean every skill body is loaded | Did not claim these sources were rewritten or bulk-edit unrelated plugins |

No user `.agents/skills`, repository `.agents/skills`, or separate rules directory was found locally. Official guidance distinguishes startup AGENTS discovery from on-demand skill loading. The repository's existing `skills/` path is explicitly routed through AGENTS; it was not claimed to be registered with the skill selector, and no duplicate was created. [AGENTS discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [skill discovery and loading](https://learn.chatgpt.com/docs/build-skills)

<a id="具体修正"></a>

## Specific corrections

| Previous issue | Correction |
| --- | --- |
| Workspace tests were required before every change, while the skill repeated the complete build/E2E/bundle chain | Root instructions define verification principles; `docs/testing.md` supplies change-specific scope. Full CI/release gates remain |
| The skill required reading several documents in a fixed order and repeated root rules | Retained necessary UI/E2E/packaging facts and read references only for relevant tasks |
| Any Manager-facing service/CI work could trigger the Dioxus skill | Limited it to Dioxus UI, Native E2E, and Dioxus bundles; excluded WinUI research and Runner lifecycle work |
| `AGENTS.md` prohibited online covers, while source/tests/docs already had a Steam CDN fallback | Described the actual limited AppID fallback, no-upload/no-third-party-expansion boundaries, and offline placeholders; network behavior was not changed |
| All-Rust / Dioxus-only / Linux-LTS-first directions conflicted with the new Windows goal | Distinguished current implementation from the WinUI target, deferred Linux/SteamOS expansion, and retained old code/contracts |
| Skill top-level `version`, `author`, `platforms`, and similar fields were unsupported by the validator | Moved them into `metadata`, retaining existing information without claiming every platform was verified |
| Documentation presented CI declarations or source-string assertions as platform acceptance | Clarified evidence limits, corrected the workflow containing NSIS checks, and listed native WinUI verification needs |

<a id="验证与限制"></a>

## Verification and limitations

The original instructions' `cargo test --workspace` was attempted. Dependency compilation failed because MSVC `link.exe` was missing, before tests executed. This environment blocker was not hidden by changing tests or weakening CI gates.

Validation results: `git diff --check` passed; 36 local links/anchors across 11 changed Markdown files passed; `quick_validate.py` passed with `python -X utf8`. Required PyYAML was installed only in a task-local temporary directory, not added as a product dependency. Windows' default GBK error while reading a UTF-8 skill was resolved using UTF-8 mode for that command, without changing system settings or the validator.

An independent reviewer walked through documentation wording changes and a Dioxus behavioral fix to assess routing/check scope and found no blockers. Its suggestion to clarify that `ui_contract` proves source declarations only was adopted. These checks validate documentation/instructions; they do not quantify Astra task success rates or performance gains.

File edits were saved and the revised text was read in this session. Future sessions will discover repository AGENTS according to loading rules; editing disk files does not remove previously injected text from the current context. The empty global file, app configuration, system skills, and plugin caches were unchanged.

<a id="同日后续重设计"></a>

## Later redesign on the same day

The user further authorized redesign around the original requirements. The initial README, architecture, and roadmap were traced, and `docs/windows-v2-design.md` was added. The design changed to WinUI/C# configuration services and an independent Rust Runner using existing TOML/CLI contracts, withdrawing the initial default FFI recommendation. AGENTS, the Dioxus skill, and related docs were aligned with that boundary while retaining the Astra instruction-simplification principles and adding no generic prompts.

The preceding 11-file/36-link results describe the first audit. After redesign, validation passed for 12 Markdown files, 62 local links/anchors, and skill metadata. Independent original-requirement and architecture reviews found no blockers; suggestions to add CI incrementally from the start and clarify roadmap order were adopted. Runtime code, CI, and the system toolchain were still unchanged, and the earlier blocked test was not represented as passing.
