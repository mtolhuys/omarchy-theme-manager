#!/usr/bin/bash
# Compose the README banner loop from the frames marketing-preview.sh captures
# in the disposable plugin lab. One output: assets/banner.gif.
#
# The banner is the first thing anyone sees, and it went two releases stale
# because the tool that built it lived in an untracked scratch directory. This
# one is versioned so a release can regenerate it:
#
#   ./bin/lab plugin tests/lab/marketing-preview.sh     # capture, in the lab
#   tests/lab/compose-banner.sh <run-dir> [output.gif]  # compose, on the host
#
# Only ImageMagick is needed, which the plugin already requires.
set -euo pipefail

frames_dir=${1:-}
output=${2:-assets/banner.gif}

if [[ -z $frames_dir || ! -d $frames_dir ]]; then
  echo "Usage: compose-banner.sh <lab-run-dir> [output.gif]" >&2
  exit 2
fi

magick=/usr/bin/magick
font_bold=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
[[ -x $magick ]] || {
  echo "compose-banner.sh: $magick is missing" >&2
  exit 1
}
[[ -f $font_bold ]] || {
  echo "compose-banner.sh: $font_bold is missing" >&2
  exit 1
}

# The lab console is 1280x800 with a thin Hyprland bar on top; crop it so the
# frame is product only. Output width keeps the README readable without
# turning the GIF into a multi-megabyte download.
bar_height=36
width=900
caption_size=21
prefix=success-theme-manager-marketing

# scene | hold ms | caption. A continuation of the scene before it holds for
# less, because the reader has already taken in the layout.
scenes=(
  "01-themes|1500|Installed themes in Omarchy's own picker"
  "02-themes-scroll|950|Type to search  ·  arrows to browse"
  "02b-theme-grid|1600|Ctrl+G  ·  grid with favorites and collections"
  "03-catalog|1500|Ctrl+B  ·  community theme catalog"
  "04-catalog-filters|1300|Ctrl+F  ·  listing, availability, stars, sort"
  "05-wallpapers|1600|Ctrl+W  ·  wallpapers with a live palette"
  "07-actions|1200|Save  ·  All  ·  Reset  ·  Remove"
  "08-icons|1500|Ctrl+I  ·  icon themes with live previews"
  "09-wallhaven|1500|Ctrl+B  ·  open wallpaper catalog"
  "10-wallhaven-scroll|950|Bundled Omarchy art  ·  CC0 / CC-BY  ·  Commons"
  "11-themes-finale|1900|Sticky per-theme memory  ·  Themes, Wallpapers, Icons"
)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "compose-banner: reading frames from $frames_dir"

index=0
for scene in "${scenes[@]}"; do
  IFS='|' read -r name _hold caption <<<"$scene"
  source_frame="$frames_dir/$prefix-$name.png"
  if [[ ! -f $source_frame ]]; then
    echo "compose-banner: missing capture $source_frame" >&2
    exit 1
  fi

  plain=$(printf '%s/plain-%02d.png' "$work" "$index")
  capped=$(printf '%s/capped-%02d.png' "$work" "$index")

  # Product frame, bar cropped, scaled to the banner width.
  "$magick" "$source_frame" \
    -crop "x$((800 - bar_height))+0+$bar_height" +repage \
    -resize "${width}x" \
    -strip "$plain"

  # The caption rides in its own pill so it stays legible over any wallpaper.
  "$magick" -background none -fill '#f2f0e8' -font "$font_bold" \
    -pointsize "$caption_size" "label:$caption" "$work/label.png"
  label_w=$("$magick" identify -format '%w' "$work/label.png")
  label_h=$("$magick" identify -format '%h' "$work/label.png")
  pill_w=$((label_w + 44))
  pill_h=$((label_h + 22))
  "$magick" -size "${pill_w}x${pill_h}" xc:none \
    -fill '#14161ae0' -stroke '#3c4448' -strokewidth 1 \
    -draw "roundrectangle 0,0 $((pill_w - 1)),$((pill_h - 1)) 11,11" \
    "$work/label.png" -gravity center -composite "$work/chip.png"

  "$magick" "$plain" "$work/chip.png" -gravity north -geometry +0+26 \
    -composite "$capped"

  index=$((index + 1))
done

# Transitions blend the frames without their captions, so no text is ever
# ghosted over the next one -- which is what the previous banner did.
args=()
count=${#scenes[@]}
for i in $(seq 0 $((count - 1))); do
  IFS='|' read -r _name hold _caption <<<"${scenes[$i]}"
  capped=$(printf '%s/capped-%02d.png' "$work" "$i")
  args+=(-delay "$((hold / 10))" "$capped")

  next=$(((i + 1) % count))
  a=$(printf '%s/plain-%02d.png' "$work" "$i")
  b=$(printf '%s/plain-%02d.png' "$work" "$next")
  # Per-scene filenames: args carry paths, not pixels, so a shared name would
  # leave every transition pointing at the last scene's blend.
  "$magick" "$a" "$b" -morph 2 "$work/morph-$i-%02d.png"
  for step in 01 02; do
    args+=(-delay 6 "$work/morph-$i-$step.png")
  done
done

output_dir=$(dirname "$output")
if [[ ! -d $output_dir ]]; then
  echo "compose-banner.sh: $output_dir does not exist" >&2
  exit 1
fi

"$magick" -loop 0 "${args[@]}" \
  -colors 180 -dither FloydSteinberg \
  -layers OptimizePlus -layers OptimizeTransparency \
  "$output"

printf 'compose-banner: wrote %s (%s, %s frames)\n' \
  "$output" \
  "$(du -h "$output" | cut -f1)" \
  "$("$magick" identify "$output" | wc -l)"
