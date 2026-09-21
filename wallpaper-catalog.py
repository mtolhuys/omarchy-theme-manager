#!/usr/bin/env python3
"""Bounded open-wallpaper catalog for the Theme Manager plugin."""

from __future__ import annotations

import argparse
import hashlib
import html
from http.client import HTTPException
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import struct
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


API_URL = "https://commons.wikimedia.org/w/api.php"
OCS_API_URL = "https://api.opendesktop.org/ocs/v1/content/data"
OCS_CATEGORY = "296"
USER_AGENT = "Omarchy Theme Manager wallpaper catalog"
RESULT_LIMIT = 24
OCS_SEARCH_LIMIT = 48
MAX_API_BYTES = 4 * 1024 * 1024
MAX_THUMB_BYTES = 12 * 1024 * 1024
MAX_IMAGE_BYTES = 64 * 1024 * 1024
SEARCH_CACHE_TTL_SECONDS = 6 * 60 * 60
VALID_COLLECTIONS = {
    "omarchy",
    "community-abstract",
    "community-minimal",
    "community-dark",
    "community-space",
    "community-neon",
    "photography",
}
COLLECTION_SEEDS = {
    "community-abstract": ("", "gradient", "geometric"),
    "community-minimal": ("minimal", "simple", "gradient"),
    "community-dark": ("dark", "night", "black"),
    "community-space": ("space", "cosmic", "galaxy"),
    "community-neon": ("neon", "synthwave", "cyberpunk"),
}
VALID_SORTS = {"featured", "popular", "newest"}
VALID_LICENSES = {"any", "public-domain", "attribution", "share-alike"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
IMAGE_MIMES = {"image/jpeg", "image/png", "image/webp"}
BRANDING = re.compile(
    r"\b(gnome|ubuntu|debian|fedora|manjaro|nixos|windows|mac\s*os|linux\s*mint|"
    r"kde(?:\s*plasma)?|plasma\s+desktop|tux)\b|\b(?:with\s+)?logo\b",
    re.IGNORECASE,
)
DIMENSION = re.compile(r"([1-9][0-9]{2,4})\s*[x×_-]\s*([1-9][0-9]{2,4})", re.IGNORECASE)
ID_PATTERN = re.compile(r"^(omarchy|ocs|commons)-([0-9]{1,20})$")


class CatalogError(RuntimeError):
    pass


def fail(message: str):
    raise CatalogError(message)


def verify_owned_directory(fd, label):
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        fail(f"{label} is not a directory")
    if info.st_uid != os.getuid():
        fail(f"{label} is not owned by the current user")
    if info.st_mode & 0o022:
        fail(f"{label} is writable by another user")


def open_owned_directory(path, label):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(path, flags)
    verify_owned_directory(fd, label)
    return fd


def open_or_create_child(parent_fd, name, label):
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
    except FileExistsError:
        pass
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(name, flags, dir_fd=parent_fd)
    verify_owned_directory(fd, label)
    return fd


def home_paths(variable: str, default: str):
    """The normalized HOME and the directory named by variable, which must be inside HOME."""
    home = os.environ.get("HOME", "")
    target = os.environ.get(variable, os.path.join(home, default))
    if not home or not os.path.isabs(home) or not os.path.isabs(target):
        fail(f"HOME and {variable} must be absolute")
    home_normal = os.path.normpath(home)
    target_normal = os.path.normpath(target)
    if os.path.commonpath([home_normal, target_normal]) != home_normal:
        fail(f"{variable} must be inside HOME")
    return home_normal, target_normal


def path_components(home_normal: str, target_normal: str):
    relative = os.path.relpath(target_normal, home_normal)
    if relative == ".":
        return []
    components = relative.split(os.sep)
    if any(component in {"", ".", ".."} for component in components):
        fail("Invalid plugin directory")
    return components


@contextmanager
def owned_directory(variable: str, default: str, label: str, names: tuple[str, ...]):
    """Open HOME, every component of the XDG directory and every plugin name below it.

    Each descriptor is opened no-follow relative to its parent and owner-checked; the
    last one is yielded and all of them are closed afterwards.
    """
    home_normal, target_normal = home_paths(variable, default)
    directory_fds = []
    try:
        directory_fds.append(open_owned_directory(home_normal, "HOME"))
        for component in path_components(home_normal, target_normal):
            directory_fds.append(open_or_create_child(directory_fds[-1], component, f"{variable} directory"))
        for name in names:
            directory_fds.append(open_or_create_child(directory_fds[-1], name, label))
        yield directory_fds[-1]
    finally:
        for fd in reversed(directory_fds):
            os.close(fd)


class PluginDirectory:
    """A plugin directory below HOME whose whole chain is verified before every use."""

    def __init__(self, variable: str, default: str, label: str, *names: str):
        self.variable = variable
        self.default = default
        self.label = label
        self.names = names
        with self.open():
            pass
        self.path = Path(home_paths(variable, default)[1], *names)

    def open(self):
        return owned_directory(self.variable, self.default, self.label, self.names)


def plugin_cache_dir(name: str) -> PluginDirectory:
    return PluginDirectory("XDG_CACHE_HOME", ".cache", "wallpaper cache", "omarchy-theme-manager", name)


def wallpaper_dir() -> PluginDirectory:
    return PluginDirectory("XDG_DATA_HOME", ".local/share", "wallpaper directory", "omarchy-theme-manager", "wallpapers")


def atomic_write(directory: PluginDirectory, name: str, data: bytes, mode: int = 0o600) -> Path:
    temporary = f".{name}.{secrets.token_hex(8)}.tmp"
    with directory.open() as dir_fd:
        file_fd = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            mode,
            dir_fd=dir_fd,
        )
        try:
            with os.fdopen(file_fd, "wb", closefd=True) as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
        except Exception:
            try:
                os.unlink(temporary, dir_fd=dir_fd)
            except FileNotFoundError:
                pass
            raise
        os.replace(temporary, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    return directory.path / name


def is_pling_file_host(host: str) -> bool:
    return bool(re.fullmatch(r"files[0-9]{1,3}\.pling\.com", host))


def is_ocs_cdn_host(host: str) -> bool:
    return bool(re.fullmatch(r"ocs-dl\.[a-z0-9-]{2,24}\.cdn\.digitaloceanspaces\.com", host))


def trusted_host(host: str) -> bool:
    host = host.lower()
    return host in {
        "api.opendesktop.org",
        "commons.wikimedia.org",
        "upload.wikimedia.org",
        "thumb.wikimedia.org",
        "images.pling.com",
    } or is_pling_file_host(host) or is_ocs_cdn_host(host)


class SafeRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        parsed = urlparse(new_url)
        if parsed.scheme != "https" or not trusted_host(parsed.hostname or ""):
            raise CatalogError("wallpaper provider redirected to an untrusted host")
        return super().redirect_request(request, fp, code, message, headers, new_url)


OPENER = build_opener(SafeRedirectHandler())


def request_bytes(url: str, maximum: int, expected_json: bool = False) -> bytes:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not trusted_host(parsed.hostname or ""):
        raise CatalogError("refusing untrusted wallpaper URL")
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json" if expected_json else "image/*"})
    try:
        with OPENER.open(request, timeout=30) as response:
            length = response.headers.get("Content-Length")
            if length and int(length) > maximum:
                raise CatalogError(f"wallpaper response exceeds the {maximum} byte limit")
            data = response.read(maximum + 1)
            if len(data) > maximum:
                raise CatalogError(f"wallpaper response exceeds the {maximum} byte limit")
            if expected_json:
                content_type = response.headers.get_content_type()
                if content_type not in {"application/json", "text/json", "text/plain"}:
                    raise CatalogError(f"wallpaper provider returned {content_type}")
            return data
    except HTTPError as error:
        raise CatalogError(f"wallpaper provider returned HTTP {error.code}") from error
    except URLError as error:
        raise CatalogError(f"wallpaper provider request failed: {error.reason}") from error
    except (HTTPException, ValueError) as error:
        raise CatalogError("wallpaper provider returned an invalid URL or response") from error


def request_json(url: str) -> dict:
    try:
        value = json.loads(request_bytes(url, MAX_API_BYTES, expected_json=True))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise CatalogError("wallpaper provider returned invalid JSON") from error
    if not isinstance(value, dict):
        raise CatalogError("wallpaper provider returned an invalid document")
    return value


def clean_text(value, maximum: int = 240) -> str:
    text = re.sub(r"<[^>]*>", " ", str(value or ""))
    return re.sub(r"\s+", " ", html.unescape(text)).strip()[:maximum]


def clean_https(value, hosts=None) -> str:
    text = html.unescape(str(value or "")).strip()
    parsed = urlparse(text)
    if parsed.scheme != "https" or not parsed.hostname:
        return ""
    host = parsed.hostname.lower()
    if hosts is not None and host not in hosts:
        return ""
    return parsed._replace(
        path=quote(parsed.path, safe="/%:@+"),
        query=quote(parsed.query, safe="=&%:+,;/?@"),
        fragment="",
    ).geturl()


def normalize(args) -> dict:
    query = re.sub(r"\s+", " ", args.query or "").strip()[:120]
    collection = args.collection
    if collection in {"abstract", "minimal", "dark", "space", "neon"}:
        collection = "community-" + collection
    if collection not in VALID_COLLECTIONS:
        collection = "omarchy"
    sorting = args.sorting if args.sorting in VALID_SORTS else "featured"
    license_filter = args.license if args.license in VALID_LICENSES else "any"
    if collection == "omarchy":
        sorting, license_filter = "featured", "any"
    return {
        "query": query,
        "collection": collection,
        "sorting": sorting,
        "license": license_filter,
        "page": max(1, args.page),
    }


def matches_license(license_name: str, value: str) -> bool:
    lower = license_name.lower()
    if value == "public-domain":
        return "public domain" in lower or "cc0" in lower or lower.startswith("pd-")
    if value == "attribution":
        return "cc by" in lower and "by-sa" not in lower
    if value == "share-alike":
        return "by-sa" in lower or "share alike" in lower or "gfdl" in lower
    return True


def display_name(value: str) -> str:
    return " ".join(word[:1].upper() + word[1:] for word in re.split(r"[-_\s]+", value) if word)


def omarchy_root() -> Path:
    configured = os.environ.get("OMARCHY_PATH", "")
    root = Path(configured) if os.path.isabs(configured) else Path("/usr/share/omarchy")
    try:
        return (root / "themes").resolve(strict=True)
    except OSError as error:
        raise CatalogError("bundled Omarchy wallpaper collection was not found") from error


def omarchy_id(relative: str) -> str:
    value = int.from_bytes(hashlib.sha256(relative.encode()).digest()[:8], "big") & ((1 << 63) - 1)
    return f"omarchy-{value}"


def image_dimensions(path: Path) -> str:
    try:
        data = path.read_bytes()[:65536]
        if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
            width, height = struct.unpack(">II", data[16:24])
            return f"{width}x{height}"
        if data.startswith(b"\xff\xd8"):
            index = 2
            while index + 9 < len(data):
                if data[index] != 0xFF:
                    index += 1
                    continue
                marker = data[index + 1]
                index += 2
                if marker in {0xD8, 0xD9}:
                    continue
                length = int.from_bytes(data[index:index + 2], "big")
                if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF} and length >= 7:
                    height = int.from_bytes(data[index + 3:index + 5], "big")
                    width = int.from_bytes(data[index + 5:index + 7], "big")
                    return f"{width}x{height}"
                index += max(2, length)
        if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and len(data) >= 30:
            kind = data[12:16]
            if kind == b"VP8X":
                width = 1 + int.from_bytes(data[24:27], "little")
                height = 1 + int.from_bytes(data[27:30], "little")
                return f"{width}x{height}"
            if kind == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
                width = int.from_bytes(data[26:28], "little") & 0x3FFF
                height = int.from_bytes(data[28:30], "little") & 0x3FFF
                return f"{width}x{height}"
            if kind == b"VP8L" and data[20] == 0x2F:
                bits = int.from_bytes(data[21:25], "little")
                return f"{(bits & 0x3FFF) + 1}x{((bits >> 14) & 0x3FFF) + 1}"
    except (OSError, ValueError, struct.error):
        pass
    return ""


def discover_omarchy() -> list[dict]:
    root = omarchy_root()
    groups = []
    seen = set()
    for theme_dir in sorted(root.iterdir(), key=lambda value: value.name.lower()):
        if theme_dir.is_symlink() or not theme_dir.is_dir():
            continue
        backgrounds = theme_dir / "backgrounds"
        if not backgrounds.is_dir() or backgrounds.is_symlink():
            continue
        group = []
        for path in sorted(backgrounds.iterdir(), key=lambda value: value.name.lower()):
            if path.is_symlink() or not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:
                continue
            if path.stem.lower() == "omarchy":
                continue
            try:
                info = path.stat()
                resolved = path.resolve(strict=True)
                relative = resolved.relative_to(root).as_posix()
            except (OSError, ValueError):
                continue
            if info.st_size <= 0 or info.st_size > MAX_IMAGE_BYTES:
                continue
            item_id = omarchy_id(relative)
            if item_id in seen:
                continue
            seen.add(item_id)
            source_dir = "/".join(quote(part, safe="") for part in relative.split("/")[:2])
            group.append({
                "id": item_id,
                "title": f"{display_name(theme_dir.name)} — {display_name(path.stem)}",
                "url": f"https://github.com/omacom/omarchy/tree/quattro/themes/{source_dir}",
                "path": str(resolved),
                "resolution": image_dimensions(resolved),
                "collection": "omarchy",
                "source": "Bundled with Omarchy",
                "license": "See Omarchy source",
                "licenseURL": "https://github.com/omacom/omarchy/tree/quattro/themes",
                "author": "",
                "thumbURL": str(resolved),
            })
        if group:
            groups.append(group)
    items = []
    for row in range(max((len(group) for group in groups), default=0)):
        items.extend(group[row] for group in groups if row < len(group))
    return items


def search_omarchy(params: dict) -> dict:
    query = params["query"].lower()
    items = [item for item in discover_omarchy() if not query or query in (item["title"] + " " + item["author"]).lower()]
    total = len(items)
    start = (params["page"] - 1) * RESULT_LIMIT
    return {
        "wallpapers": items[start:start + RESULT_LIMIT],
        "meta": {
            "current_page": params["page"],
            "last_page": max(1, math.ceil(total / RESULT_LIMIT)),
            "total": total,
        },
    }


def ocs_string(record: dict, key: str) -> str:
    value = record.get(key, "")
    return str(value) if isinstance(value, (str, int, float)) else ""


def ocs_license(tags: str):
    for tag in tags.lower().split(","):
        value = tag.strip()
        if value == "cc0":
            return "CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"
        if value == "cc-by":
            return "CC BY", "https://creativecommons.org/licenses/by/"
        if value == "cc-by-sa":
            return "CC BY-SA", "https://creativecommons.org/licenses/by-sa/"
    return "", ""


def download_mime(tags: str) -> str:
    for value in tags.split("##"):
        if value.lower().startswith("mimetype="):
            return value.split("=", 1)[1].strip().lower()
    return ""


def best_ocs_download(record: dict):
    best = None
    best_quality = -10**18
    for index in range(1, 51):
        url = ocs_string(record, f"downloadlink{index}")
        name = ocs_string(record, f"downloadname{index}")
        price = ocs_string(record, f"downloadprice{index}")
        mime = download_mime(ocs_string(record, f"downloadtags{index}"))
        try:
            size = int(float(ocs_string(record, f"downloadsize{index}") or 0))
        except ValueError:
            size = 0
        if not url or (price and price != "0") or Path(name).suffix.lower() not in IMAGE_EXTENSIONS or (mime and mime not in IMAGE_MIMES):
            continue
        normalized = re.sub(r"[-_]", " ", name.lower())
        quality = size
        if "no logo" in normalized or "without logo" in normalized:
            quality += 1_000_000_000
        elif "with logo" in normalized:
            quality -= 1_000_000_000
        if quality > best_quality:
            best, best_quality = {"url": url, "name": name}, quality
    return best


def inferred_resolution(value: str) -> str:
    match = DIMENSION.search(value)
    if match:
        return f"{match.group(1)}x{match.group(2)}"
    lower = value.lower()
    for token, resolution in (("8k", "7680x4320"), ("5k", "5120x2880"), ("4k", "3840x2160"), ("2k", "2560x1440")):
        if token in lower:
            return resolution
    return ""


def ocs_item(record: dict, collection: str, license_filter: str):
    item_id = ocs_string(record, "id")
    if not item_id.isdigit() or len(item_id) > 20:
        return None
    license_name, license_url = ocs_license(ocs_string(record, "tags"))
    if not license_name or not matches_license(license_name, license_filter):
        return None
    selected = best_ocs_download(record)
    if not selected:
        return None
    title = clean_text(ocs_string(record, "name"), 180)
    branded = " ".join((title, ocs_string(record, "summary"), clean_text(ocs_string(record, "description")), selected["name"]))
    if BRANDING.search(branded):
        return None
    thumb = clean_https(ocs_string(record, "previewpic1"), {"images.pling.com"})
    page = clean_https(ocs_string(record, "detailpage"), {"www.gnome-look.org", "www.pling.com", "www.opendesktop.org"})
    download = clean_https(selected["url"])
    if not thumb or not page or not download or not trusted_host(urlparse(download).hostname or ""):
        return None
    return {
        "id": f"ocs-{item_id}",
        "title": title,
        "url": page,
        "path": download,
        "resolution": inferred_resolution(" ".join((selected["name"], title, ocs_string(record, "summary")))),
        "collection": collection,
        "source": "OpenDesktop community",
        "license": license_name,
        "licenseURL": license_url,
        "author": clean_text(ocs_string(record, "personid"), 160),
        "thumbURL": thumb,
    }


def ocs_sort(value: str) -> str:
    return {"newest": "new", "popular": "down"}.get(value, "high")


def search_ocs_seed(params: dict, seed: str):
    query = " ".join(part for part in (seed, params["query"]) if part).strip()
    values = {
        "categories": OCS_CATEGORY,
        "sortmode": ocs_sort(params["sorting"]),
        "pagesize": OCS_SEARCH_LIMIT,
        "page": params["page"] - 1,
        "format": "json",
    }
    if query:
        values["search"] = query
    payload = request_json(OCS_API_URL + "?" + urlencode(values))
    if payload.get("status") != "ok":
        raise CatalogError("OpenDesktop search failed: " + clean_text(payload.get("message")))
    records = payload.get("data") if isinstance(payload.get("data"), list) else []
    items = [item for record in records if isinstance(record, dict) for item in [ocs_item(record, params["collection"], params["license"])] if item]
    try:
        total = max(len(items), int(payload.get("totalitems") or 0))
    except (TypeError, ValueError):
        total = len(items)
    return items, total, max(params["page"], math.ceil(total / OCS_SEARCH_LIMIT))


def search_ocs(params: dict) -> dict:
    groups = []
    total = 0
    last_page = params["page"]
    first_error = None
    for seed in COLLECTION_SEEDS[params["collection"]]:
        try:
            items, seed_total, seed_last_page = search_ocs_seed(params, seed)
            groups.append(items)
            total += seed_total
            last_page = max(last_page, seed_last_page)
        except CatalogError as error:
            first_error = first_error or error
    if not groups and first_error:
        raise first_error
    results, seen, authors = [], set(), {}
    for row in range(max((len(group) for group in groups), default=0)):
        for group in groups:
            if row >= len(group):
                continue
            item = group[row]
            author = item["author"].lower()
            if item["id"] in seen or (author and authors.get(author, 0) >= 6):
                continue
            seen.add(item["id"])
            authors[author] = authors.get(author, 0) + 1
            results.append(item)
            if len(results) == RESULT_LIMIT:
                break
        if len(results) == RESULT_LIMIT:
            break
    return {"wallpapers": results, "meta": {"current_page": params["page"], "last_page": last_page, "total": max(total, len(results))}}


def commons_item(page: dict, license_filter: str):
    image_info = page.get("imageinfo")
    if not isinstance(image_info, list) or not image_info or not isinstance(image_info[0], dict):
        return None
    info = image_info[0]
    if info.get("mime") not in IMAGE_MIMES:
        return None
    metadata = info.get("extmetadata") if isinstance(info.get("extmetadata"), dict) else {}
    metadata_value = lambda name: metadata.get(name, {}).get("value", "") if isinstance(metadata.get(name), dict) else ""
    license_name = clean_text(metadata_value("LicenseShortName"), 80)
    if not license_name or not matches_license(license_name, license_filter):
        return None
    image = clean_https(info.get("url"), {"upload.wikimedia.org", "thumb.wikimedia.org"})
    thumb = clean_https(info.get("thumburl") or info.get("url"), {"upload.wikimedia.org", "thumb.wikimedia.org"})
    source = clean_https(info.get("descriptionurl"), {"commons.wikimedia.org"})
    page_id = page.get("pageid")
    if not isinstance(page_id, int) or page_id <= 0 or not image or not thumb or not source:
        return None
    width, height = int(info.get("width") or 0), int(info.get("height") or 0)
    return {
        "id": f"commons-{page_id}",
        "title": clean_text(str(page.get("title") or "").removeprefix("File:"), 180),
        "url": source,
        "path": image,
        "resolution": f"{width}x{height}" if width > 0 and height > 0 else "",
        "collection": "photography",
        "source": "Wikimedia Commons",
        "license": license_name,
        "licenseURL": clean_https(metadata_value("LicenseUrl")),
        "author": clean_text(metadata_value("Artist"), 160),
        "thumbURL": thumb,
    }


def search_commons(params: dict) -> dict:
    search = " ".join(part for part in (params["query"], 'incategory:"Featured pictures of landscapes"') if part)
    values = {
        "action": "query", "format": "json", "formatversion": "2", "generator": "search",
        "gsrnamespace": "6", "gsrlimit": RESULT_LIMIT, "gsroffset": (params["page"] - 1) * RESULT_LIMIT,
        "gsrinfo": "totalhits", "gsrsearch": search,
        "gsrsort": "create_timestamp_desc" if params["sorting"] == "newest" else "relevance",
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "960",
        "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl",
    }
    payload = request_json(API_URL + "?" + urlencode(values))
    query = payload.get("query") if isinstance(payload.get("query"), dict) else {}
    pages = query.get("pages") if isinstance(query.get("pages"), list) else []
    items = [item for page in pages if isinstance(page, dict) for item in [commons_item(page, params["license"])] if item][:RESULT_LIMIT]
    info = query.get("searchinfo") if isinstance(query.get("searchinfo"), dict) else {}
    total = max(len(items), int(info.get("totalhits") or 0))
    last_page = max(params["page"], math.ceil(total / RESULT_LIMIT))
    if payload.get("continue") and last_page == params["page"]:
        last_page += 1
    return {"wallpapers": items, "meta": {"current_page": params["page"], "last_page": last_page, "total": total}}


def search_cache_path(params: dict) -> Path:
    key = "\n".join(str(params[name]) for name in ("query", "collection", "sorting", "license", "page"))
    return plugin_cache_dir("wallpaper-search").path / (hashlib.sha256(key.encode()).hexdigest() + ".json")


def search_page(params: dict) -> dict:
    cache = search_cache_path(params)
    if params["collection"] != "omarchy":
        try:
            if time.time() - cache.stat().st_mtime <= SEARCH_CACHE_TTL_SECONDS:
                cached = json.loads(cache.read_bytes())
                if isinstance(cached, dict) and isinstance(cached.get("wallpapers"), list):
                    cached.setdefault("meta", {})["cached"] = True
                    return cached
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            pass
    try:
        if params["collection"] == "omarchy":
            result = search_omarchy(params)
        elif params["collection"] == "photography":
            result = search_commons(params)
        else:
            result = search_ocs(params)
        atomic_write(plugin_cache_dir("wallpaper-search"), cache.name, json.dumps(result, separators=(",", ":")).encode())
        return result
    except CatalogError:
        try:
            cached = json.loads(cache.read_bytes())
            if isinstance(cached, dict) and isinstance(cached.get("wallpapers"), list):
                cached.setdefault("meta", {})["stale"] = True
                return cached
            raise CatalogError("cached wallpaper response is invalid")
        except (OSError, json.JSONDecodeError, TypeError):
            raise


def image_signature(data: bytes) -> bool:
    return data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG\r\n\x1a\n") or (data.startswith(b"RIFF") and data[8:12] == b"WEBP")


def remote_image(url: str, directory: PluginDirectory, stem: str, maximum: int) -> Path:
    parsed = urlparse(url)
    extension = Path(parsed.path).suffix.lower()
    if extension not in IMAGE_EXTENSIONS:
        extension = ".jpg"
    destination = directory.path / (stem + extension)
    if destination.is_file() and not destination.is_symlink() and destination.stat().st_size > 0:
        return destination
    data = request_bytes(url, maximum)
    if not image_signature(data):
        raise CatalogError("wallpaper provider returned invalid image data")
    return atomic_write(directory, destination.name, data)


def local_thumbnail(item: dict) -> Path:
    root = omarchy_root()
    source = Path(item["path"]).resolve(strict=True)
    try:
        relative = source.relative_to(root).as_posix()
    except ValueError as error:
        raise CatalogError("refusing wallpaper outside the bundled Omarchy collection") from error
    parts = relative.split("/")
    if len(parts) != 3 or parts[1] != "backgrounds" or omarchy_id(relative) != item["id"]:
        raise CatalogError("invalid bundled Omarchy wallpaper")
    directory = plugin_cache_dir("wallpaper-thumbs")
    destination = directory.path / (item["id"] + ".png")
    if destination.is_file() and not destination.is_symlink() and destination.stat().st_mtime_ns >= source.stat().st_mtime_ns:
        return destination
    if shutil.which("magick"):
        temporary = directory.path / f".{item['id']}.{secrets.token_hex(8)}.png"
        try:
            completed = subprocess.run(
                ["magick", str(source), "-auto-orient", "-thumbnail", "960x540>", "-strip", str(temporary)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                timeout=20, check=False, text=True,
            )
            if completed.returncode != 0 or not temporary.is_file() or temporary.stat().st_size <= 0:
                raise CatalogError("could not generate a local wallpaper preview")
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
        return destination
    return atomic_write(directory, item["id"] + source.suffix.lower(), source.read_bytes())


def add_thumbnail(item: dict) -> dict:
    copy = dict(item)
    if item["id"].startswith("omarchy-"):
        copy["thumbnailPath"] = str(local_thumbnail(item))
    else:
        copy["thumbnailPath"] = str(remote_image(item["thumbURL"], plugin_cache_dir("wallpaper-thumbs"), item["id"], MAX_THUMB_BYTES))
    return copy


def merged_search(params: dict, pages: int) -> dict:
    requested = []
    with ThreadPoolExecutor(max_workers=min(3, pages)) as executor:
        futures = {}
        for offset in range(pages):
            page_params = dict(params)
            page_params["page"] += offset
            futures[executor.submit(search_page, page_params)] = offset
        for future in as_completed(futures):
            requested.append((futures[future], future.result()))
    requested.sort(key=lambda value: value[0])
    first = requested[0][1]
    seen = set()
    items = []
    for _, result in requested:
        for item in result.get("wallpapers", []):
            if item.get("id") not in seen:
                seen.add(item.get("id"))
                items.append(item)
    with ThreadPoolExecutor(max_workers=3) as executor:
        indexed = list(enumerate(items))
        futures = {executor.submit(add_thumbnail, item): index for index, item in indexed}
        thumbnails = {}
        for future in as_completed(futures):
            try:
                thumbnails[futures[future]] = future.result()
            except CatalogError:
                thumbnails[futures[future]] = items[futures[future]]
    meta = dict(first.get("meta", {}))
    meta["current_page"] = (params["page"] - 1) // pages + 1
    meta["last_page"] = max(1, math.ceil(max(result.get("meta", {}).get("last_page", 1) for _, result in requested) / pages))
    meta["total"] = max(result.get("meta", {}).get("total", 0) for _, result in requested)
    meta["cached"] = all(result.get("meta", {}).get("cached") is True for _, result in requested)
    meta["stale"] = any(result.get("meta", {}).get("stale") is True for _, result in requested)
    return {"wallpapers": [thumbnails[index] for index in range(len(items))], "meta": meta}


def lookup_ocs(item_id: str) -> dict:
    payload = request_json(f"{OCS_API_URL}/{quote(item_id)}?format=json")
    if payload.get("status") != "ok":
        raise CatalogError("OpenDesktop wallpaper lookup failed")
    data = payload.get("data")
    if isinstance(data, list):
        if len(data) != 1:
            raise CatalogError("OpenDesktop returned no unique wallpaper")
        data = data[0]
    if not isinstance(data, dict):
        raise CatalogError("OpenDesktop returned an invalid wallpaper")
    item = ocs_item(data, "community-abstract", "any")
    if not item or item["id"] != f"ocs-{item_id}":
        raise CatalogError("OpenDesktop item is not a free downloadable image")
    return item


def lookup_commons(item_id: str) -> dict:
    values = {
        "action": "query", "format": "json", "formatversion": "2", "pageids": item_id,
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "3840",
        "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl",
    }
    payload = request_json(API_URL + "?" + urlencode(values))
    query = payload.get("query") if isinstance(payload.get("query"), dict) else {}
    pages = query.get("pages") if isinstance(query.get("pages"), list) else []
    item = commons_item(pages[0], "any") if len(pages) == 1 and isinstance(pages[0], dict) else None
    if not item or item["id"] != f"commons-{item_id}":
        raise CatalogError("Commons page is not a supported open image")
    item["path"] = item["thumbURL"]
    return item


def download_wallpaper(value: str) -> Path:
    match = ID_PATTERN.fullmatch(value)
    if not match:
        raise CatalogError("invalid wallpaper id")
    provider, numeric_id = match.groups()
    directory = wallpaper_dir()
    if provider == "omarchy":
        items = {item["id"]: item for item in discover_omarchy()}
        item = items.get(value)
        if not item:
            raise CatalogError("bundled Omarchy wallpaper was not found")
        source = Path(item["path"]).resolve(strict=True)
        destination = directory.path / (value + source.suffix.lower())
        if not destination.is_file() or destination.is_symlink() or destination.stat().st_size <= 0:
            atomic_write(directory, destination.name, source.read_bytes())
    else:
        item = lookup_ocs(numeric_id) if provider == "ocs" else lookup_commons(numeric_id)
        destination = remote_image(item["path"], directory, value, MAX_IMAGE_BYTES)
    attribution = {
        "title": item["title"], "sourceURL": item["url"], "author": item["author"],
        "license": item["license"], "licenseURL": item["licenseURL"], "source": item["source"],
    }
    atomic_write(directory, destination.name + ".attribution.json", (json.dumps(attribution, indent=2) + "\n").encode(), 0o600)
    return destination


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(add_help=False)
    actions = value.add_mutually_exclusive_group(required=True)
    actions.add_argument("--wallpaper-thumbs", action="store_true")
    actions.add_argument("--wallpaper-download", metavar="ID")
    value.add_argument("--json", action="store_true")
    value.add_argument("--pages", type=int, default=1)
    value.add_argument("--page", type=int, default=1)
    value.add_argument("--collection", default="omarchy")
    value.add_argument("--sorting", default="featured")
    value.add_argument("--license", default="any")
    value.add_argument("query", nargs="?")
    return value


def main() -> int:
    args = parser().parse_args()
    try:
        if args.wallpaper_download:
            result = {"path": str(download_wallpaper(args.wallpaper_download))}
        else:
            result = merged_search(normalize(args), min(4, max(1, args.pages)))
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (CatalogError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": f"Wallpaper request failed: {clean_text(error)}"}, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
