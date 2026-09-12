#!/bin/bash

set -euo pipefail

force_refresh=${1:-}
if [[ -n $force_refresh && $force_refresh != "--refresh" ]]; then
  echo "Usage: catalog.sh [--refresh]" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec python3 "$script_dir/catalog-cache.py" "$@"
