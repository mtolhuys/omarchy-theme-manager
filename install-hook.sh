#!/usr/bin/bash
# Copy the theme-set hook into the user's hook directory when it is missing
# or differs, and mark it executable. Started by Run (omakit/Run.qml) from
# ImagePicker.qml with the source and destination as arguments; it was a
# bash -c string before the Run port.
#
# Usage: install-hook.sh <source> <destination>
set -euo pipefail

src=${1:-}
dest=${2:-}
if [[ -z $src || $src != /* || -z $dest || $dest != /* ]]; then
  echo "Usage: install-hook.sh <source> <destination>" >&2
  exit 2
fi
[[ -f $src ]] || {
  echo "Hook source does not exist: $src" >&2
  exit 1
}

mkdir -p "$(dirname "$dest")"
if [[ ! -f $dest ]] || ! cmp -s "$src" "$dest"; then
  cp "$src" "$dest"
  chmod +x "$dest"
fi
