#!/usr/bin/env bash
# Browse / install icon themes via Pling gnome-look.org OCS API (category 132).
# Network stays in this helper — QML never curls.
set -euo pipefail

api_base=${OMARCHY_ICONS_OCS_API:-https://api.gnome-look.org/ocs/v1}
category_id=${OMARCHY_ICONS_OCS_CATEGORY:-132}
pagesize_default=24
max_pagesize=48
max_search_bytes=$((2 * 1024 * 1024))
max_download_bytes=$((200 * 1024 * 1024))
max_extract_files=50000
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-manager/icons-browse
icons_root=${XDG_DATA_HOME:-$HOME/.local/share}/icons

# Scratch paths owned by the running command; the EXIT trap removes them.
search_tmp=""
install_work=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  icons-browse.sh search [--query TEXT] [--sort new|down|high] [--page N] [--pagesize N]
  icons-browse.sh install <content_id> [--file-index N]
USAGE
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 127
  }
}

is_uint() {
  [[ ${1:-} =~ ^[0-9]+$ ]]
}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

normalize_sort() {
  case ${1:-new} in
    new | newest) printf '%s\n' new ;;
    down | downloads | download) printf '%s\n' down ;;
    high | score) printf '%s\n' high ;;
    *)
      echo "Unsupported sort mode: $1 (use new, down, or high)" >&2
      exit 2
      ;;
  esac
}

ocs_get() {
  local url=$1
  local destination=$2
  local max_bytes=$3

  curl --fail --location --silent --show-error \
    --proto '=https' --max-filesize "$max_bytes" \
    --connect-timeout 10 --max-time 60 \
    -H 'Accept: application/json' \
    --output "$destination" "$url"
}

file_size() {
  stat -c '%s' "$1"
}

safe_content_id() {
  [[ ${1:-} =~ ^[0-9]{1,12}$ ]]
}

# --- search ------------------------------------------------------------------

search_query=""
search_sort=new
search_page=0
search_pagesize=$pagesize_default

parse_search_args() {
  while (($# > 0)); do
    case $1 in
      --query)
        search_query=${2:-}
        shift 2
        ;;
      --sort)
        search_sort=$(normalize_sort "${2:-}")
        shift 2
        ;;
      --page)
        search_page=${2:-}
        shift 2
        ;;
      --pagesize)
        search_pagesize=${2:-}
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
}

validate_search_paging() {
  is_uint "$search_page" || die "--page must be a non-negative integer" 2
  is_uint "$search_pagesize" || die "--pagesize must be a positive integer" 2
  if ((search_pagesize < 1 || search_pagesize > max_pagesize)); then
    die "--pagesize must be between 1 and $max_pagesize" 2
  fi
}

# Bound and strip control characters from the search query.
sanitize_query() {
  printf '%s' "$1" | tr -d '\000-\037\177' | head -c 120
}

search_url() {
  local encoded_query
  encoded_query=$(jq -rn --arg q "$search_query" '$q|@uri')
  local api_pagesize=$search_pagesize
  if ((api_pagesize < 10)); then
    api_pagesize=10
  fi
  local url="${api_base}/content/data?categories=${category_id}&sortmode=${search_sort}&pagesize=${api_pagesize}&page=${search_page}&format=json"
  if [[ -n $search_query ]]; then
    url+="&search=${encoded_query}"
  fi
  printf '%s\n' "$url"
}

fetch_search_payload() {
  local url=$1
  local destination=$2
  if ! ocs_get "$url" "$destination" "$max_search_bytes"; then
    die "Icon catalog search failed."
  fi
  if [[ $(file_size "$destination") -gt $max_search_bytes ]]; then
    die "Icon catalog search response exceeds the safe size limit."
  fi
}

