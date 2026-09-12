#!/usr/bin/env python3
"""Fetch and render bounded theme metadata through a no-follow cache fd."""

import json
import math
import os
import re
import secrets
import stat
import subprocess
import sys
import time
from datetime import datetime


CATALOG_URL = "https://raw.githubusercontent.com/limehawk/omarchy-theme-website/main/src/data/themes-data.json"
OFFICIAL_URL = "https://omarchy.org/themes/"
CATALOG_MAX_BYTES = 8 * 1024 * 1024
OFFICIAL_MAX_BYTES = 2 * 1024 * 1024
OUTPUT_MAX_BYTES = 4 * 1024 * 1024
CATALOG_MAX_ITEMS = 2000
OFFICIAL_MAX_ITEMS = 1000
OFFICIAL_REPOSITORY = re.compile(
    r'href="(https://github\.com/[A-Za-z0-9-]{1,39}/[A-Za-z0-9_.-]{1,100})'
)


def fail(message):
    raise RuntimeError(message)


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


def open_cache_directory():
    home = os.environ.get("HOME", "")
    cache_home = os.environ.get("XDG_CACHE_HOME", os.path.join(home, ".cache"))
    if not home or not os.path.isabs(home) or not os.path.isabs(cache_home):
        fail("HOME and XDG_CACHE_HOME must be absolute")

    home_normal = os.path.normpath(home)
    cache_normal = os.path.normpath(cache_home)
    if os.path.commonpath([home_normal, cache_normal]) != home_normal:
        fail("XDG_CACHE_HOME must be inside HOME")

    directory_fds = [open_owned_directory(home_normal, "HOME")]
    parent_fd = directory_fds[0]
    relative_cache = os.path.relpath(cache_normal, home_normal)
    if relative_cache != ".":
        for component in relative_cache.split(os.sep):
            if component in {"", ".", ".."}:
                fail("Invalid cache directory")
            parent_fd = open_or_create_child(parent_fd, component, "cache directory")
            directory_fds.append(parent_fd)

    cache_fd = open_or_create_child(parent_fd, "omarchy-theme-manager", "theme catalog cache")
    directory_fds.append(cache_fd)
    return cache_fd, directory_fds


def read_fd(fd, maximum):
    os.lseek(fd, 0, os.SEEK_SET)
    chunks = []
    total = 0
    while True:
        chunk = os.read(fd, min(1024 * 1024, maximum + 1 - total))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > maximum:
            fail("Downloaded cache exceeds the safe size limit")


def parse_json(data):
    return json.loads(
        data.decode("utf-8"),
        parse_constant=lambda value: fail(f"Invalid JSON number: {value}"),
    )


def validate_catalog(data):
    payload = parse_json(data)
    if not isinstance(payload, list) or not 0 < len(payload) <= CATALOG_MAX_ITEMS:
        fail("Theme catalog has an invalid item count")
    for entry in payload:
        if not isinstance(entry, dict):
            fail("Theme catalog entry is not an object")
        name = entry.get("name")
        repository = entry.get("github_url")
        if not isinstance(name, str) or len(name) > 120:
            fail("Theme catalog entry has an invalid name")
        if not isinstance(repository, str) or len(repository) > 512:
            fail("Theme catalog entry has an invalid repository URL")
    return payload


def validate_official(data):
    page = data.decode("utf-8")
    repositories = OFFICIAL_REPOSITORY.findall(page)
    if not 20 < len(repositories) <= OFFICIAL_MAX_ITEMS:
        fail("Official theme page has an invalid repository count")
    return repositories


def open_cached_file(cache_fd, name):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(name, flags, dir_fd=cache_fd)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        os.close(fd)
        fail(f"Unsafe cache entry: {name}")
    return fd


def load_cached(cache_fd, name, maximum, validator):
    fd = open_cached_file(cache_fd, name)
    try:
        info = os.fstat(fd)
        return validator(read_fd(fd, maximum)), info.st_mtime
    finally:
        os.close(fd)


def create_staging_file(cache_fd):
    flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
    for _attempt in range(100):
        name = f".download-{os.getpid()}-{secrets.token_hex(8)}.tmp"
        try:
            return name, os.open(name, flags, 0o600, dir_fd=cache_fd)
        except FileExistsError:
            continue
    fail("Could not create an exclusive cache staging file")


