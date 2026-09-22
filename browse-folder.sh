#!/usr/bin/env bash
# List one directory under $HOME for the picker's folder browser: the
# subdirectories first, then the images themselves, as bounded TSV rows.
#
# Usage: browse-folder.sh <absolute-dir> [--hidden]
#
# Rows:
#   D<TAB><directory><TAB><preview thumbnail or empty><TAB><image count>
#   F<TAB><image><TAB><thumbnail><TAB><size in bytes>
#   X<TAB>truncated       one of the bounds below was reached; more exists
#
# Everything is bounded: the directory must resolve under $HOME, entries are
# capped per kind, previews are only resolved for the first directories, and
# emission stops at a byte ceiling. Symlinks are never followed while walking,
# so a link planted inside the tree cannot widen it.
set -euo pipefail

# Byte-exact ${#row} and a stable, locale-independent order.
export LC_ALL=C

readonly max_dirs=240
readonly max_files=600
readonly max_preview_dirs=96
readonly max_dir_count=400
readonly max_index_lines=50000
readonly max_bytes=1048576
readonly min_image_bytes=4096

dir_raw=${1:-}
hidden=0
if [[ ${2:-} == --hidden ]]; then
  hidden=1
fi

home=${HOME:-}
if [[ -z $home || $home != /* ]]; then
  echo "HOME is not absolute" >&2
  exit 1
fi
home=${home%/}

if [[ -z $dir_raw || $dir_raw != /* || ${#dir_raw} -gt 4096 ]]; then
  echo "Invalid directory" >&2
  exit 1
fi

if [[ ! -d $dir_raw ]]; then
  echo "Not a directory: $dir_raw" >&2
  exit 1
fi

# realpath resolves every link in the path, so a link out of the tree is
# refused here rather than followed.
dir=$(realpath -e "$dir_raw")
case $dir in
  "$home" | "$home"/*) ;;
  *)
    echo "Directory must be under HOME" >&2
    exit 1
    ;;
esac

cache_dir=${XDG_CACHE_HOME:-$home/.cache}/omarchy/image-selector
index_file=$cache_dir/index.tsv

# Omarchy's thumbnail index, read once. Keyed by the same path/size:mtime
# signature list.sh derives, so a wallpaper Omarchy already thumbnailed shows
# its thumbnail here too; anything else falls back to the image itself.
declare -A thumbnail_index=()

# Set by split_record / directory_preview for the caller that follows them.
record_path=""
record_size=""
record_mtime=""
preview_path=""
preview_count=0

load_thumbnail_index() {
  local path signature hash count=0
  [[ -f $index_file ]] || return 0
  while IFS=$'\t' read -r path signature hash _rest; do
    if [[ -n $path && -n $signature && -n $hash ]]; then
      thumbnail_index["$path"$'\t'"$signature"]=$hash
    fi
    count=$((count + 1))
    if ((count >= max_index_lines)); then
      break
    fi
  done <"$index_file"
  return 0
}

thumbnail_for() {
  local path=$1
  local signature=$2
  local hash=${thumbnail_index["$path"$'\t'"$signature"]:-}
  if [[ -n $hash && -f $cache_dir/$hash.jpg ]]; then
    printf '%s' "$cache_dir/$hash.jpg"
  else
    printf '%s' "$path"
  fi
}

# A name the TSV can carry and the picker can use.
listable_name() {
  local name=$1
  [[ -n $name && $name != "." && $name != ".." ]] || return 1
  [[ $name != *$'\t'* && $name != *$'\n'* ]] || return 1
  ((hidden == 1)) || [[ $name != .* ]] || return 1
  return 0
}

emitted=0
truncated=0

emit() {
  local row=$1
  if ((emitted + ${#row} > max_bytes)); then
    truncated=1
    return 1
  fi
  printf '%s' "$row"
  emitted=$((emitted + ${#row}))
  return 0
}

# find enumerates images once per directory and reports the size and mtime
# with the path, so the signature costs no extra process per file.
find_images() {
  find -P "$1" -maxdepth 1 -type f -size "+$((min_image_bytes - 1))c" \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
    -o -iname '*.bmp' -o -iname '*.webp' \) \
    -printf '%p\t%s\t%Ts\0' 2>/dev/null
}

# The record is split from the right, which keeps a name holding a tab intact
# for listable_name to drop.
split_record() {
  local record=$1
  record_mtime=${record##*$'\t'}
  local head=${record%$'\t'*}
  record_size=${head##*$'\t'}
  record_path=${head%$'\t'*}
}

# The first usable image in a directory and how many it holds, from one walk.
directory_preview() {
  local target=$1
  local record count=0
  preview_path=""
  preview_count=0
  while IFS= read -r -d '' record; do
    split_record "$record"
    listable_name "${record_path##*/}" || continue
    count=$((count + 1))
    if [[ -z $preview_path ]]; then
      preview_path=$(thumbnail_for "$record_path" "$record_size:$record_mtime")
    fi
    if ((count >= max_dir_count)); then
      break
    fi
  done < <(find_images "$target" | sort -z)
  preview_count=$count
  return 0
}

emit_directories() {
  local entry name row shown=0 walked=0
  while IFS= read -r -d '' entry; do
    name=${entry##*/}
    listable_name "$name" || continue
    if ((shown >= max_dirs)); then
      truncated=1
      break
    fi
    preview_path=""
    preview_count=0
    if ((walked < max_preview_dirs)); then
      walked=$((walked + 1))
      directory_preview "$entry"
    fi
    printf -v row 'D\t%s\t%s\t%s\n' "$entry" "$preview_path" "$preview_count"
    emit "$row" || break
    shown=$((shown + 1))
  done < <(find -P "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
  return 0
}

emit_images() {
  local record row thumbnail shown=0
  while IFS= read -r -d '' record; do
    split_record "$record"
    listable_name "${record_path##*/}" || continue
    if ((shown >= max_files)); then
      truncated=1
      break
    fi
    thumbnail=$(thumbnail_for "$record_path" "$record_size:$record_mtime")
    printf -v row 'F\t%s\t%s\t%s\n' "$record_path" "$thumbnail" "$record_size"
    emit "$row" || break
    shown=$((shown + 1))
  done < <(find_images "$dir" | sort -z)
  return 0
}

load_thumbnail_index
emit_directories
emit_images

if ((truncated == 1)); then
  printf 'X\ttruncated\n'
fi
