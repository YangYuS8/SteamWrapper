#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd -- "$script_dir/../../.." && pwd)"
profile="${STEAMWRAPPER_RUNNER_PROFILE:-release}"
runner_name="steamwrapper-runner"
resource_dir="$script_dir/../resources/runner"
destination="$resource_dir/$runner_name"
windows_destination="$resource_dir/SteamWrapperRunner.exe"

case "$profile" in
  debug) cargo_args=(build --package steamwrapper-runner) ;;
  release) cargo_args=(build --package steamwrapper-runner --release) ;;
  *) printf 'Unsupported STEAMWRAPPER_RUNNER_PROFILE: %s\n' "$profile" >&2; exit 2 ;;
esac

if [[ "${STEAMWRAPPER_RUNNER_SKIP_BUILD:-0}" != "1" ]]; then
  cargo "${cargo_args[@]}" --manifest-path "$workspace_dir/Cargo.toml"
fi

source="$workspace_dir/target/$profile/$runner_name"
source_windows="$source.exe"
if [[ ! -f "$source" && ! -f "$source_windows" ]]; then
  printf 'Runner was not built at %s or %s\n' "$source" "$source_windows" >&2
  exit 1
fi

mkdir -p "$resource_dir"
if [[ -f "$source" ]]; then
  install -m 0755 "$source" "$destination"
  : > "$windows_destination"
  printf 'Staged %s Linux Runner: %s\n' "$profile" "$destination"
fi
if [[ -f "$source_windows" ]]; then
  install -m 0644 "$source_windows" "$windows_destination"
  : > "$destination"
  printf 'Staged %s Windows Runner resource\n' "$profile"
fi

test -f "$destination"
test -f "$windows_destination"
