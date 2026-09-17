#!/usr/bin/bash
# Report whether the remembered wallpaper is still the current background:
# OK, MISSING (the file is gone or under 4 KiB) or MISMATCH. Started by Run
# from ImagePicker.qml; a bash -c string before the Run port.
#
# Usage: verify-wallpaper.sh <expected-path>
set -euo pipefail

expected=${1:-}
if [[ -z $expected ]]; then
  echo OK
  exit 0
fi
if [[ ! -f $expected ]]; then
  echo MISSING
  exit 0
fi
size=$(stat -c %s "$expected" 2>/dev/null || echo 0)
if ((size < 4096)); then
  echo MISSING
  exit 0
fi
current=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
if [[ $current != "$expected" ]]; then
  echo MISMATCH
else
  echo OK
fi
