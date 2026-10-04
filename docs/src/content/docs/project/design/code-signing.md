---
title: "Code signing policy"
description: "Optional Windows code signing, project-signed application updates, and the retained SignPath preparation tools."
---

## Current status

**The maintainer reported on 2026-10-05 that the SignPath Foundation application was rejected.** It was submitted on 2026-10-04. No rejection reason is recorded here, and no subscription, project certificate or production signing approval has been obtained. Authenticode signing is now an optional distribution improvement, not a prerequisite for stable delivery or application updates. Unsigned releases remain explicitly identified as such.

Application updates use a separate project-controlled key: the release workflow signs the update manifest, and Manager verifies its signature and the installer's exact length and SHA-256 before offering installation. The real public key is embedded and the corresponding GitHub release secret is configured. Publication and end-to-end acceptance remain separate gates; CNB has no published binary mirror or configured release credential yet. This trust does not establish a Windows publisher identity or remove Windows download warnings. See the [delivery plan](/SteamWrapper/project/design/windows-delivery/).

The repository retains Windows signing verification, post-sign Runner manifest generation, MSVC Runner PE resources, artifact configuration drafts, dependency/license inventory tooling and a provider-prerequisite validator for possible future Authenticode signing. They are not a SignPath connection and do not submit files to that provider. The [application dossier](/SteamWrapper/project/design/signing-application/) preserves the submitted software facts. The sections below describe this optional provider route; they do not gate project-signed updates.

## Human responsibility

