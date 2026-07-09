# SteamWrapper v2

[中文 README](README.zh-CN.md) | [Agent Guidelines](AGENTS.md)

SteamWrapper v2 is a planned rewrite of SteamWrapper.

The goal is no longer just "put a wrapper exe into a game folder". The new goal is:

> Configure once in SteamWrapper Manager, then launch the game normally from Steam.

SteamWrapper should be visible only when users configure a game. During daily play, Steam should silently call a small runner process, and users should feel like they are launching the game normally.

## Goals

- No .NET Runtime requirement.
- No SteamEdit requirement in the default workflow.
- No need to copy a full wrapper program into every game folder.
- GUI is used only for configuration.
- Runtime launcher is headless and started automatically by Steam.
- Windows first, with Linux and SteamOS / Steam Deck support planned.
- Windows users should install with a setup wizard or use a portable zip.
- Game cover images should be loaded from the local Steam library/cache first; no online cover service is required for the first version.

## Product shape

```text
SteamWrapperManager.exe   # Tauri GUI/configuration app
SteamWrapperRunner.exe    # native headless runner called by Steam Launch Options
profiles.toml             # shared game profiles
logs/                     # runtime logs
backups/                  # Steam config backups, future use
cache/                    # local metadata/cache, future use
```

Typical flow:

```text
Install SteamWrapper
→ open SteamWrapper Manager once
→ scan local Steam games
→ select a Steam game profile
→ select the real target exe / launcher
→ apply or copy the generated Steam Launch Options
→ from then on, launch directly from Steam
```

Generated Launch Options example:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

## Technical direction

The v2 branch is being laid out as a Rust + Tauri workspace:

```text
crates/
  core/      # shared config, profile and launch option logic
  runner/    # native headless runtime entrypoint called by Steam

apps/
  manager/   # Tauri v2 + React + shadcn/ui configuration app
```

Selected stack:

- Runner/Core language: Rust
- Manager desktop shell: Tauri v2
- Manager frontend: React + TypeScript + Vite
- UI system: Tailwind CSS + shadcn/ui
- Config format: TOML
- Windows packaging: NSIS setup.exe first, portable zip second
- Windows process waiting: Job Object planned
- Linux process waiting: process group/session planned
- SteamOS support: planned after the Windows workflow is stable

See:

- `AGENTS.md`
- `docs/tech-stack.md`
- `docs/architecture.md`
- `docs/distribution.md`
- `docs/roadmap.md`

## License

Apache-2.0

## Status

This branch is an early v2 layout branch. The original C# implementation on `main` remains the stable legacy version for now.
