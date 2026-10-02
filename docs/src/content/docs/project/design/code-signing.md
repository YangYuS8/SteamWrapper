---
title: "Code signing policy"
description: "Implemented signing preparation and the pending SignPath Foundation application, with human approval and release boundaries."
---

## Current status

**SignPath Foundation application: not submitted. No subscription, project certificate or production signing approval has been obtained.** The maintainer has selected the free OSS route and accepts Foundation as the future certificate publisher. Current unsigned previews must not claim that signing is available.

The repository now provides Windows signing verification, post-sign Runner manifest generation and MSVC Runner PE version resources. It does not provide a signing-provider connection, export a private key, submit files to SignPath or establish an authenticated application update channel. See the [delivery plan](/SteamWrapper/project/design/windows-delivery/) for the wider implementation and acceptance stages.

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

After actual approval, replace the pending status with verified details and use this acknowledgment: “Free code signing provided by SignPath.io, certificate by SignPath Foundation.” Until then it describes a requested future service, not a provided certificate.

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

Prepare, but do not send automatically:

1. A public current-form installer preview after installation/recovery acceptance, its source tag and verified hosted build.
2. License/dependency inventory and a precise list of own files versus redistributed runtimes.
3. Confirmed human authors, reviewers, approvers and MFA; privacy and uninstall behavior in both documentation languages.
4. Provider artifact configurations for the coordinated PE metadata, generated uninstaller, immutable payload and final Setup.
5. Approved signer pins, protected submission identity, approval flow, timeout/retry handling and audit evidence.
6. Genuine signed-artifact tests for timestamps, certificate expiry/revocation, rotation, post-sign manifests and clean Windows downloads.

Application identity, approval, token provisioning and certificate policy remain provider/maintainer setup. A required-signed release must stop when these are missing or verification fails; it must not quietly publish an unsigned replacement.

## Privacy and user trust

Default operation uses local game profiles and Steam metadata without uploading them. Optional official Steam CDN cover requests require a preference and send a locally discovered AppID; optional update checks require consent and contact the documented distribution endpoints. Signing submits release build artifacts and provenance, never player profiles, credentials, saves or library contents. Application-request and operating-system certificate checks are separate.

Valid signatures establish origin and integrity under a trust policy. They do not guarantee that Defender, SmartScreen or Smart App Control accepts every new release. Keep protections enabled during download/launch acceptance. [Microsoft SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).
