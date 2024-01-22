#!/usr/bin/env bash
set -euo pipefail
: "${BREW_SRC:=}"

root="$(dirname $0)/.."
brew_tail="$root/modules/brew.tail.sh"
brew_upstream="${BREW_SRC}/bin/brew"

if [[ -z "${BREW_SRC}" ]]; then
	>&2 echo "\$BREW_SRC must be set"
	exit 1
fi

>&2 echo "Updating ${brew_tail} using ${brew_upstream}"

cat >"${brew_tail}" <<EOF
# -----
# The following is copied from upstream bin/brew
# Copyright (c) 2009-present, Homebrew contributors
# -----

# nix-homebrew:
# Run scripts/update-brew-tail.sh to update this
EOF
sed \
	-e '1,/^HOMEBREW_LIBRARY=/d' \
	-e 's/^PATH="/PATH="@runtimePath@:/' \
	"${brew_upstream}" >>"${brew_tail}"