def download(cache_fd, name, url, maximum, validator):
    temporary_name, temporary_fd = create_staging_file(cache_fd)
    try:
        command = [
            "curl",
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--proto",
            "=https",
            "--max-filesize",
            str(maximum),
            "--connect-timeout",
            "10",
            "--max-time",
            "45",
            "--output",
            f"/proc/self/fd/{temporary_fd}",
            url,
        ]
        result = subprocess.run(command, pass_fds=(temporary_fd,), check=False)
        if result.returncode != 0:
            fail(f"Download failed: {url}")
        value = validator(read_fd(temporary_fd, maximum))
        os.fsync(temporary_fd)
        os.replace(
            temporary_name,
            name,
            src_dir_fd=cache_fd,
            dst_dir_fd=cache_fd,
        )
        temporary_name = ""
        os.fsync(cache_fd)
        return value
    finally:
        os.close(temporary_fd)
        if temporary_name:
            try:
                os.unlink(temporary_name, dir_fd=cache_fd)
            except FileNotFoundError:
                pass


def refresh(cache_fd, name, url, maximum, validator, max_age, force):
    cached = None
    modified = 0
    try:
        cached, modified = load_cached(cache_fd, name, maximum, validator)
    except (OSError, RuntimeError, UnicodeError, json.JSONDecodeError):
        pass

    if not force and cached is not None and time.time() - modified < max_age:
        return cached

    try:
        return download(cache_fd, name, url, maximum, validator)
    except (OSError, RuntimeError, UnicodeError, json.JSONDecodeError):
        if cached is None:
            raise
        print("Theme catalog refresh failed; using cached data.", file=sys.stderr)
        return cached


def bounded_string(value, maximum):
    return value[:maximum] if isinstance(value, str) else ""


def bounded_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return value if math.isfinite(value) else 0


def render(catalog, official_repositories):
    deduplicated = {}
    for repository in official_repositories:
        normalized = repository.removesuffix(".git").rstrip("/")
        if normalized == "https://github.com/omacom-io/omarchy-site":
            continue
        deduplicated.setdefault(normalized.casefold(), normalized)

    themes = []
    for entry in catalog[:CATALOG_MAX_ITEMS]:
        if entry.get("is_builtin") == 1:
            continue
        themes.append(
            {
                "name": bounded_string(entry.get("name"), 120),
                "repositoryUrl": bounded_string(
                    entry.get("canonical_github_url") or entry.get("github_url"), 512
                ),
                "owner": bounded_string(entry.get("github_owner"), 80),
                "description": bounded_string(entry.get("description"), 500),
                "stars": bounded_number(entry.get("stars")),
                "apps": bounded_string(entry.get("apps_json"), 4096),
                "securityWarnings": bounded_string(entry.get("security_warnings"), 8192),
                "previewUrl": bounded_string(entry.get("preview_url"), 512),
            }
        )

    output = {
        "sourceUrl": "https://omarchytheme.com/",
        "fetchedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
        "officialRepositories": sorted(deduplicated.values(), key=str.casefold)[
            :OFFICIAL_MAX_ITEMS
        ],
        "themes": themes,
    }
    encoded = json.dumps(output, ensure_ascii=False, separators=(",", ":")).encode()
    if len(encoded) > OUTPUT_MAX_BYTES:
        fail("Theme catalog output exceeds the safe size limit")
    return encoded


def main():
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] != "--refresh"):
        print("Usage: catalog-cache.py [--refresh]", file=sys.stderr)
        return 2
    raw_max_age = os.environ.get("OMARCHY_THEME_CATALOG_MAX_AGE", "21600")
    if not raw_max_age.isdigit():
        print("OMARCHY_THEME_CATALOG_MAX_AGE must be a non-negative integer.", file=sys.stderr)
        return 2

    directory_fds = []
    try:
        cache_fd, directory_fds = open_cache_directory()
        force = len(sys.argv) == 2
        catalog = refresh(
            cache_fd,
            "themes-data.json",
            CATALOG_URL,
            CATALOG_MAX_BYTES,
            validate_catalog,
            int(raw_max_age),
            force,
        )
        official = refresh(
            cache_fd,
            "official-themes.html",
            OFFICIAL_URL,
            OFFICIAL_MAX_BYTES,
            validate_official,
            int(raw_max_age),
            force,
        )
        sys.stdout.buffer.write(render(catalog, official) + b"\n")
        return 0
    except (OSError, RuntimeError, UnicodeError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        for fd in reversed(directory_fds):
            os.close(fd)


if __name__ == "__main__":
    raise SystemExit(main())
