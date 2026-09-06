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

safe_content_id() {
  [[ ${1:-} =~ ^[0-9]{1,12}$ ]]
}

cmd_search() {
  local query=""
  local sort=new
  local page=0
  local pagesize=$pagesize_default

  while (($# > 0)); do
    case $1 in
      --query)
        query=${2:-}
        shift 2
        ;;
      --sort)
        sort=$(normalize_sort "${2:-}")
        shift 2
        ;;
      --page)
        page=${2:-}
        shift 2
        ;;
      --pagesize)
        pagesize=${2:-}
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  is_uint "$page" || {
    echo "--page must be a non-negative integer" >&2
    exit 2
  }
  is_uint "$pagesize" || {
    echo "--pagesize must be a positive integer" >&2
    exit 2
  }
  if ((pagesize < 1 || pagesize > max_pagesize)); then
    echo "--pagesize must be between 1 and $max_pagesize" >&2
    exit 2
  fi

  # Bound and strip control characters from the search query.
  query=$(printf '%s' "$query" | tr -d '\000-\037\177' | head -c 120)

  mkdir -p "$cache_dir"
  local temporary
  temporary=$(mktemp "$cache_dir/.search.XXXXXX")
  trap 'rm -f "${temporary:-}"' EXIT

  local encoded_query
  encoded_query=$(jq -rn --arg q "$query" '$q|@uri')
  local api_pagesize=$pagesize
  if ((api_pagesize < 10)); then
    api_pagesize=10
  fi
  local url="${api_base}/content/data?categories=${category_id}&sortmode=${sort}&pagesize=${api_pagesize}&page=${page}&format=json"
  if [[ -n $query ]]; then
    url+="&search=${encoded_query}"
  fi

  if ! ocs_get "$url" "$temporary" "$max_search_bytes"; then
    echo "Icon catalog search failed." >&2
    exit 1
  fi

  if [[ $(stat -c '%s' "$temporary") -gt $max_search_bytes ]]; then
    echo "Icon catalog search response exceeds the safe size limit." >&2
    exit 1
  fi

  jq -e --argjson maxItems "$max_pagesize" --arg apiBase "$api_base" --arg sort "$sort" --argjson page "$page" --argjson pagesize "$pagesize" --arg query "$query" '
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
  ' "$temporary"
}

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

extract_archive() {
  local archive=$1
  local destination=$2
  mkdir -p "$destination"

  case $(file -b --mime-type "$archive") in
    application/gzip | application/x-gzip | application/x-tar | application/x-gtar | application/x-xz | application/x-bzip2 | application/zstd)
      # Strip components safely by validating every member path first.
      local listing
      listing=$(mktemp "$cache_dir/.listing.XXXXXX")
      if ! tar -tf "$archive" >"$listing"; then
        rm -f "$listing"
        echo "Could not read icon theme archive." >&2
        return 1
      fi
      local count
      count=$(wc -l <"$listing")
      if ((count > max_extract_files)); then
        rm -f "$listing"
        echo "Icon theme archive has too many files." >&2
        return 1
      fi
      local unsafe=0
      while IFS= read -r member; do
        [[ -z $member || $member == ./ ]] && continue
        case $member in
          /* | *..*)
            echo "Refusing archive member with unsafe path: $member" >&2
            unsafe=1
            break
            ;;
        esac
      done <"$listing"
      rm -f "$listing"
      if ((unsafe)); then
        return 1
      fi
      tar -xaf "$archive" -C "$destination"
      ;;
    application/zip | application/x-zip-compressed)
      local listing
      listing=$(mktemp "$cache_dir/.listing.XXXXXX")
      if ! unzip -Z1 "$archive" >"$listing"; then
        rm -f "$listing"
        echo "Could not read icon theme zip archive." >&2
        return 1
      fi
      local count
      count=$(wc -l <"$listing")
      if ((count > max_extract_files)); then
        rm -f "$listing"
        echo "Icon theme archive has too many files." >&2
        return 1
      fi
      local unsafe=0
      while IFS= read -r member; do
        [[ -z $member ]] && continue
        case $member in
          /* | *..*)
            echo "Refusing zip member with unsafe path: $member" >&2
            unsafe=1
            break
            ;;
        esac
      done <"$listing"
      rm -f "$listing"
      if ((unsafe)); then
        return 1
      fi
      unzip -q -o "$archive" -d "$destination"
      ;;
    *)
      echo "Unsupported icon theme archive type." >&2
      return 1
      ;;
  esac
}

install_theme_dir() {
  local source_dir=$1
  local index=$source_dir/index.theme
  [[ -f $index ]] || return 1

  local folder_name=${source_dir##*/}
  local display_name
  display_name=$(theme_name_from_index "$index")
  local target_name=$folder_name
  if safe_theme_dirname "$folder_name"; then
    target_name=$folder_name
  elif [[ -n $display_name ]]; then
    target_name=$(printf '%s' "$display_name" | tr ' ' '-' | tr -cd 'A-Za-z0-9._+-')
  fi

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
  # Drop any symlink that escapes the install root.
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

  printf '%s\n' "$target_name"
}

