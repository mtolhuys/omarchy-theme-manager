#!/usr/bin/bash
# Install the theme-set hook into the user's hook directory. Started by Run
# (omakit/Run.qml) from ImagePicker.qml with the source and destination as
# arguments; it was a bash -c string before the Run port.
#
# The copy itself is done by install-hook.py, which walks the destination
# directory chain with checked no-follow descriptors and publishes by rename,
# so neither a planted parent directory link nor a planted destination link can
# redirect the write. This script only checks its arguments and hands over.
#
# Usage: install-hook.sh <source> <destination>
set -euo pipefail

src=${1:-}
dest=${2:-}
if [[ -z $src || $src != /* || -z $dest || $dest != /* ]]; then
  echo "Usage: install-hook.sh <source> <destination>" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec python3 -B "$script_dir/install-hook.py" "$src" "$dest"
