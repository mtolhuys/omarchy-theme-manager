#!/usr/bin/env python3
"""Install one exact, bundled theme snapshot through a data-only boundary."""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


MAX_PALETTE_BYTES = 64 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_IMAGE_TOTAL_BYTES = 80 * 1024 * 1024
MAX_IMAGES = 16
MAX_TREE_LIST_BYTES = 1024 * 1024
MAX_COMMIT_BYTES = 64 * 1024
MAX_DOWNLOAD_BYTES = MAX_IMAGE_TOTAL_BYTES + 2 * MAX_TREE_LIST_BYTES + MAX_COMMIT_BYTES + MAX_PALETTE_BYTES
DOWNLOAD_SECONDS = 60
SOCKET_TIMEOUT_SECONDS = 10
SAFE_SHA = re.compile(r"^[0-9a-f]{40}$")
SAFE_COLOR_VALUE = re.compile(r"^[A-Za-z0-9#(),._+/% -]{1,128}$")
SAFE_REPOSITORY = re.compile(
    r"^https://github\.com/([a-z0-9-]{1,39})/([a-z0-9_.-]{1,100})$"
)
SAFE_SLUG = re.compile(r"^[a-z0-9][a-z0-9._+-]*$")
SAFE_IMAGE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ +()-]{0,180}\.(?:png|jpe?g|gif|webp|bmp)$", re.IGNORECASE)
ALLOWED_COLOR_KEYS = {
    "mode",
    "theme_type",
    "accent",
    "selection",
    "selection_background",
    "selection_foreground",
    "background",
    "dark_background",
    "darker_background",
    "lighter_background",
    "foreground",
    "dark_foreground",
    "light_foreground",
    "bright_foreground",
    "cursor",
    "red",
    "green",
    "yellow",
    "orange",
    "blue",
    "magenta",
    "purple",
    "cyan",
    "brown",
    "bright_red",
    "bright_green",
    "bright_yellow",
    "bright_blue",
    "bright_magenta",
    "bright_purple",
    "bright_cyan",
    "bg",
    "dark_bg",
    "darker_bg",
    "lighter_bg",
    "fg",
    "dark_fg",
    "light_fg",
    "bright_fg",
    *(f"color{index}" for index in range(16)),
}
NORMAL_NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")


def fail(message):
    raise RuntimeError(message)


def normalize_repository(value):
    repository = str(value or "").strip().lower().removesuffix(".git").rstrip("/")
    return repository if SAFE_REPOSITORY.fullmatch(repository) else ""


def flatten_palette(data):
    if not isinstance(data, dict):
        fail("Theme palette is not a TOML table")
    palette = {}
    for key, value in data.items():
        if key not in ALLOWED_COLOR_KEYS or not isinstance(value, str):
            continue
        if key in {"mode", "theme_type"}:
            if value not in {"dark", "light"}:
                continue
        elif not SAFE_COLOR_VALUE.fullmatch(value):
            continue
        palette[key] = value
    return palette


def alacritty_palette(data):
    colors = data.get("colors") if isinstance(data, dict) else None
    if not isinstance(colors, dict):
        fail("Legacy theme has no [colors] table")
    normal = colors.get("normal")
    bright = colors.get("bright")
    primary = colors.get("primary")
    selection = colors.get("selection")
    if not isinstance(normal, dict):
        fail("Legacy theme has no [colors.normal] table")
    bright = bright if isinstance(bright, dict) else {}
    primary = primary if isinstance(primary, dict) else {}
    selection = selection if isinstance(selection, dict) else {}

    def color(table, key, fallback=""):
        value = table.get(key, fallback)
        if not isinstance(value, str):
            return ""
        match = re.fullmatch(r"(?:0x|#)?([0-9A-Fa-f]{6})", value)
        return f"#{match.group(1).lower()}" if match else ""

    normal_values = [color(normal, name) for name in NORMAL_NAMES]
    if not all(normal_values):
        fail("Legacy theme is missing one or more normal colors")
    bright_values = [color(bright, name, normal_values[index]) for index, name in enumerate(NORMAL_NAMES)]
    background = color(primary, "background", normal_values[0])
    foreground = color(primary, "foreground", normal_values[7])
    palette = {
        "accent": normal_values[4],
        "selection": color(selection, "background", foreground),
        "background": background,
        "foreground": foreground,
    }
    for index, value in enumerate(normal_values + bright_values):
        palette[f"color{index}"] = value
    return palette


def load_palette(snapshot):
    try:
        raw = snapshot.blob("colors.toml", MAX_PALETTE_BYTES)
        palette = flatten_palette(tomllib.loads(raw.decode("utf-8")))
    except RuntimeError as error:
        if str(error) != "Missing theme file: colors.toml":
            raise
        raw = snapshot.blob("alacritty.toml", MAX_PALETTE_BYTES)
        palette = alacritty_palette(tomllib.loads(raw.decode("utf-8")))
    required_semantic = {"background", "foreground", "red", "green", "yellow", "blue", "magenta", "cyan"}
    has_semantic = required_semantic.issubset(palette)
    has_ansi = all(f"color{index}" in palette for index in range(8))
    if not has_semantic and not has_ansi:
        fail("Theme palette does not contain a complete base color set")
    return palette


