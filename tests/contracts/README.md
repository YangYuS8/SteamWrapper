# Windows C# / Rust contract checks

Run `mise run winui:contracts` on Windows with the pinned project toolchain. The
script creates a unique fixture directory under ignored `target/winui-contracts/`
and prints its location. It never uses the real Steam or SteamWrapper data paths.

`legacy-v2.toml` is synthetic historical v2 data, accepted by the current Rust
parser. It includes aliased profile keys, all existing wait modes, an omitted
legacy wait mode, Linux/SteamOS profiles, quoted/Unicode/empty arguments, relative
paths and unrelated unknown TOML values. The C# driver edits one target using the
same `ProfileStore` as WinUI. The Rust integration test compares the complete TOML
value tree and every typed profile with the original plus that one change.

The driver also creates Windows configuration through `ProfileStore`, stages the
actual release Rust Runner at an isolated stable path, and invokes it without a
`--config` override. A self-contained process fixture records argv/cwd, exits its
launcher with code 7, and keeps a descendant alive behind a file gate. Checks cover:

- Exact arguments, including Chinese, spaces, embedded quotes, a trailing
  backslash and an empty argument; no accidental forwarding of Steam's command.
- Relative target and working-directory resolution, including Chinese paths.
- Job mode waits after the launcher exits and until the descendant is released;
  root mode returns while that descendant is still waiting.
- Launcher exit-code preservation and a missing target's error exit/runtime log.

The process fixture and driver are test executables only. They are not shipped
with Manager or used as an application bridge. The controlled Job Object case
does not prove every launcher, Steam overlay, or real Steam playtime behavior.
The ignored Rust cross-language test runs explicitly in this script; ordinary
Rust-only test runs still validate the shared historical input.
