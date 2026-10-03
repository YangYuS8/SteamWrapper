---
title: "SignPath application dossier"
description: "Current software facts and the human/provider prerequisites for the Foundation application."
---

This dossier prepares the software part of the [official Foundation application](https://signpath.org/apply.html). **It does not mean that an application was submitted or approved.** The [Code signing policy](/SteamWrapper/project/design/code-signing/) records the current trust and approval status.

## Software fields

| Application field | Prepared information |
| --- | --- |
| Project name | SteamWrapper |
| Repository | [YangYuS8/SteamWrapper](https://github.com/YangYuS8/SteamWrapper) |
| Homepage | [SteamWrapper documentation](https://yangyus8.top/SteamWrapper/) |
| Tagline | Configure a game once, then launch it normally from Steam. |
| Build system | GitHub Actions, with GitHub-hosted runners and locked .NET/Rust dependencies |
| Download page | [GitHub Releases](https://github.com/YangYuS8/SteamWrapper/releases); identify the current WinUI technical-preview tag, not the historical v1 launcher |
| License | Apache-2.0 for current source; redistributed dependency/runtime terms are inventoried separately |
| Privacy policy | [Privacy and user trust](/SteamWrapper/project/design/code-signing/#privacy-and-user-trust) |
| Reputation | Small, publicly maintained project with source, issues, bilingual documentation and dated local validation. No independent audit, broad adoption or clean-client approval is claimed. |

Prepared description:

> SteamWrapper is a Windows game-launch configuration tool. Its native WinUI 3/C# Manager lets the player choose an existing Steam AppID and a separate game executable or launcher. Steam invokes an independent, headless Rust Runner using generated Launch Options; Manager is not part of daily game launch. The tool does not inject DLLs, patch Steam or game binaries, bypass DRM, install a hidden service or upload player files. Profiles and local Steam covers work offline. Optional official Steam CDN cover requests are disabled by default and require an explicit preference. A per-user installer manages only Manager, preserves user data and the stable Runner, and supplies uninstallation. Current delivery is a technical preview, with remaining clean-client and native-interaction limits documented.

Keep contact name and email out of committed software materials unless the maintainer deliberately chooses to publish them. The form requires the real contact's first name, last name, email and discovery channel, includes reCAPTCHA, and requires consent to processing personal details. A maintainer must supply these facts and complete those personal steps. Do not invent a company, external endorsements or a Wikipedia entry.

## Technical attachments

The reviewed templates and inventory tooling live in `packaging/windows/signpath/`. `payload-v1.xml` names exactly seven own PE files and enforces `ProductName=SteamWrapper`, the coordinated numeric version and SHA-256 signing. `uninstaller-v1.xml` and `setup-v1.xml` are separate drafts. Their XML validity does not mean that Foundation accepted the chained build policy.

The inventory distinguishes own binaries, upstream binaries, runtime packages, build tools and the Windows Runner dependency closure. Preserve canonical third-party license/notice text in the delivered package. In particular, Microsoft package terms must not be mislabeled as MIT or presumed approved under Foundation's System Libraries exception. Include the inventory and ask the provider to confirm that classification. Do not re-sign upstream DLLs with the project's certificate.

Use the actual GitHub-hosted artifact identity as build-origin evidence. The current official submission action is pinned to commit `f6d04783b4569d051e0c80105fe66e82819d0092` (v3); adoption still requires a real organization, project, approved policies and restricted CI submitter. [Official action](https://github.com/SignPath/github-action-submit-signing-request/tree/f6d04783b4569d051e0c80105fe66e82819d0092), [GitHub origin verification](https://docs.signpath.io/trusted-build-systems/github).

Ask Foundation to review this order: sign the own payload; verify final signatures and rebuild the Runner manifest; generate and sign the same-build Inno uninstaller; embed it in Setup; sign and verify final Setup; then record final hashes. Inno supports externally signed cached uninstallers, while the provider must accept their origin and the multi-stage policy. [Inno SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm), [SignedUninstallerDir](https://jrsoftware.org/ishelp/topic_setup_signeduninstallerdir.htm).

## Required external setup

All human maintainers need GitHub and SignPath MFA. Name actual authors, reviewers and signing approvers; each release needs human approval. The agent and a CI submitter cannot supply that approval. After admission, record the provider's accepted configuration, genuine public certificate DER SHA-256 pins and protected submission identity. A checksum or unsigned preview is not a substitute for signed trust. [Foundation conditions](https://signpath.org/terms.html).

The current-form public preview, contact/MFA confirmation, CAPTCHA/consent, Foundation admission and the accepted artifact chain remain separate facts to verify. Never change a pending status merely because local fixture validation passed. Missing provider configuration stops a required-signed release rather than publishing an unsigned fallback.
