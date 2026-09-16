#!/usr/bin/env python3
"""Install one exact, bundled theme snapshot through a data-only boundary."""

import gzip
import json
import os
import re
import subprocess
import sys
import tarfile
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
MAX_REF_ADVERTISEMENT_BYTES = 1024 * 1024
MAX_ARCHIVE_BYTES = MAX_IMAGE_TOTAL_BYTES + 8 * 1024 * 1024
MAX_ARCHIVE_EXPANDED_BYTES = 160 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 4096
MAX_ARCHIVE_PATH_BYTES = 4096
MAX_DOWNLOAD_BYTES = MAX_REF_ADVERTISEMENT_BYTES + MAX_ARCHIVE_BYTES
DOWNLOAD_SECONDS = 60
SOCKET_TIMEOUT_SECONDS = 10
TEMPORARY_FAILURE = 75
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


class GitHubRateLimitError(RuntimeError):
    """A public GitHub endpoint asked this unauthenticated client to wait."""


def github_rate_limited(error):
    if not isinstance(error, urllib.error.HTTPError) or error.code not in {403, 429}:
        return False
    headers = error.headers or {}
    remaining = str(headers.get("X-RateLimit-Remaining", "")).strip()
    reason = str(error.reason or "").casefold()
    return error.code == 429 or remaining == "0" or "rate limit" in reason


def normalize_repository(value):
    repository = str(value or "").strip().lower().removesuffix(".git").rstrip("/")
    return repository if SAFE_REPOSITORY.fullmatch(repository) else ""


def palette_value_allowed(key, value):
    if key not in ALLOWED_COLOR_KEYS or not isinstance(value, str):
        return False
    if key in {"mode", "theme_type"}:
        return value in {"dark", "light"}
    return bool(SAFE_COLOR_VALUE.fullmatch(value))


def flatten_palette(data):
    if not isinstance(data, dict):
        fail("Theme palette is not a TOML table")
    return {key: value for key, value in data.items() if palette_value_allowed(key, value)}


def legacy_color(table, key, fallback=""):
    value = table.get(key, fallback)
    if not isinstance(value, str):
        return ""
    match = re.fullmatch(r"(?:0x|#)?([0-9A-Fa-f]{6})", value)
    return f"#{match.group(1).lower()}" if match else ""


def legacy_table(colors, name):
    table = colors.get(name)
    return table if isinstance(table, dict) else {}


def legacy_color_tables(data):
    """The normal, bright, primary and selection tables of an Alacritty theme."""
    colors = data.get("colors") if isinstance(data, dict) else None
    if not isinstance(colors, dict):
        fail("Legacy theme has no [colors] table")
    if not isinstance(colors.get("normal"), dict):
        fail("Legacy theme has no [colors.normal] table")
    return tuple(legacy_table(colors, name) for name in ("normal", "bright", "primary", "selection"))


