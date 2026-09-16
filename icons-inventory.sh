#!/usr/bin/env bash
# Emit installed icon themes as TSV: name<TAB>folder<TAB>app<TAB>mime
set -euo pipefail

roots=("/usr/share/icons")
if [[ -n ${HOME:-} && -d $HOME/.local/share/icons ]]; then
  roots+=("$HOME/.local/share/icons")
fi

declare -A seen=()

is_hidden_theme() {
  local index=$1
  [[ -f $index ]] || return 0
  awk '
    BEGIN { hidden=0; in_theme=0 }
    /^\[Icon Theme\]/ { in_theme=1; next }
    /^\[/ { in_theme=0 }
    in_theme && $0 ~ /^Hidden[[:space:]]*=[[:space:]]*true[[:space:]]*$/ { hidden=1 }
    END { exit hidden ? 0 : 1 }
  ' "$index"
}

theme_inherits() {
  local index=$1
  [[ -f $index ]] || return 0
  awk -F= '
    BEGIN { in_theme=0 }
    /^\[Icon Theme\]/ { in_theme=1; next }
    /^\[/ { in_theme=0 }
    in_theme && $1 ~ /^Inherits[[:space:]]*$/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "$index"
}

# The first icon named in $2.. that exists in $1, as png, svg or svgz.
icon_in_dir() {
  local dir=$1
  shift
  local name ext
  for name in "$@"; do
    for ext in png svg svgz; do
      [[ -f $dir/$name.$ext ]] && { printf '%s\n' "$dir/$name.$ext"; return 0; }
    done
  done
  return 1
}

icon_in_theme() {
  local root=$1
  local theme=$2
  shift 2
  local -a sizes=("48x48" "32x32" "24x24" "16x16" "scalable" "48x48@2x" "32x32@2x")
  local -a cats=("places" "apps" "mimetypes" "actions" "devices" "status")
  local size cat
  [[ -d $root/$theme ]] || return 1
  for size in "${sizes[@]}"; do
    for cat in "${cats[@]}"; do
      icon_in_dir "$root/$theme/$size/$cat" "$@" && return 0
    done
  done
  return 1
}

# The themes $1 inherits from, one per line, over every root that carries it.
theme_parents() {
  local theme=$1
  local root name
  local -a inherit
  for root in "${roots[@]}"; do
    [[ -f $root/$theme/index.theme ]] || continue
    IFS=',' read -r -a inherit <<<"$(theme_inherits "$root/$theme/index.theme")"
    for name in "${inherit[@]}"; do
      [[ -n $name ]] && printf '%s\n' "$name"
    done
  done
}

# Breadth-first over the theme and its inheritance chain.
resolve_icon() {
  local theme_name=$1
  shift
  local -a queue=("$theme_name")
  local -A visited=()
  local current root parent
  while ((${#queue[@]} > 0)); do
    current=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -n $current && -z ${visited[$current]+x} ]] || continue
    visited[$current]=1
    for root in "${roots[@]}"; do
      icon_in_theme "$root" "$current" "$@" && return 0
    done
    for parent in $(theme_parents "$current"); do
      [[ -z ${visited[$parent]+x} ]] && queue+=("$parent")
    done
  done
  return 1
}

is_listable_theme() {
  local root=$1
  local name=$2
  local index=$root/$name/index.theme
  [[ -f $index ]] || return 1
  case $name in
    default | hicolor | . | ..) return 1 ;;
    .*) return 1 ;;
  esac
  ! is_hidden_theme "$index"
}

emit_theme() {
  local root=$1
  local name=$2
  local folder app mime
  is_listable_theme "$root" "$name" || return 0
  [[ -z ${seen[$name]+x} ]] || return 0
  seen[$name]=1

  folder=$(resolve_icon "$name" folder user-home folder-documents folder-open || true)
  app=$(resolve_icon "$name" utilities-terminal org.gnome.Nautilus firefox preferences-system application-x-executable || true)
  mime=$(resolve_icon "$name" text-x-generic image-x-generic audio-x-generic application-pdf || true)

  printf '%s\t%s\t%s\t%s\n' "$name" "$folder" "$app" "$mime"
}

for root in "${roots[@]}"; do
  [[ -d $root ]] || continue
  for path in "$root"/*; do
    [[ -d $path ]] || continue
    name=${path##*/}
    case $name in
      . | ..) continue ;;
      .*) continue ;;
    esac
    emit_theme "$root" "$name"
  done
done | LC_ALL=C sort
