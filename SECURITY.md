# Security policy

English | [简体中文](SECURITY.zh-CN.md)

## Scope and versions

This policy covers SteamWrapper code and its configuration/launch workflow. The `v2` branch is under development; its WinUI Manager is a preview. There is no published security support window, response SLA, or guaranteed backport policy. Identify the affected version, branch, and commit when reporting an issue. This policy does not make a maintenance commitment for the legacy `main` branch.

Game translations, third-party launchers, Steam, and antivirus products are separate software. A detection or missing file alone does not establish a SteamWrapper vulnerability or prove that a third-party executable is safe.

## Reporting a vulnerability

Do not put exploit details, credentials, personal data, saves, or game binaries in a public issue.

The repository's GitHub private vulnerability reporting was **disabled when checked on 2026-09-08**, and no dedicated security email is configured in this repository. If the repository's Security tab later offers **Report a vulnerability**, use that private channel. Otherwise, open a minimal issue asking the maintainer to establish a private security-reporting channel; omit exploit steps, affected personal data, and sensitive attachments until a private channel is agreed. Do not assume an ordinary GitHub issue is private.

In a private report, include the affected commit/platform, a concise impact description, minimal reproduction steps, and a proposed fix if available. Use synthetic data wherever possible. This project does not promise a response or remediation deadline.

## Project boundaries

SteamWrapper does not inject DLLs, patch Steam or game binaries, bypass DRM, run a hidden service, or upload user data. Manager configuration and Runner process handling have separate responsibilities. Tests should use disposable fixtures; real-library acceptance requires the owner's authorization and must stop on unresolved save/cloud conflicts.

Do not disable security software or restore a quarantined third-party file merely to reproduce a SteamWrapper bug. System security changes and third-party file recovery are not SteamWrapper features. For ordinary configuration help, use [SUPPORT.md](SUPPORT.md).
