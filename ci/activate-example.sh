#!/usr/bin/env bash
set -euo pipefail

DIR=$(dirname $0)

if [[ "$#" != "1" ]]; then
  >&2 echo "Usage: $0 [example]"
  exit 1
fi
example="$1"

system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
>&2 echo "System: ${system}"

systemProfile="$(nix build "./${DIR}/..#ci.${system}.${example}.system" -L --no-link --print-out-paths)"
>&2 echo "Built $systemProfile"

sudo rm -f "/etc/nix/nix.conf"
sudo "$systemProfile/activate"
"$systemProfile/activate-user"

# vim: set et ts=2 sw=2:
