#!/usr/bin/env bash
set -euo pipefail

DIR=$(dirname $0)

real_nix="$(type -P nix)"
nix() {
  "${real_nix}" --extra-experimental-features "nix-command flakes" "$@"
}

if [[ "$#" != "1" ]]; then
  >&2 echo "Usage: $0 [example]"
  exit 1
fi
example="$1"

system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
>&2 echo "System: ${system}"

flakeDarwinAttr="${system}.${example}"

darwinRebuild="$(nix build ".#darwinConfigurations.${flakeDarwinAttr}.config.system.build.darwin-rebuild" -L --no-link --print-out-paths)/bin/darwin-rebuild"
>&2 echo "Built $darwinRebuild"

set -x
"$darwinRebuild" switch --flake ".#${flakeDarwinAttr}" -L -v --option extra-experimental-features "nix-command flakes"

# vim: set et ts=2 sw=2:
