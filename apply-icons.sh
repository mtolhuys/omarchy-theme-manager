#!/usr/bin/bash
# Record an icon theme as the current one and apply it through gsettings.
# Started by Run from ImagePicker.qml with the theme name and the state file
# as arguments; a bash -c string with shell-quoted values before the Run port.
#
# Usage: apply-icons.sh <icon-theme> <current-icons-theme-file>
set -euo pipefail

icons=${1:-}
state=${2:-}
if [[ -z $icons || -z $state || $state != /* ]]; then
  echo "Usage: apply-icons.sh <icon-theme> <current-icons-theme-file>" >&2
  exit 2
fi
case $icons in
  *[!A-Za-z0-9._@+-]* | .* | -*)
    echo "Icon theme name is not safe: $icons" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$state")"
printf '%s\n' "$icons" >"$state"
gsettings set org.gnome.desktop.interface icon-theme "$icons"
