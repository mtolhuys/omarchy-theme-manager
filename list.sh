#!/bin/bash

image_dirs=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

# The cached thumbnail hash for an image at a size:mtime signature, from the index or freshly derived.
hash_for() {
  local image=$1
  local signature=$2
  local hash
  hash=$(awk -F '\t' -v path="$image" -v sig="$signature" '$1 == path && $2 == sig { print $3; exit }' "$index_file" 2>/dev/null)
  [[ -n $hash ]] || hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
  printf '%s' "$hash"
}

# Older on-demand picker code keyed fallback thumbnails by file content.
# Keep finding those if a user still has them cached.
legacy_thumbnail_for() {
  local image=$1
  local legacy_hash
  legacy_hash=$(md5sum "$image" 2>/dev/null | cut -d ' ' -f 1)
  [[ -n $legacy_hash && -f $cache_dir/$legacy_hash.jpg ]] && printf '%s' "$cache_dir/$legacy_hash.jpg"
  return 0
}

thumbnail_for() {
  local image="$1"
  local signature thumbnail

  signature=$(stat -Lc '%s:%Y' "$image") || return
  thumbnail="$cache_dir/$(hash_for "$image" "$signature").jpg"
  [[ -f $thumbnail ]] || thumbnail=$(legacy_thumbnail_for "$image")

  if [[ -n $thumbnail && -f $thumbnail ]]; then
    printf '%s' "$thumbnail"
  else
    printf '%s' "$image"
  fi
}

while IFS= read -r dir; do
  [[ -n $dir && -d $dir ]] || continue
  find -L "$dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
    -print0 2>/dev/null
done <<<"$image_dirs" | sort -z | while IFS= read -r -d '' image; do
  # Skip empty/near-empty files (e.g. vantablack stock omarchy.webp is ~712B solid black).
  size=$(stat -c '%s' "$image" 2>/dev/null || echo 0)
  [[ $size -ge 4096 ]] || continue
  thumbnail=$(thumbnail_for "$image")
  [[ -n $thumbnail ]] || continue
  printf '%s\t%s\n' "$image" "$thumbnail"
done
