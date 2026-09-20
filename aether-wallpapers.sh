#!/usr/bin/env bash
# Resolve Aether predictably for the wallpaper browser. Omarchy Shell may use a
# smaller PATH than interactive terminals, so prefer the conventional per-user
# binary before falling back to the system command.

set -euo pipefail

if [[ -n ${AETHER_BIN:-} ]]; then
  if [[ $AETHER_BIN != /* || ! -x $AETHER_BIN ]]; then
    echo "AETHER_BIN must name an absolute executable" >&2
    exit 127
  fi
  exec -- "$AETHER_BIN" "$@"
fi

home=${HOME:-}
if [[ $home == /* && -x $home/.local/bin/aether ]]; then
  exec -- "$home/.local/bin/aether" "$@"
fi

exec aether "$@"