def write_palette(path, palette):
    preferred = ["mode", "theme_type", "accent", "selection", "selection_background", "selection_foreground"]
    preferred += [
        "background", "dark_background", "darker_background", "lighter_background",
        "foreground", "dark_foreground", "light_foreground", "bright_foreground", "cursor",
        "red", "green", "yellow", "orange", "blue", "magenta", "purple", "cyan", "brown",
        "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta",
        "bright_purple", "bright_cyan",
    ]
    preferred += [f"color{index}" for index in range(16)]
    preferred += ["bg", "dark_bg", "darker_bg", "lighter_bg", "fg", "dark_fg", "light_fg", "bright_fg"]
    lines = [f'{key} = {json.dumps(palette[key])}' for key in preferred if key in palette]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def image_kind(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "gif"
    if len(data) >= 12 and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    if data.startswith(b"BM"):
        return "bmp"
    return ""


def copy_image(data, name, destination):
    kind = image_kind(data)
    if not kind:
        fail(f"Unsupported image data: {name}")
    destination.write_bytes(data)
    os.chmod(destination, 0o600)
    return len(data)


def copy_images(snapshot, destination):
    total = 0
    copied = 0
    try:
        preview = snapshot.blob("preview.png", MAX_IMAGE_BYTES)
        total += copy_image(preview, "preview.png", destination / "preview.png")
    except RuntimeError as error:
        if str(error) != "Missing theme file: preview.png":
            raise

    entries = snapshot.backgrounds()
    if not entries:
        return
    target = destination / "backgrounds"
    target.mkdir(mode=0o700)
    for path in entries:
        if copied >= MAX_IMAGES:
            break
        name = path.removeprefix("backgrounds/")
        if "/" in name or not SAFE_IMAGE_NAME.fullmatch(name):
            continue
        remaining = MAX_IMAGE_TOTAL_BYTES - total
        data = snapshot.blob(path, min(MAX_IMAGE_BYTES, remaining))
        size = copy_image(data, name, target / name)
        total += size
        copied += 1
        if total > MAX_IMAGE_TOTAL_BYTES:
            fail("Theme images exceed the safe total size limit")
    if copied == 0:
        target.rmdir()


def git_environment():
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    environment["GIT_TERMINAL_PROMPT"] = "0"
    return environment


def run(command, **kwargs):
    check = kwargs.pop("check", True)
    timeout = kwargs.pop("timeout", 60)
    return subprocess.run(
        command,
        check=check,
        text=True,
        timeout=timeout,
        env=git_environment(),
        **kwargs,
    )


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        fail("Theme download redirects are not allowed")


class Downloader:
    """Bound bytes while reading, including chunked responses without a length."""

    def __init__(self):
        self.remaining = MAX_DOWNLOAD_BYTES
        self.deadline = time.monotonic() + DOWNLOAD_SECONDS
        self.opener = urllib.request.build_opener(NoRedirects())

    def read(self, url, maximum):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in {"api.github.com", "raw.githubusercontent.com"}:
            fail("Theme download host is not allowed")
        maximum = min(maximum, self.remaining)
        if maximum < 0 or time.monotonic() >= self.deadline:
            fail("Theme download budget exhausted")
        request = urllib.request.Request(url, headers={
            "Accept": "application/vnd.github+json" if parsed.netloc == "api.github.com" else "application/octet-stream",
            "Accept-Encoding": "identity",
            "User-Agent": "Omarchy-Theme-Manager",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        timeout = min(SOCKET_TIMEOUT_SECONDS, self.deadline - time.monotonic())
        with self.opener.open(request, timeout=max(0.001, timeout)) as response:
            if response.status != 200:
                fail("Theme download did not return a complete response")
            if response.headers.get("Content-Encoding", "identity").lower() != "identity":
                fail("Compressed theme responses are not allowed")
            length = response.headers.get("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > maximum):
                fail("Theme download exceeds its byte limit")
            result = bytearray()
            while True:
                if time.monotonic() >= self.deadline:
                    fail("Theme download timed out")
                # read1 returns available bytes rather than waiting to fill a
                # chunk, so trickled responses still reach the deadline check.
                chunk = response.read1(min(64 * 1024, maximum - len(result) + 1))
                self.remaining -= len(chunk)
                if len(result) + len(chunk) > maximum:
                    fail("Theme download exceeds its byte limit")
                if not chunk:
                    break
                result.extend(chunk)
            if length is not None and len(result) != int(length):
                fail("Theme download is incomplete")
            return bytes(result)


class Snapshot:
    """Read only two nonrecursive trees and selected blobs at one commit."""

    def __init__(self, repository):
        self.downloader = Downloader()
        self.repository = repository.removeprefix("https://github.com/")
        self.api = f"https://api.github.com/repos/{self.repository}"
        commits = self.document(f"{self.api}/commits?per_page=1", MAX_COMMIT_BYTES)
        if not isinstance(commits, list) or len(commits) != 1 or not isinstance(commits[0], dict):
            fail("Downloaded theme does not resolve to an exact commit")
        latest = commits[0]
        self.commit = latest.get("sha")
        if not isinstance(self.commit, str) or not SAFE_SHA.fullmatch(self.commit):
            fail("Downloaded theme does not resolve to an exact commit")
        details = latest.get("commit")
        tree = details.get("tree") if isinstance(details, dict) else None
        self.entries = self.tree(tree.get("sha") if isinstance(tree, dict) else None)
        self.background_entries = {}

    def document(self, url, maximum):
        return json.loads(self.downloader.read(url, maximum))

    def tree(self, sha):
        if not isinstance(sha, str) or not SAFE_SHA.fullmatch(sha):
            fail("Invalid theme tree identity")
        document = self.document(f"{self.api}/git/trees/{sha}", MAX_TREE_LIST_BYTES)
        if not isinstance(document, dict) or document.get("sha") != sha or document.get("truncated") is not False:
            fail("Theme tree is incomplete")
        entries = document.get("tree")
        if not isinstance(entries, list):
            fail("Invalid theme tree entries")
        result = {}
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
                fail("Invalid theme tree entry")
            path = entry["path"]
            if path in result:
                fail("Duplicate theme tree entry")
            result[path] = entry
        return result

    def backgrounds(self):
        entry = self.entries.get("backgrounds")
        if entry is None:
            return []
        if entry.get("mode") != "040000" or entry.get("type") != "tree":
            fail("Theme backgrounds path is not a directory")
        entries = self.tree(entry.get("sha"))
        self.background_entries = {
            f"backgrounds/{path}": entry for path, entry in entries.items()
            if "/" not in path and SAFE_IMAGE_NAME.fullmatch(path)
            and entry.get("mode") == "100644" and entry.get("type") == "blob"
        }
        return sorted(self.background_entries, key=str.casefold)

    def blob(self, path, maximum):
        entry = self.background_entries.get(path) if path.startswith("backgrounds/") else self.entries.get(path)
        if entry is None:
            fail(f"Missing theme file: {path}")
        if entry.get("mode") != "100644" or entry.get("type") != "blob":
            fail(f"Theme path is not a regular file: {path}")
        size = entry.get("size")
        sha = entry.get("sha")
        if type(size) is not int or size < 0 or size > maximum:
            fail(f"Oversized theme file: {path}")
        if not isinstance(sha, str) or not SAFE_SHA.fullmatch(sha):
            fail(f"Invalid theme file identity: {path}")
        quoted = urllib.parse.quote(path, safe="/")
        url = f"https://raw.githubusercontent.com/{self.repository}/{self.commit}/{quoted}"
        data = self.downloader.read(url, size)
        digest = hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()
        if len(data) != size or digest != sha:
            fail(f"Theme file changed while reading: {path}")
        return data


def initialize_safe_repository(path, upstream, commit):
    (path / "SOURCE.md").write_text(
        f"Sanitized by Omarchy Theme Manager from {upstream}/commit/{commit}.\n",
        encoding="utf-8",
    )
    run(["git", "-c", "init.defaultBranch=main", "init", "--quiet", str(path)])
    run(["git", "-C", str(path), "config", "user.name", "Omarchy Theme Manager"])
    run(["git", "-C", str(path), "config", "user.email", "theme-manager@localhost"])
    run(["git", "-C", str(path), "add", "--all"])
    run(["git", "-C", str(path), "commit", "--quiet", "-m", f"Sanitized snapshot {commit}"])


def main():
    if len(sys.argv) != 2:
        print("Usage: install-theme.py <github-repository-url>", file=sys.stderr)
        return 2
    repository = normalize_repository(sys.argv[1])
    if not repository:
        print("Theme repository is not a normalized GitHub URL", file=sys.stderr)
        return 2

    slug = repository.rsplit("/", 1)[-1]
    slug = re.sub(r"^omarchy-", "", slug)
    slug = re.sub(r"-theme$", "", slug)
    if not SAFE_SLUG.fullmatch(slug):
        print("Theme repository does not produce a safe install name", file=sys.stderr)
        return 1

    try:
        with tempfile.TemporaryDirectory(prefix="omarchy-theme-manager-") as temporary:
            root = Path(temporary)
            safe = root / f"omarchy-{slug}-theme"
            safe.mkdir(mode=0o700)
            snapshot = Snapshot(repository)
            write_palette(safe / "colors.toml", load_palette(snapshot))
            copy_images(snapshot, safe)
            initialize_safe_repository(safe, repository, snapshot.commit)
            run(["omarchy", "theme", "install", safe.as_uri()])
        print(slug)
        return 0
    except (OSError, RuntimeError, UnicodeError, ValueError, tomllib.TOMLDecodeError, subprocess.SubprocessError, urllib.error.URLError) as error:
        print(f"Theme install failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