def alacritty_palette(data):
    normal, bright, primary, selection = legacy_color_tables(data)
    normal_values = [legacy_color(normal, name) for name in NORMAL_NAMES]
    if not all(normal_values):
        fail("Legacy theme is missing one or more normal colors")
    bright_values = [
        legacy_color(bright, name, normal_values[index]) for index, name in enumerate(NORMAL_NAMES)
    ]
    background = legacy_color(primary, "background", normal_values[0])
    foreground = legacy_color(primary, "foreground", normal_values[7])
    palette = {
        "accent": normal_values[4],
        "selection": legacy_color(selection, "background", foreground),
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


def copy_preview(snapshot, destination):
    """Bytes copied for preview.png, 0 when the theme has none."""
    try:
        preview = snapshot.blob("preview.png", MAX_IMAGE_BYTES)
    except RuntimeError as error:
        if str(error) != "Missing theme file: preview.png":
            raise
        return 0
    return copy_image(preview, "preview.png", destination / "preview.png")


def background_name(path):
    name = path.removeprefix("backgrounds/")
    return name if "/" not in name and SAFE_IMAGE_NAME.fullmatch(name) else ""


def copy_backgrounds(snapshot, entries, target, total):
    """Copy up to MAX_IMAGES safe backgrounds within the total byte budget; returns the count."""
    copied = 0
    for path in entries:
        if copied >= MAX_IMAGES:
            break
        name = background_name(path)
        if not name:
            continue
        data = snapshot.blob(path, min(MAX_IMAGE_BYTES, MAX_IMAGE_TOTAL_BYTES - total))
        total += copy_image(data, name, target / name)
        copied += 1
        if total > MAX_IMAGE_TOTAL_BYTES:
            fail("Theme images exceed the safe total size limit")
    return copied


def copy_images(snapshot, destination):
    total = copy_preview(snapshot, destination)
    entries = snapshot.backgrounds()
    if not entries:
        return
    target = destination / "backgrounds"
    target.mkdir(mode=0o700)
    if copy_backgrounds(snapshot, entries, target, total) == 0:
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

    def open(self, url, maximum):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in {"github.com", "codeload.github.com"}:
            fail("Theme download host is not allowed")
        maximum = min(maximum, self.remaining)
        if maximum < 0 or time.monotonic() >= self.deadline:
            fail("Theme download budget exhausted")
        response = self.open_response(url, parsed.netloc)
        try:
            length = declared_length(response, maximum)
        except RuntimeError:
            response.close()
            raise
        return response, maximum, length

    def open_response(self, url, host):
        timeout = min(SOCKET_TIMEOUT_SECONDS, self.deadline - time.monotonic())
        try:
            return self.opener.open(
                github_request(url, host), timeout=max(0.001, timeout)
            )
        except urllib.error.HTTPError as error:
            if github_rate_limited(error):
                error.close()
                raise GitHubRateLimitError("GitHub download rate limit reached") from None
            raise

    def chunks(self, response, maximum):
        received = 0
        while True:
            if time.monotonic() >= self.deadline:
                fail("Theme download timed out")
            chunk = response.read1(min(64 * 1024, maximum - received + 1))
            self.remaining -= len(chunk)
            received += len(chunk)
            if received > maximum:
                fail("Theme download exceeds its byte limit")
            if not chunk:
                break
            yield chunk

    def read(self, url, maximum):
        response, maximum, length = self.open(url, maximum)
        with response:
            result = b"".join(self.chunks(response, maximum))
            if length is not None and len(result) != length:
                fail("Theme download is incomplete")
            return result

    def download(self, url, maximum, destination):
        response, maximum, length = self.open(url, maximum)
        received = 0
        with response, destination.open("xb") as output:
            for chunk in self.chunks(response, maximum):
                output.write(chunk)
                received += len(chunk)
        if length is not None and received != length:
            fail("Theme download is incomplete")
        return received


def github_request(url, host):
    accept = (
        "application/x-git-upload-pack-advertisement"
        if host == "github.com"
        else "application/octet-stream"
    )
    return urllib.request.Request(url, headers={
        "Accept": accept,
        "Accept-Encoding": "identity",
        "User-Agent": "Omarchy-Theme-Manager",
    })


def declared_length(response, maximum):
    """The Content-Length as an int within the budget, or None when absent."""
    if response.status != 200:
        fail("Theme download did not return a complete response")
    if response.headers.get("Content-Encoding", "identity").lower() != "identity":
        fail("HTTP content encoding is not allowed")
    length = response.headers.get("Content-Length")
    if length is None:
        return None
    if not length.isdecimal() or int(length) > maximum:
        fail("Theme download exceeds its byte limit")
    return int(length)


class BoundedReader:
    """Bound decompressed archive bytes and check the shared deadline."""

    def __init__(self, stream, maximum, deadline):
        self.stream = stream
        self.maximum = maximum
        self.deadline = deadline
        self.received = 0

    def read(self, size=-1):
        if time.monotonic() >= self.deadline:
            fail("Theme archive processing timed out")
        remaining = self.maximum - self.received
        if remaining < 0:
            fail("Theme archive exceeds its expanded byte limit")
        maximum = remaining + 1
        if size < 0 or size > maximum:
            size = maximum
        data = self.stream.read(size)
        self.received += len(data)
        if self.received > self.maximum:
            fail("Theme archive exceeds its expanded byte limit")
        return data


def packet_lines(data):
    """Parse a complete Git pkt-line advertisement without accepting truncation."""

    offset = 0
    while offset < len(data):
        if len(data) - offset < 4 or not re.fullmatch(rb"[0-9a-fA-F]{4}", data[offset:offset + 4]):
            fail("Invalid Git reference advertisement")
        length = int(data[offset:offset + 4], 16)
        offset += 4
        if length == 0:
            yield b""
            continue
        if length < 4 or offset + length - 4 > len(data):
            fail("Incomplete Git reference advertisement")
        yield data[offset:offset + length - 4]
        offset += length - 4


def advertised_head(data):
    head = ""
    service_seen = False
    for packet in packet_lines(data):
        if packet == b"":
            continue
        if packet.startswith(b"# service="):
            if packet != b"# service=git-upload-pack\n" or service_seen:
                fail("Invalid Git reference service")
            service_seen = True
            continue
        reference = packet.rstrip(b"\n").split(b"\0", 1)[0]
        parts = reference.split(b" ", 1)
        if len(parts) != 2 or parts[1] != b"HEAD":
            continue
        candidate = parts[0].decode("ascii")
        if head or not SAFE_SHA.fullmatch(candidate):
            fail("Invalid Git HEAD identity")
        head = candidate
    if not service_seen or not head:
        fail("Downloaded theme does not resolve to an exact commit")
    return head


class Snapshot:
    """Read selected regular files from one bounded, commit-pinned archive."""

    def __init__(self, repository, storage):
        self.downloader = Downloader()
        self.repository = repository.removeprefix("https://github.com/")
        self.name = self.repository.rsplit("/", 1)[-1]
        refs_url = f"https://github.com/{self.repository}.git/info/refs?service=git-upload-pack"
        self.commit = advertised_head(self.downloader.read(refs_url, MAX_REF_ADVERTISEMENT_BYTES))
        storage.mkdir(mode=0o700)
        archive = storage / "snapshot.tar.gz"
        archive_url = f"https://codeload.github.com/{self.repository}/tar.gz/{self.commit}"
        self.downloader.download(archive_url, MAX_ARCHIVE_BYTES, archive)
        self.entries = self.inventory(archive)
        self.extract(archive, storage)

    def walk(self, archive, visitor):
        expected_root = f"{self.name}-{self.commit}"
        count = 0
        declared = 0
        with archive.open("rb") as compressed:
            with gzip.GzipFile(fileobj=compressed, mode="rb") as expanded:
                bounded = BoundedReader(expanded, MAX_ARCHIVE_EXPANDED_BYTES, self.downloader.deadline)
                with tarfile.open(fileobj=bounded, mode="r|") as stream:
                    for member in stream:
                        count += 1
                        if count > MAX_ARCHIVE_MEMBERS:
                            fail("Theme archive contains too many entries")
                        if member.size < 0:
                            fail("Theme archive contains an invalid entry size")
                        declared += member.size
                        if declared > MAX_ARCHIVE_EXPANDED_BYTES:
                            fail("Theme archive exceeds its expanded byte limit")
                        if len(member.name.encode("utf-8")) > MAX_ARCHIVE_PATH_BYTES:
                            fail("Theme archive path is too long")
                        parts = member.name.rstrip("/").split("/")
                        if (
                            not parts
                            or parts[0].casefold() != expected_root.casefold()
                            or any(part in {"", ".", ".."} for part in parts)
                        ):
                            fail("Theme archive contains an invalid path")
                        relative = "/".join(parts[1:])
                        if not relative:
                            if not member.isdir():
                                fail("Theme archive root is not a directory")
                            continue
                        visitor(stream, member, relative)
                while bounded.read(64 * 1024):
                    pass

    def inventory(self, archive):
        entries = {}

        def inspect(_stream, member, relative):
            root_file = relative in {"colors.toml", "alacritty.toml", "preview.png"}
            background = (
                relative.startswith("backgrounds/")
                and relative.count("/") == 1
                and SAFE_IMAGE_NAME.fullmatch(relative.removeprefix("backgrounds/"))
            )
            if not root_file and not background:
                return
            if background and not member.isfile():
                return
            if relative in entries:
                fail(f"Duplicate theme archive entry: {relative}")
            if not member.isfile():
                fail(f"Theme path is not a regular file: {relative}")
            entries[relative] = {"size": member.size}

        self.walk(archive, inspect)
        for path in ("colors.toml", "alacritty.toml"):
            if path in entries and entries[path]["size"] > MAX_PALETTE_BYTES:
                fail(f"Oversized theme file: {path}")
        if "preview.png" in entries and entries["preview.png"]["size"] > MAX_IMAGE_BYTES:
            fail("Oversized theme file: preview.png")
        backgrounds = sorted(
            (path for path in entries if path.startswith("backgrounds/")),
            key=str.casefold,
        )
        selected = set(backgrounds[:MAX_IMAGES])
        for path in backgrounds[MAX_IMAGES:]:
            del entries[path]
        image_total = entries.get("preview.png", {}).get("size", 0)
        for path in selected:
            size = entries[path]["size"]
            if size > MAX_IMAGE_BYTES:
                fail(f"Oversized theme file: {path}")
            image_total += size
        if image_total > MAX_IMAGE_TOTAL_BYTES:
            fail("Theme images exceed the safe total size limit")
        return entries

    def extract(self, archive, storage):
        pending = set(self.entries)
        counter = 0

        def copy_selected(stream, member, relative):
            nonlocal counter
            if relative not in pending:
                return
            if not member.isfile() or member.size != self.entries[relative]["size"]:
                fail(f"Theme archive entry changed while reading: {relative}")
            source = stream.extractfile(member)
            if source is None:
                fail(f"Theme archive entry cannot be read: {relative}")
            destination = storage / f"entry-{counter}"
            counter += 1
            remaining = member.size
            with source, destination.open("xb") as output:
                while remaining:
                    chunk = source.read(min(64 * 1024, remaining))
                    if not chunk:
                        fail(f"Theme archive entry is incomplete: {relative}")
                    output.write(chunk)
                    remaining -= len(chunk)
                if source.read(1):
                    fail(f"Theme archive entry exceeds its declared size: {relative}")
            os.chmod(destination, 0o600)
            self.entries[relative]["file"] = destination
            pending.remove(relative)

        self.walk(archive, copy_selected)
        if pending:
            fail("Theme archive changed between validation and extraction")

    def backgrounds(self):
        return sorted(
            (path for path in self.entries if path.startswith("backgrounds/")),
            key=str.casefold,
        )

    def blob(self, path, maximum):
        entry = self.entries.get(path)
        if entry is None:
            fail(f"Missing theme file: {path}")
        size = entry["size"]
        if size > maximum:
            fail(f"Oversized theme file: {path}")
        with entry["file"].open("rb") as source:
            data = source.read(maximum + 1)
        if len(data) != size:
            fail(f"Theme archive entry changed after extraction: {path}")
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


def install_slug(repository):
    slug = repository.rsplit("/", 1)[-1]
    slug = re.sub(r"^omarchy-", "", slug)
    return re.sub(r"-theme$", "", slug)


def install(repository, slug):
    with tempfile.TemporaryDirectory(prefix="omarchy-theme-manager-") as temporary:
        root = Path(temporary)
        safe = root / f"omarchy-{slug}-theme"
        safe.mkdir(mode=0o700)
        snapshot = Snapshot(repository, root / "snapshot")
        write_palette(safe / "colors.toml", load_palette(snapshot))
        copy_images(snapshot, safe)
        initialize_safe_repository(safe, repository, snapshot.commit)
        run(["omarchy", "theme", "install", safe.as_uri()])


INSTALL_ERRORS = (
    OSError,
    RuntimeError,
    UnicodeError,
    ValueError,
    tomllib.TOMLDecodeError,
    subprocess.SubprocessError,
    urllib.error.URLError,
)


def main():
    if len(sys.argv) != 2:
        print("Usage: install-theme.py <github-repository-url>", file=sys.stderr)
        return 2
    repository = normalize_repository(sys.argv[1])
    if not repository:
        print("Theme repository is not a normalized GitHub URL", file=sys.stderr)
        return 2
    slug = install_slug(repository)
    if not SAFE_SLUG.fullmatch(slug):
        print("Theme repository does not produce a safe install name", file=sys.stderr)
        return 1
    try:
        install(repository, slug)
    except GitHubRateLimitError as error:
        print(f"Theme install paused: {error}; retry later", file=sys.stderr)
        return TEMPORARY_FAILURE
    except urllib.error.HTTPError as error:
        try:
            print(f"Theme install failed: {error}", file=sys.stderr)
        finally:
            error.close()
        return 1
    except INSTALL_ERRORS as error:
        print(f"Theme install failed: {error}", file=sys.stderr)
        return 1
    print(slug)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
