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

resolve_icon() {
  local theme_name=$1
  shift
  local -a names=("$@")
  local -a sizes=("48x48" "32x32" "24x24" "16x16" "scalable" "48x48@2x" "32x32@2x")
  local -a cats=("places" "apps" "mimetypes" "actions" "devices" "status")
  local -a queue=("$theme_name")
  local -A visited=()
  local current inherit root size cat name ext path

  while ((${#queue[@]} > 0)); do
    current=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -n $current && -z ${visited[$current]+x} ]] || continue
    visited[$current]=1

    for root in "${roots[@]}"; do
      [[ -d $root/$current ]] || continue
      for size in "${sizes[@]}"; do
        for cat in "${cats[@]}"; do
          for name in "${names[@]}"; do
            for ext in png svg svgz; do
              path=$root/$current/$size/$cat/$name.$ext
              if [[ -f $path ]]; then
                printf '%s\n' "$path"
                return 0
              fi
            done
          done
        done
      done
    done

    for root in "${roots[@]}"; do
      if [[ -f $root/$current/index.theme ]]; then
        IFS=',' read -r -a inherit <<<"$(theme_inherits "$root/$current/index.theme")"
        for name in "${inherit[@]}"; do
          [[ -n $name && -z ${visited[$name]+x} ]] && queue+=("$name")
        done
      fi
    done
  done

  return 1
}

emit_theme() {
  local root=$1
  local name=$2
  local index=$root/$name/index.theme
  local folder app mime

  [[ -f $index ]] || return 0
  case $name in
    default | hicolor | . | ..) return 0 ;;
    .*) return 0 ;;
  esac
  if is_hidden_theme "$index"; then
    return 0
  fi
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
