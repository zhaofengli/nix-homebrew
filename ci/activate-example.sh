#!/usr/bin/env bash
set -euo pipefail

DIR=$(dirname $0)

if [[ "$#" != "1" ]]; then
  >&2 echo "Usage: $0 [example]"
  exit 1
fi
example="$1"

nix-instantiate --eval --json -E 'builtins.currentSystem' >"${DIR}/system.json"
systemProfile=$(nix build "./${DIR}/..#darwinConfigurations.ci.${example}.system" -L --no-link --print-out-paths)

>&2 echo "Built $systemProfile"

sudo "$systemProfile/activate"
"$systemProfile/activate-user"

# vim: set et ts=2 sw=2:
