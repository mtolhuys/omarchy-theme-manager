#!/usr/bin/env bash
# Copy an external wallpaper into the theme's user backgrounds folder so the
# local wallpaper picker (omarchy-theme-bg-switcher) can list it.
#
# Usage: install-wallpaper.sh <theme-name> <source-path>
# Prints the installed (or already-local) absolute path on stdout.

set -euo pipefail

theme=${1:-}
src_raw=${2:-}

if [[ -z $theme || $theme == */* || $theme == "." || $theme == ".." || ${#theme} -gt 255 ]]; then
  echo "Invalid theme name" >&2
  exit 1
fi

if [[ -z $src_raw || $src_raw != /* || ${#src_raw} -gt 4096 ]]; then
  echo "Invalid wallpaper path" >&2
  exit 1
fi

if [[ ! -f $src_raw ]]; then
  echo "Wallpaper file does not exist: $src_raw" >&2
  exit 1
fi

src=$(realpath -e "$src_raw")

# Reject empty/near-empty sources so the picker never gains a black ghost tile.
src_size=$(stat -c '%s' "$src" 2>/dev/null || echo 0)
if [[ $src_size -lt 4096 ]]; then
  echo "Wallpaper file too small (${src_size} bytes): $src" >&2
  exit 1
fi

home=${HOME:-}

if [[ -z $home || $home != /* ]]; then
  echo "HOME is not absolute" >&2
  exit 1
fi

# Only allow wallpapers under the user's home (Aether cache or other local files).
case $src in
  "$home"/*) ;;
  *)
    echo "Wallpaper path must be under HOME" >&2
    exit 1
    ;;
esac

base=$(basename "$src")
if [[ -z $base || $base == "." || $base == ".." || $base == */* ]]; then
  echo "Invalid wallpaper basename" >&2
  exit 1
fi

case "${base,,}" in
  *.jpg | *.jpeg | *.png | *.gif | *.bmp | *.webp) ;;
  *)
    echo "Unsupported wallpaper type: $base" >&2
    exit 1
    ;;
esac

theme_dir=$home/.config/omarchy/backgrounds/$theme
current_dir=$home/.local/state/omarchy/current/theme/backgrounds

# Already visible to the local picker — keep the existing path.
case $src in
  "$theme_dir"/* | "$current_dir"/*)
    printf '%s\n' "$src"
    exit 0
    ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec python3 "$script_dir/publish-wallpaper.py" "$theme" "$src"