The proposed human maintainer account is [YangYuS8](https://github.com/YangYuS8), owner of the [GitHub source repository](https://github.com/YangYuS8/SteamWrapper). Confirm and record the real people and their SignPath roles during onboarding:

| Role | Responsibility | Setup status |
| --- | --- | --- |
| Authors | Maintain the reviewed source and build definitions | Human repository maintainer; provider mapping pending |
| Reviewers | Review changes from other contributors, especially workflows and packaging | Human maintainer; additional reviewers may be nominated |
| Signing approvers | Inspect the commit, tests, artifact and signing request before approval | Human maintainer to be confirmed by Foundation |
| CI submitter | Submit only a verified hosted build under the approved policy | Dedicated least-privilege service identity not configured |

An AI coding agent can prepare changes and evidence. It is not a Foundation-approved human reviewer or signing approver. A CI token may submit a request but must not approve it. MFA readiness and actual role assignments are not asserted by this document.

## Source and artifact policy

Only reviewed version tags whose exact commits are reachable from `main` may enter the future production signing path. Ordinary PR/main CI and unsigned manual previews do not receive signing credentials. Bind the source commit, workflow run and uploaded artifact identity; repository-provided JSON alone is not independent provenance evidence.

Sign only project-owned EXE/DLL files built from the reviewed source. Preserve upstream signatures on redistributed runtime files. Every own PE uses `ProductName=SteamWrapper` and one coordinated product version, including localized assemblies, Runner and deployment components. Reject same-version changed Runner bytes rather than weakening the stable Runner's manifest recognition.

The payload/uninstaller and final Setup signing stages must be accepted by the provider. Inno-generated uninstaller provenance is part of that review; do not import a manually signed binary from outside the build. Regenerate `runner-manifest.json` **after** Runner signing, then preserve those bytes through packaging. Sign final Setup only after embedding the verified payload. ZIP contents are signed PE files; ZIP authenticity is established separately by authenticated metadata and its final digest.

Foundation admission is an external review, and release signing requires human approval. [Foundation conditions](https://signpath.org/terms.html), [GitHub origin verification](https://docs.signpath.io/trusted-build-systems/github).

Only if a future application receives actual approval may the project record the verified provider details and use this acknowledgment: “Free code signing provided by SignPath.io, certificate by SignPath Foundation.” It is not a current project acknowledgment.

## Verification available now

`scripts/windows/WindowsSigning.ps1` exposes:

| Function | Behavior |
| --- | --- |
| `Get-WindowsSigningEvidence` | Inspect embedded Windows trust, SHA-256 digest, signer, RFC3161 timestamp and PE product metadata without running the file |
| `Assert-WindowsSigning` | Require trusted Windows verification, trusted RFC3161 timestamp, SHA-256, exact SteamWrapper product version, Foundation signer name and an explicit certificate DER SHA-256 allowlist |
| `Update-RunnerSigningManifest` | Verify the final staged Runner, keep its bytes read-locked, then atomically rebuild its adjacent sidecar; preserve the previous manifest on failure |

Verification defaults to Windows cached trust using `WTD_CACHE_ONLY_URL_RETRIEVAL`; it does not fetch missing chains or revocation evidence. Missing evidence fails closed. `-OnlineRevocation` is an explicit maintenance option, separate from ordinary offline application use, and uses Windows certificate retrieval. The native check does not execute an installer, Runner or game. [Windows trust flags](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/ns-wintrust-wintrust_data).

The allowlist is intentionally not supplied with a guessed Foundation certificate. Record an approved public certificate's DER SHA-256 through the protected provider setup; it is not a password or private key. Rotation requires review of new pins, coordinated new releases and the update trust policy. Do not accept an unrelated Foundation-signed application merely because its publisher text matches.

Focused local checks, after building the current Runner:

```powershell
cargo build --locked --release -p steamwrapper-runner
pwsh -NoProfile -File scripts/windows/Test-RunnerSigningMetadata.ps1
pwsh -NoProfile -File scripts/windows/Test-WindowsSigning.ps1
```

These inspect real PE resources, reject an actual unsigned Runner and a modified copy of an embedded-signed PE, and exercise identity/timestamp/hash policy and atomic sidecar failures. Fixture successes are not evidence of a provided Foundation certificate, real production signing, clean-client installation or an automatic-update service.

## Application dossier and remaining gates

The [application dossier](/SteamWrapper/project/design/signing-application/) records the software facts for the rejected application. If the optional provider route is revisited, refresh the following evidence and onboarding requirements; personal application details are not published here:

1. A public current-form technical installer preview with its exact source tag, verified hosted build, local installation/recovery evidence and remaining clean-client limits. A preview does not waive stable-delivery gates.
2. License/dependency inventory and a precise list of own files versus redistributed runtimes.
3. Confirmed human authors, reviewers, approvers and MFA; privacy and uninstall behavior in both documentation languages.
4. Provider artifact configurations for the coordinated PE metadata, generated uninstaller, immutable payload and final Setup.
5. Approved signer pins, protected submission identity, approval flow, timeout/retry handling and audit evidence.
6. Genuine signed-artifact tests for timestamps, certificate expiry/revocation, rotation, post-sign manifests and clean Windows downloads.

Application identity, approval, token provisioning and certificate policy remain provider/maintainer setup. A required-signed release must stop when these are missing or verification fails; it must not quietly publish an unsigned replacement.

`packaging/windows/signpath/` contains separate payload, generated-uninstaller and Setup XML drafts. The exact own-file targets and metadata restrictions were checked against the reviewed official schema; none has provider approval. `Test-SignPathConfiguration.ps1` still rejects unapproved/missing prerequisites and broadened targets without reading a token or sending a request. The local `providerApproved` declaration is not independent evidence of admission, roles, MFA or certificate trust. Runtime and dependency terms are inventoried separately; a future provider would need to confirm treatment of Microsoft's redistributed components under its System Libraries exception.

## Privacy and user trust

Default operation uses local game profiles and Steam metadata without uploading them. Optional official Steam CDN cover requests require a preference and send a locally discovered AppID. Application updates contact GitHub or a configured CNB mirror on a manual check or when the player enables checking at Manager startup; automatic checking defaults off. No game profiles, credentials, saves or library contents are uploaded. Downloading and installation require user action. Future provider signing would submit release build artifacts and provenance only. Application requests and operating-system certificate checks are separate.

Requests to external services expose normal connection information such as the requesting IP address. Review the applicable [Valve privacy policy](https://store.steampowered.com/privacy_agreement/), [GitHub privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) and [SignPath privacy policy](https://signpath.io/privacy-policy). SignPath processes the maintainer's application and signing-service information; it is not part of the player's daily game launch.

Valid signatures establish origin and integrity under a trust policy. They do not guarantee that Defender, SmartScreen or Smart App Control accepts every new release. Keep protections enabled during download/launch acceptance. [Microsoft SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).