search_result_filter='
  if (.status != "ok")
     or ((.data | type) != "array")
     or ((.data | length) > $maxItems)
  then
    error("unexpected OCS search payload")
  else
    {
      source: "gnome-look-ocs",
      apiBase: $apiBase,
      category: 132,
      query: $query,
      sort: $sort,
      page: $page,
      pagesize: $pagesize,
      totalitems: ((.totalitems | tonumber?) // 0),
      itemsperpage: ((.itemsperpage | tonumber?) // $pagesize),
      items: [
        .data[]
        | select(((.typeid | tonumber?) // 0) == 132 or (.xdg_type // "") == "icons")
        | {
            id: (.id | tostring),
            name: ((.name // "") | tostring | .[0:160]),
            summary: ((.summary // "") | tostring | .[0:280]),
            version: ((.version // "") | tostring | .[0:40]),
            downloads: ((.downloads | tonumber?) // 0),
            score: ((.score | tonumber?) // 0),
            personid: ((.personid // "") | tostring | .[0:80]),
            detailpage: ((.detailpage // "") | tostring | .[0:240]),
            previewUrl: ((.previewpic1 // "") | tostring | .[0:512]),
            downloadName: ((.downloadname1 // "") | tostring | .[0:160]),
            downloadSize: ((.downloadsize1 | tonumber?) // 0)
          }
        | select(.id | test("^[0-9]{1,12}$"))
      ][0:$pagesize]
    }
  end
'

render_search_result() {
  jq -e \
    --argjson maxItems "$max_pagesize" \
    --arg apiBase "$api_base" \
    --arg sort "$search_sort" \
    --argjson page "$search_page" \
    --argjson pagesize "$search_pagesize" \
    --arg query "$search_query" \
    "$search_result_filter" "$1"
}

cmd_search() {
  parse_search_args "$@"
  validate_search_paging
  search_query=$(sanitize_query "$search_query")

  mkdir -p "$cache_dir"
  search_tmp=$(mktemp "$cache_dir/.search.XXXXXX")
  trap 'rm -f "${search_tmp:-}"' EXIT

  fetch_search_payload "$(search_url)" "$search_tmp"
  render_search_result "$search_tmp"
}

# --- archives ----------------------------------------------------------------

archive_kind() {
  case $(file -b --mime-type "$1") in
    application/gzip | application/x-gzip | application/x-tar | application/x-gtar | application/x-xz | application/x-bzip2 | application/zstd)
      printf '%s\n' tar
      ;;
    application/zip | application/x-zip-compressed)
      printf '%s\n' zip
      ;;
    *)
      echo "Unsupported icon theme archive type." >&2
      return 1
      ;;
  esac
}

list_archive_members() {
  local kind=$1
  local archive=$2
  case $kind in
    tar) tar -tf "$archive" ;;
    zip) unzip -Z1 "$archive" ;;
  esac
}

# Every member path must stay inside the extraction root.
verify_member_listing() {
  local listing=$1
  local count
  count=$(wc -l <"$listing")
  if ((count > max_extract_files)); then
    echo "Icon theme archive has too many files." >&2
    return 1
  fi
  local member
  while IFS= read -r member; do
    [[ -z $member || $member == ./ ]] && continue
    case $member in
      /* | *..*)
        echo "Refusing archive member with unsafe path: $member" >&2
        return 1
        ;;
    esac
  done <"$listing"
}

unpack_archive() {
  local kind=$1
  local archive=$2
  local destination=$3
  case $kind in
    tar) tar -xaf "$archive" -C "$destination" ;;
    zip) unzip -q -o "$archive" -d "$destination" ;;
  esac
}

extract_archive() {
  local archive=$1
  local destination=$2
  mkdir -p "$destination"

  local kind
  kind=$(archive_kind "$archive") || return 1

  local listing
  listing=$(mktemp "$cache_dir/.listing.XXXXXX")
  local verdict=0
  if ! list_archive_members "$kind" "$archive" >"$listing"; then
    echo "Could not read icon theme archive." >&2
    verdict=1
  elif ! verify_member_listing "$listing"; then
    verdict=1
  fi
  rm -f "$listing"
  ((verdict == 0)) || return 1

  unpack_archive "$kind" "$archive" "$destination"
}

# --- theme directories ---------------------------------------------------------

theme_name_from_index() {
  local index=$1
  awk -F= '
    BEGIN { in_theme=0 }
    /^\[Icon Theme\]/ { in_theme=1; next }
    /^\[/ { in_theme=0 }
    in_theme && $1 ~ /^Name[[:space:]]*$/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$index"
}

safe_theme_dirname() {
  local name=$1
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || return 1
  [[ $name != default && $name != hicolor ]] || return 1
  [[ ${#name} -le 255 ]] || return 1
  return 0
}

# The folder name when it is safe, otherwise a sanitized display name.
resolve_target_name() {
  local source_dir=$1
  local index=$2
  local folder_name=${source_dir##*/}
  if safe_theme_dirname "$folder_name"; then
    printf '%s\n' "$folder_name"
    return 0
  fi
  local display_name
  display_name=$(theme_name_from_index "$index")
  if [[ -n $display_name ]]; then
    printf '%s' "$display_name" | tr ' ' '-' | tr -cd 'A-Za-z0-9._+-'
    printf '\n'
    return 0
  fi
  printf '%s\n' "$folder_name"
}

# Drop any symlink that escapes the install root.
prune_escaping_symlinks() {
  local target=$1
  find "$target" -type l -print0 | while IFS= read -r -d '' link; do
    local resolved
    if ! resolved=$(readlink -f "$link" 2>/dev/null); then
      rm -f "$link"
      continue
    fi
    case $resolved in
      "$target" | "$target"/*) ;;
      *) rm -f "$link" ;;
    esac
  done
}

install_theme_dir() {
  local source_dir=$1
  local index=$source_dir/index.theme
  [[ -f $index ]] || return 1

  local target_name
  target_name=$(resolve_target_name "$source_dir" "$index")
  safe_theme_dirname "$target_name" || {
    echo "Icon theme name is unsafe: $target_name" >&2
    return 1
  }

  mkdir -p "$icons_root"
  local target=$icons_root/$target_name
  rm -rf "$target"
  mkdir -p "$target"
  # Copy contents, never follow absolute symlinks out of the tree.
  cp -a --no-preserve=ownership "$source_dir"/. "$target"/
  prune_escaping_symlinks "$target"

  printf '%s\n' "$target_name"
}

# --- install -------------------------------------------------------------------

install_file_index=1

parse_install_args() {
  while (($# > 0)); do
    case $1 in
      --file-index)
        install_file_index=${2:-}
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
}

validate_install_args() {
  safe_content_id "$1" || die "Invalid content id." 2
  if ! is_uint "$install_file_index" || ((install_file_index < 1 || install_file_index > 20)); then
    die "--file-index must be between 1 and 20" 2
  fi
}

fetch_download_meta() {
  local content_id=$1
  local meta=$2
  local url="${api_base}/content/download/${content_id}/${install_file_index}?format=json"
  ocs_get "$url" "$meta" 65536 || die "Could not resolve icon theme download link."
}

download_link_from_meta() {
  jq -er '
    if (.status != "ok")
       or ((.data | type) != "array")
       or ((.data | length) < 1)
       or ((.data[0].downloadlink | type) != "string")
       or ((.data[0].downloadlink | length) < 12)
    then error("unexpected OCS download payload")
    else .data[0].downloadlink
    end
  ' "$1"
}

archive_name_from_meta() {
  local file_name
  file_name=$(jq -r '
    ((.data[0].downloadlink // "") | split("/") | last) as $fromLink
    | if ($fromLink | length) > 0 then $fromLink else "icon-theme-archive" end
  ' "$1")
  file_name=${file_name%%\?*}
  file_name=$(printf '%s' "$file_name" | tr -cd 'A-Za-z0-9._+-')
  [[ -n $file_name ]] || file_name=icon-theme-archive
  printf '%s\n' "$file_name"
}

require_download_host() {
  if [[ ! $1 =~ ^https://files[0-9]+\.pling\.com/ ]] \
    && [[ ! $1 =~ ^https://dl\.opendesktop\.org/ ]]; then
    die "Refusing unexpected download host."
  fi
}

download_archive() {
  local download_link=$1
  local archive=$2
  if ! curl --fail --location --silent --show-error \
    --proto '=https' --max-filesize "$max_download_bytes" \
    --connect-timeout 10 --max-time 180 \
    --output "$archive" "$download_link"; then
    die "Icon theme download failed."
  fi
  if [[ $(file_size "$archive") -le 64 ]]; then
    die "Downloaded icon theme archive is empty."
  fi
}

# Prints one installed theme name per line.
install_extracted_themes() {
  local extract_dir=$1
  local index_path theme_dir
  while IFS= read -r index_path; do
    theme_dir=${index_path%/index.theme}
    install_theme_dir "$theme_dir" || continue
  done < <(find "$extract_dir" -type f -name index.theme | LC_ALL=C sort)
}

render_install_result() {
  local content_id=$1
  shift
  jq -n \
    --arg id "$content_id" \
    --arg iconsRoot "$icons_root" \
    --argjson themes "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '{
      contentId: $id,
      iconsRoot: $iconsRoot,
      themeNames: $themes,
      themeName: $themes[0]
    }'
}

cmd_install() {
  local content_id=${1:-}
  shift || true
  parse_install_args "$@"
  validate_install_args "$content_id"

  mkdir -p "$cache_dir"
  install_work=$(mktemp -d "$cache_dir/.install.XXXXXX")
  trap 'rm -rf "${install_work:-}"' EXIT

  local meta=$install_work/download.json
  fetch_download_meta "$content_id" "$meta"

  local download_link
  download_link=$(download_link_from_meta "$meta")
  require_download_host "$download_link"

  local archive
  archive=$install_work/$(archive_name_from_meta "$meta")
  download_archive "$download_link" "$archive"

  local extract_dir=$install_work/extract
  extract_archive "$archive" "$extract_dir"

  local -a installed=()
  mapfile -t installed < <(install_extracted_themes "$extract_dir")
  if ((${#installed[@]} == 0)); then
    die "No icon theme (index.theme) found in the archive."
  fi

  render_install_result "$content_id" "${installed[@]}"
}

require_cmd curl
require_cmd jq
require_cmd tar
require_cmd file
require_cmd find
require_cmd unzip

command=${1:-}
shift || true

case $command in
  search) cmd_search "$@" ;;
  install) cmd_install "$@" ;;
  *) usage ;;
esac