cmd_install() {
  local content_id=${1:-}
  shift || true
  local file_index=1

  while (($# > 0)); do
    case $1 in
      --file-index)
        file_index=${2:-}
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  safe_content_id "$content_id" || {
    echo "Invalid content id." >&2
    exit 2
  }
  if ! is_uint "$file_index" || ((file_index < 1 || file_index > 20)); then
    echo "--file-index must be between 1 and 20" >&2
    exit 2
  fi

  mkdir -p "$cache_dir"
  local work
  work=$(mktemp -d "$cache_dir/.install.XXXXXX")
  trap 'rm -rf "${work:-}"' EXIT

  local meta=$work/download.json
  local url="${api_base}/content/download/${content_id}/${file_index}?format=json"
  if ! ocs_get "$url" "$meta" 65536; then
    echo "Could not resolve icon theme download link." >&2
    exit 1
  fi

  local download_link
  download_link=$(jq -er '
    if (.status != "ok")
       or ((.data | type) != "array")
       or ((.data | length) < 1)
       or ((.data[0].downloadlink | type) != "string")
       or ((.data[0].downloadlink | length) < 12)
    then error("unexpected OCS download payload")
    else .data[0].downloadlink
    end
  ' "$meta")
  local file_name
  file_name=$(jq -r '
    ((.data[0].downloadlink // "") | split("/") | last) as $fromLink
    | if ($fromLink | length) > 0 then $fromLink else "icon-theme-archive" end
  ' "$meta")
  file_name=${file_name%%\?*}
  file_name=$(printf '%s' "$file_name" | tr -cd 'A-Za-z0-9._+-')
  [[ -n $file_name ]] || file_name=icon-theme-archive

  if [[ ! $download_link =~ ^https://files[0-9]+\.pling\.com/ ]] \
    && [[ ! $download_link =~ ^https://dl\.opendesktop\.org/ ]]; then
    echo "Refusing unexpected download host." >&2
    exit 1
  fi

  local archive=$work/$file_name
  if ! curl --fail --location --silent --show-error \
    --proto '=https' --max-filesize "$max_download_bytes" \
    --connect-timeout 10 --max-time 180 \
    --output "$archive" "$download_link"; then
    echo "Icon theme download failed." >&2
    exit 1
  fi

  if [[ $(stat -c '%s' "$archive") -le 64 ]]; then
    echo "Downloaded icon theme archive is empty." >&2
    exit 1
  fi

  local extract_dir=$work/extract
  extract_archive "$archive" "$extract_dir"

  local -a installed=()
  local index_path theme_dir theme_name
  while IFS= read -r index_path; do
    theme_dir=${index_path%/index.theme}
    theme_name=$(install_theme_dir "$theme_dir") || continue
    installed+=("$theme_name")
  done < <(find "$extract_dir" -type f -name index.theme | LC_ALL=C sort)

  if ((${#installed[@]} == 0)); then
    echo "No icon theme (index.theme) found in the archive." >&2
    exit 1
  fi

  jq -n \
    --arg id "$content_id" \
    --arg iconsRoot "$icons_root" \
    --argjson themes "$(printf '%s\n' "${installed[@]}" | jq -R . | jq -s .)" \
    '{
      contentId: $id,
      iconsRoot: $iconsRoot,
      themeNames: $themes,
      themeName: $themes[0]
    }'
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
