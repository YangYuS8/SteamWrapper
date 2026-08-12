# SteamWrapper v2 local development commands.
# Run `just` to list recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Start the Dioxus Desktop Manager with watch + hot reload and real local data.
dev:
    cd apps/manager-dioxus && dx serve --desktop --open=false --always-on-top=false

# Start the Manager with a disposable Steam and user-data sandbox.
dev-sandbox:
    root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT; cd apps/manager-dioxus && STEAMWRAPPER_E2E_ROOT="$root" STEAM_DIR="$root/Steam" XDG_DATA_HOME="$root/xdg-data" LOCALAPPDATA="$root/local-app-data" dx serve --desktop --open=false --always-on-top=false

# Build and run the Manager once without the development watcher.
run:
    cargo run -p steamwrapper-manager-dioxus --bin SteamWrapperManager

# Check Dioxus source and build a release client.
check:
    cd apps/manager-dioxus && dx check && dx build --release

# Run all Rust formatting, checks, and tests.
test:
    cargo fmt --all -- --check
    cargo check --workspace
    cargo test --workspace

# Type-check and run isolated Dioxus Native E2E.
e2e:
    pnpm install --frozen-lockfile
    pnpm --filter steamwrapper-manager-dioxus-e2e exec tsc --noEmit
    cargo build -p steamwrapper-manager-dioxus --features e2e
    pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:native

# Run every local quality gate used before delivery.
verify: test check e2e

# Stage the Linux Runner and produce an AppImage under release-artifacts/.
bundle-linux:
    STEAMWRAPPER_RUNNER_PROFILE=release apps/manager-dioxus/scripts/stage-runner.sh
    rm -rf release-artifacts
    cd apps/manager-dioxus && dx bundle --release --package-types appimage --out-dir ../../release-artifacts

# Remove Dioxus E2E artifacts and local release bundle output.
clean:
    pnpm --filter steamwrapper-manager-dioxus-e2e run e2e:clean
    rm -rf release-artifacts

# Show this command list.
default:
    just --list
