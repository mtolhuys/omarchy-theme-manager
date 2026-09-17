#!/usr/bin/bash
# Restore a theme's default icon theme: the remembered default, else the
# theme's own icons.theme, else Yaru-blue; record it, apply it, print it.
# Started by Run from ImagePicker.qml with PATH extended to Omarchy's bin
# directory for omarchy-theme-dir; a bash -c string before the Run port.
#
# Usage: reset-icons.sh <theme-name> [fallback-icon-theme]
set -euo pipefail

theme=${1:-}
fallback=${2:-}
[[ -n $theme ]] || {
  echo "Usage: reset-icons.sh <theme-name> [fallback-icon-theme]" >&2
  exit 2
}

dir=$(omarchy-theme-dir "$theme" 2>/dev/null || true)
value=""
if [[ -n $fallback ]]; then
  value=$fallback
elif [[ -n $dir && -f $dir/icons.theme ]]; then
  value=$(head -c 256 "$dir/icons.theme")
else
  value=Yaru-blue
fi
value=$(printf '%s' "$value" | tr -d '\r\n')
case $value in
  *[!A-Za-z0-9._@+-]* | .* | -* | "") value=Yaru-blue ;;
esac

state="$HOME/.local/state/omarchy/current/theme/icons.theme"
# shellcheck disable=SC2174 # the parents exist; the mode is for the one directory this may create
mkdir -p -m 0700 "$(dirname "$state")"
printf '%s\n' "$value" >"$state"
gsettings set org.gnome.desktop.interface icon-theme "$value"
printf '%s\n' "$value"
