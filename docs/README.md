<a id="文档"></a>

# Documentation

English | [简体中文](README.zh-CN.md)

SteamWrapper's primary documentation is English. Every page in this directory has a complete Simplified Chinese counterpart named `*.zh-CN.md`; use the language link at the top of a page to switch. Commands, configuration keys, paths, and historical measurements retain their original meaning in both languages.

Start with the [project overview](../README.md), then choose the relevant guide below. Current design, implemented behavior, and dated validation are separate: a plan or earlier passing result does not establish that a later build or every platform has passed.

<a id="产品与开发"></a>

## Product and development

| Guide | Purpose |
| --- | --- |
| [Architecture](architecture.md) | Manager, services, independent Runner, file contracts, stable data, and display language settings. |
| [Windows v2 design](windows-v2-design.md) | Windows-first requirements, configuration fidelity, delivery gates, and deferred scope. |
| [Technology stack](tech-stack.md) | Current implementation, tooling, retained Dioxus baseline, and rejected directions. |
| [Windows development](windows-development.md) | mise-managed setup, build/test commands, and shared-data-path checks. |
| [Testing](testing.md) | Choose relevant automated, native, package, and authorized live Steam checks. |
| [Distribution](distribution.md) | Preview packaging, stable Runner installation, update/uninstall boundaries, and release gates. |
| [Roadmap](roadmap.md) | Implementation priorities and work still required before replacing the baseline. |
| [Separate translated games](translated-games.md) | Keep official Steam installs and independent translations separate; understand launch, achievement, save, and cloud limits. |

<a id="研究与带日期的证据"></a>

## Research and dated evidence

These records retain their original dates and measurements. Later results are identified separately; local evidence under ignored `target/` paths is not included in a repository checkout.

| Record | Purpose |
| --- | --- |
| [WinUI 3 assessment](winui3-assessment.md) | Migration alternatives, dependencies, deployment, and initial validation plan. |
| [Windows Manager comparison](windows-manager-comparison.md) | Same-input configuration tests, native checks, and bounded resource measurements. |
| [WinUI preview validation](winui-preview-validation.md) | Initial configuration-slice evidence and subsequent coverage. |
| [Real Steam validation](real-steam-validation.md) | Authorized game-specific observations, historical failures, later retests, and remaining limits. |
| [Astra instruction audit](astra-instruction-audit.md) | The dated instruction-research and repository-guidance changes. |

<a id="社区与自动化"></a>

## Community and automation

Read [contributing](../CONTRIBUTING.md), the [Code of Conduct](../CODE_OF_CONDUCT.md), [security reporting](../SECURITY.md), or [support](../SUPPORT.md) as appropriate. [AGENTS.md](../AGENTS.md) contains repository automation instructions; it is not a user guide.

This implementation is developed on `v2`. GitHub's default branch remains `main`; the community files and templates shown by GitHub can therefore differ from the ones in this branch.
