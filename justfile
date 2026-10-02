# Optional shortcuts. Direct SDK / PowerShell / pnpm commands remain supported.
set windows-shell := ["pwsh", "-NoProfile", "-Command"]

default:
    just --list

# Start WinUI using disposable Steam and user-data fixtures.
dev-sandbox:
    pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Sandbox

# Build or publish the native Windows Manager and independent Runner.
build:
    pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Build

publish:
    pwsh -NoProfile -File scripts/windows/Invoke-WinUI.ps1 -Action Publish

# Verify the shared Rust contracts on the current platform.
test:
    cargo fmt --all -- --check
    cargo check --locked --workspace
    cargo test --locked --workspace

# Run the complete Windows build/service/contract/publish gates.
verify:
    pwsh -NoProfile -File scripts/windows/Invoke-Build.ps1 -Action Verify

docs:
    pnpm docs:check
    pnpm docs:build
