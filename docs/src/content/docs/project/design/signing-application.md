---
title: "SignPath application dossier"
description: "Archived software facts for the rejected Foundation application and optional future provider setup."
---

This dossier preserves the software part of the [official Foundation application](https://signpath.org/apply.html), submitted on 2026-10-04. **The maintainer reported rejection on 2026-10-05; no reason is recorded or inferred.** No subscription, project certificate or production signing approval was obtained. Authenticode is an optional future improvement; project-key-verified application updates and stable delivery do not require Foundation approval. The [Code signing policy](/SteamWrapper/project/design/code-signing/) records the current trust policy. The material below is retained for reference, not an active onboarding request.

## Software fields

| Application field | Prepared information |
| --- | --- |
| Project name | SteamWrapper |
| Repository | [YangYuS8/SteamWrapper](https://github.com/YangYuS8/SteamWrapper) |
| Homepage | [SteamWrapper documentation](https://yangyus8.top/SteamWrapper/) |
| Tagline | Configure a game once, then launch it normally from Steam. |
| Build system | GitHub Actions, with GitHub-hosted runners and locked .NET/Rust dependencies |
| Download page | The submitted application uses the publicly published and download-verified [v0.2.4-preview.1](https://github.com/YangYuS8/SteamWrapper/releases/tag/v0.2.4-preview.1); later WinUI previews use their own immutable tags |
| License | Apache-2.0 for current source; redistributed dependency/runtime terms are inventoried separately |
| Privacy policy | [Privacy and user trust](/SteamWrapper/project/design/code-signing/#privacy-and-user-trust) |
| Reputation | Small, publicly maintained project with source, issues, bilingual documentation and dated local validation. No independent audit, broad adoption or clean-client approval is claimed. |

Prepared description:

> SteamWrapper is a Windows game-launch configuration tool. Its native WinUI 3/C# Manager lets the player choose an existing Steam AppID and a separate game executable or launcher. Steam invokes an independent, headless Rust Runner using generated Launch Options; Manager is not part of daily game launch. The tool does not inject DLLs, patch Steam or game binaries, bypass DRM, install a hidden service or upload player files. Profiles and local Steam covers work offline. Optional official Steam CDN cover requests are disabled by default and require an explicit preference. A per-user installer manages only Manager, preserves user data and the stable Runner, and supplies uninstallation. Current delivery is a technical preview, with remaining clean-client and native-interaction limits documented.

Keep contact name and email out of committed software materials unless the maintainer deliberately chooses to publish them. The form requires the real contact's first name, last name, email and discovery channel, includes reCAPTCHA, and requires consent to processing personal details. A maintainer must supply these facts and complete those personal steps. Do not invent a company, external endorsements or a Wikipedia entry.

The submitted download page, `v0.2.4-preview.1`, comes from commit `1175d84cb51c3ed24c6af7b84ae7886ec9b78b2a` and successful [hosted release run 37123341068](https://github.com/YangYuS8/SteamWrapper/actions/runs/37123341068). Its public assets were independently downloaded and verified; it remains an unsigned technical preview.

The first current-form public preview comes from commit `c457f16b8ea8167c9ef4b8bd67b38a5030455bce` and successful [hosted release run 37120893907](https://github.com/YangYuS8/SteamWrapper/actions/runs/37120893907). All seven public assets were downloaded independently and verified against the schema-2 contract and GitHub digests/lengths. The downloaded seven own PE products matched `0.2.3`, Setup was correctly unsigned, and five actual NativeAOT recovery-language processes passed on the maintainer's Chinese Windows system. These are public-delivery and scoped local results, not clean-client or signing approval. The unconfigured CNB binary mirror was skipped; GitHub is the verified download channel.

## Technical attachments

The reviewed templates and inventory tooling live in `packaging/windows/signpath/`. `payload-v1.xml` names exactly seven own PE files and enforces `ProductName=SteamWrapper`, the coordinated numeric version and SHA-256 signing. `uninstaller-v1.xml` and `setup-v1.xml` are separate drafts. Their XML validity does not mean that Foundation accepted the chained build policy.

The inventory distinguishes own binaries, upstream binaries, runtime packages, build tools and the Windows Runner dependency closure. Preserve canonical third-party license/notice text in the delivered package. In particular, Microsoft package terms must not be mislabeled as MIT or presumed approved under Foundation's System Libraries exception. Include the inventory and ask the provider to confirm that classification. Do not re-sign upstream DLLs with the project's certificate.

Use the actual GitHub-hosted artifact identity as build-origin evidence. The current official submission action is pinned to commit `f6d04783b4569d051e0c80105fe66e82819d0092` (v3); adoption still requires a real organization, project, approved policies and restricted CI submitter. [Official action](https://github.com/SignPath/github-action-submit-signing-request/tree/f6d04783b4569d051e0c80105fe66e82819d0092), [GitHub origin verification](https://docs.signpath.io/trusted-build-systems/github).

Ask Foundation to review this order: sign the own payload; verify final signatures and rebuild the Runner manifest; generate and sign the same-build Inno uninstaller; embed it in Setup; sign and verify final Setup; then record final hashes. Inno supports externally signed cached uninstallers, while the provider must accept their origin and the multi-stage policy. [Inno SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm), [SignedUninstallerDir](https://jrsoftware.org/ishelp/topic_setup_signeduninstallerdir.htm).

## Technical precedents and limits

The Foundation's [Nagi project page](https://signpath.org/projects/nagi/) identifies an admitted C#/WinUI 3 application. Its released [2.4.0 version](https://github.com/Anthonyy232/Nagi/releases/tag/2.4.0) enables self-contained [.NET publishing](https://github.com/Anthonyy232/Nagi/blob/2.4.0/src/Nagi.WinUI/Properties/PublishProfiles/win-x64.pubxml) and [Windows App SDK deployment](https://github.com/Anthonyy232/Nagi/blob/2.4.0/src/Nagi.WinUI/Nagi.WinUI.csproj), with a production [SignPath release workflow](https://github.com/Anthonyy232/Nagi/blob/2.4.0/.github/workflows/release.yml) and an [MSIX-bundle signing configuration](https://github.com/Anthonyy232/Nagi/blob/2.4.0/.signpath/artifact-configuration.xml).

barcodrod.io provides a closer unpackaged example: its [v2.1 build script](https://github.com/MarkHopper24/barcodrod.io/blob/v2.1/installer/build-msi.ps1) publishes a self-contained WinUI 3/.NET application into an offline MSI. Its [signing configuration](https://github.com/MarkHopper24/barcodrod.io/blob/v2.1/.signpath/artifact-config-msi.xml) targets its own EXE/DLL and the MSI, and the successful [v2.1 release](https://github.com/MarkHopper24/barcodrod.io/releases/tag/v2.1) supplies x64 and ARM64 installers.

These are technical precedents for the proposed stack, not approval of SteamWrapper. They do not establish acceptance of our Microsoft dependency versions or license classifications, the System Libraries exception, or the Inno multi-stage signing chain. Submit those details for this project's own provider review; do not copy another project's identity, policies or certificate pins.

## Optional future provider setup

All human maintainers need GitHub and SignPath MFA. Name actual authors, reviewers and signing approvers; each release needs human approval. The agent and a CI submitter cannot supply that approval. After admission, record the provider's accepted configuration, genuine public certificate DER SHA-256 pins and protected submission identity. A checksum or unsigned preview is not a substitute for signed trust. [Foundation conditions](https://signpath.org/terms.html).

The application was rejected and the provider path is not active. If revisited, Foundation admission, SignPath human-account MFA/roles and acceptance of the artifact chain must be verified independently. Never change an approval status merely because local fixture validation passed. An explicitly required-Authenticode release must still stop if its provider configuration is missing; ordinary project-signed updates do not use this provider route.
