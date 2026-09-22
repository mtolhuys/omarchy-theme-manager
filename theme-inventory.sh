#!/bin/bash

set -euo pipefail

user_themes=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes
stock_themes=${OMARCHY_PATH:-/usr/share/omarchy}/themes

theme_row() {
  local kind=$1
  local theme_path=$2
  local repository_url="" icons=""
  if [[ $kind == "user" ]]; then
    repository_url=$(git -C "$theme_path" config --get remote.origin.url 2>/dev/null || true)
  fi
  if [[ -f $theme_path/icons.theme ]]; then
    icons=$(tr -d '\r\n' <"$theme_path/icons.theme")
  fi
  printf '%s\t%s\t%s\t%s\n' "$kind" "${theme_path##*/}" "$repository_url" "$icons"
}

emit_themes() {
  local kind=$1
  local directory=$2
  local theme_path
  # A user with no themes of their own is a valid state, not a failure: a bare
  # return would carry the failed test's status out of the function and end the
  # script under set -e, before stock themes were ever emitted.
  [[ -d $directory ]] || return 0
  while IFS= read -r -d '' theme_path; do
    theme_row "$kind" "$theme_path"
  done < <(find "$directory" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
}

emit_themes user "$user_themes"
emit_themes stock "$stock_themes"
