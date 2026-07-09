# SteamWrapper v2

SteamWrapper v2 is a planned rewrite of SteamWrapper.

The goal is no longer just "put a wrapper exe into a game folder". The new goal is:

> Configure once in SteamWrapper, then launch the game normally from Steam.

SteamWrapper should be visible only when users configure a game. During daily play, Steam should silently call a small runner process, and users should feel like they are launching the game normally.

## Goals

- No .NET Runtime requirement.
- No SteamEdit requirement in the default workflow.
- No need to copy a full wrapper program into every game folder.
- GUI is used only for configuration.
- Runtime launcher is headless and started automatically by Steam.
- Windows first, with Linux and SteamOS / Steam Deck support planned.

## Product shape

```text
SteamWrapperManager.exe   # GUI/configuration app
SteamWrapperRunner.exe    # headless runner called by Steam Launch Options
profiles.toml             # shared game profiles
logs/                     # runtime logs
backups/                  # Steam config backups, future use
```

Typical flow:

```text
Open SteamWrapperManager once
→ add a Steam game profile
→ select the real target exe / launcher
→ apply or copy the generated Steam Launch Options
→ from then on, launch directly from Steam
```

Generated Launch Options example:

```text
"C:\Users\<User>\AppData\Local\SteamWrapper\SteamWrapperRunner.exe" --appid "123456" -- %command%
```

## Technical direction

The v2 branch is being laid out as a Rust workspace:

```text
crates/
  core/      # shared config, profile and launch option logic
  runner/    # headless runtime entrypoint called by Steam
  manager/   # GUI configuration app
```

Selected stack:

- Language: Rust
- Config format: TOML
- GUI: egui/eframe for the Manager
- Runner: native headless binary
- Windows process waiting: Job Object planned
- Linux process waiting: process group/session planned
- SteamOS support: planned after the Windows workflow is stable

See:

- `docs/tech-stack.md`
- `docs/architecture.md`
- `docs/roadmap.md`

## Status

This branch is an early v2 layout branch. The original C# implementation on `main` remains the stable legacy version for now.
