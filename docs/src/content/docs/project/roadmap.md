---
title: "SteamWrapper v2 roadmap"
description: "Windows implementation priorities, delivery gates, and deferred work."
---

<a id="steamwrapper-v2-roadmap"></a>

<a id="路线原则"></a>

## Direction

Reorder delivery around the original Windows-first v2 requirement: **usable Windows configuration and a complete launch flow → safe one-click apply/restore and Windows stabilization → reconsider cross-platform work**. The new Manager uses WinUI 3/C# and C# configuration services, with an independent Rust Runner. TOML, stable paths, and CLI remain unchanged.

The [Windows v2 redesign](/SteamWrapper/project/design/windows-v2/) is the current implementation plan; the [WinUI assessment](/SteamWrapper/project/decisions/winui3/) records the technical basis. The WinUI configuration preview is implemented, and Dioxus remains the migration baseline. These stages describe acceptance order rather than reinterpreting published version numbers. See [preview validation](/SteamWrapper/project/validation/winui/) for current evidence.

<a id="a-windows-工具链与配置契约"></a>

## A. Windows toolchain and configuration contracts

- [x] Trace original requirements, assess WinUI, and define product/architecture boundaries
- [x] Pin development tools with mise, install MSVC/Windows SDK, and validate an isolated self-contained WinUI build
- [x] Pass the existing Rust Runner's six tests on Windows, including Job Object and process-name waiting
- [x] Verify C# reading/single-field editing/Rust consumption: complete fields, defaults, legacy aliases, unknown data, Chinese text, paths, and arguments
- [x] Verify atomic configuration saves, preservation after replacement failure, backup, and editing conflicts (a final-check race remains for non-cooperating editors)
- [x] Pass C#-generated configuration to an actual Runner fixture and verify argv, cwd, and waiting
- [x] Add Windows build/contract CI incrementally while retaining existing workflows; the implementation baseline passed remote WinUI CI, while later changes need their own verification

<a id="b-winui-完整配置切片"></a>

## B. Complete WinUI configuration slice

- [x] Establish a WinUI window and independently testable C# application services, without new FFI/helpers
- [x] Configured-game home page, adding games, search, and manual Steam path selection
- [x] Native target selection, preservation of advanced arguments/working directory, and compatible TOML saving
- [x] Local covers or friendly placeholders, without a network-cover prerequisite
- [x] Install/repair stable Runner, retaining configuration and the old binary on failure
- [x] Generate/copy exact Launch Options with explicit guidance to preserve the old value and restore it manually
- [ ] Accept native interaction, Chinese input, keyboard use, scaling, cancellation, and error recovery

<a id="c-windows-可用预览与替换门槛"></a>

## C. Usable Windows preview and replacement gate

- [x] Close Manager, launch/exit through real Steam, and record status/playtime; a local Unity game and all five 9-nine titles passed. See [per-game evidence and limits](/SteamWrapper/project/validation/steam/)
- [x] After the local Episode 1 CHS launcher exited first, the actual game and Runner remained until ordinary exit; Chinese opening and Steam playtime passed, covering only this observed launcher scenario
- [ ] Complete player acceptance for Chinese/spaced paths, launch failures, and useful diagnostic logs; retain the explanation that job returns launcher status and the limits of descendant exit-code evidence
- [ ] Validate the self-contained directory and per-user installer on a clean Windows 11 x64 VM, without manual runtime setup
- [ ] Cover updates, moving Manager, busy Runner files, and version conflicts without damaging configuration/Launch Options
- [ ] Uninstall preserves Runner still referenced by Launch Options and user data by default
- [ ] Record installation size, startup time, validated games, and known limits; provide English and complete Simplified Chinese use/recovery instructions
- [ ] Switch the default Manager/release chain after these gates pass; retire Dioxus, old management layers, and replaced workflows according to dependencies

The preview may begin with manually copied Launch Options. Generation/copying is not a Steam write, and fixture success is not real Steam playtime validation.

<a id="d-windows-安全一键应用与恢复"></a>

## D. Safe Windows one-click apply and restore

- [ ] Verify local Steam configuration, identify games and multiple users, and show previous/proposed values
- [ ] Block writes while Steam is running and check again immediately before writing
- [ ] Backup, preserve unrelated data, write atomically, read back, and recover from interruption
- [ ] Detect external changes and avoid overwriting later user settings or other games during restore
- [ ] Expand real Windows launcher tests and improve explicit wait strategies where needed
- [ ] Make one-click apply the default player flow only after stable-release acceptance

This stage takes priority over Linux/SteamOS/Proton expansion. Portable delivery, domestic mirrors, and update entry points can follow Windows delivery needs; a larger release matrix must not block the main flow.

<a id="后续评估"></a>

## Later assessment

- Windows 10, ARM64, portable ZIP, MSIX, update channels, and signing; each requires separate artifact/platform evidence.
- Import/export, multiple targets, and batch restore according to actual player needs.
- Linux, SteamOS, and Proton with separate requirements/support matrices, outside the first Windows release gate.

<a id="现有实现记录与证据边界"></a>

## Existing implementation and evidence boundaries

Current source contains Rust core/manager-core/Runner, Dioxus 0.7.10 UI, local Steam scanning, CDN cover fallback, TOML saving, stable Runner installation, Launch Options generation, platform process code, and Dioxus Native E2E/packaging workflows. They provide migration references, not proof that the current Windows acceptance has passed.

The old roadmap's Dioxus and Linux/AppImage checks are historical implementation records available at `31a609d:docs/roadmap.md`; they are not mixed into current acceptance. Existing Linux code and CI remain, with new scope deferred. The WinUI configuration preview and contracts are implemented; see the [environment record](/SteamWrapper/development/windows/). One-click apply/restore and the new installer are still unimplemented.
