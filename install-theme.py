#!/usr/bin/env python3
"""Install one exact, bundled theme snapshot through a data-only boundary."""

import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


MAX_PALETTE_BYTES = 64 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_IMAGE_TOTAL_BYTES = 80 * 1024 * 1024
MAX_IMAGES = 16
MAX_TREE_LIST_BYTES = 1024 * 1024
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


def load_palette(repository, commit):
    try:
        raw = git_blob(repository, commit, "colors.toml", MAX_PALETTE_BYTES)
        palette = flatten_palette(tomllib.loads(raw.decode("utf-8")))
    except RuntimeError as error:
        if str(error) != "Missing theme file: colors.toml":
            raise
        raw = git_blob(repository, commit, "alacritty.toml", MAX_PALETTE_BYTES)
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


def copy_images(repository, commit, destination):
    total = 0
    copied = 0
    try:
        preview = git_blob(repository, commit, "preview.png", MAX_IMAGE_BYTES)
        total += copy_image(preview, "preview.png", destination / "preview.png")
    except RuntimeError as error:
        if str(error) != "Missing theme file: preview.png":
            raise

    entries = git_tree_files(repository, commit, "backgrounds")
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
        data = git_blob(repository, commit, path, MAX_IMAGE_BYTES)
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


def clone_snapshot(repository, destination):
    run([
        "git", "-c", "transfer.fsckObjects=true", "-c", "fetch.fsckObjects=true",
        "clone", "--quiet", "--bare", "--filter=blob:none", "--depth=1", "--no-tags",
        "--single-branch", "--",
        repository, str(destination),
    ])
    actual = run(
        ["git", "-C", str(destination), "rev-parse", "HEAD"],
        capture_output=True,
    ).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", actual):
        fail("Downloaded theme does not resolve to an exact commit")
    return actual


def git_blob(repository, commit, path, maximum):
    object_name = f"{commit}:{path}"
    kind = run(
        ["git", "-C", str(repository), "cat-file", "-t", object_name],
        capture_output=True,
        check=False,
    )
    if kind.returncode != 0:
        fail(f"Missing theme file: {path}")
    if kind.stdout.strip() != "blob":
        fail(f"Theme path is not a regular file: {path}")
    size_result = run(
        ["git", "-C", str(repository), "cat-file", "-s", object_name],
        capture_output=True,
    )
    try:
        size = int(size_result.stdout.strip())
    except ValueError:
        fail(f"Could not determine theme file size: {path}")
    if size < 0 or size > maximum:
        fail(f"Oversized theme file: {path}")
    result = subprocess.run(
        ["git", "-C", str(repository), "cat-file", "blob", object_name],
        check=True,
        capture_output=True,
        timeout=60,
        env=git_environment(),
    )
    if len(result.stdout) != size:
        fail(f"Theme file changed while reading: {path}")
    return result.stdout


def git_tree_files(repository, commit, directory):
    result = run(
        ["git", "-C", str(repository), "ls-tree", "-z", f"{commit}:{directory}"],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    if len(result.stdout.encode("utf-8")) > MAX_TREE_LIST_BYTES:
        fail("Theme background tree is too large")
    paths = []
    for record in result.stdout.split("\0"):
        if not record:
            continue
        metadata, separator, path = record.partition("\t")
        fields = metadata.split()
        if separator and len(fields) == 3 and fields[0] == "100644" and fields[1] == "blob":
            paths.append(f"{directory}/{path}")
    return sorted(paths, key=str.casefold)


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
            source = root / "source.git"
            safe = root / f"omarchy-{slug}-theme"
            safe.mkdir(mode=0o700)
            commit = clone_snapshot(repository, source)
            write_palette(safe / "colors.toml", load_palette(source, commit))
            copy_images(source, commit, safe)
            initialize_safe_repository(safe, repository, commit)
            run(["omarchy", "theme", "install", safe.as_uri()])
        print(slug)
        return 0
    except (OSError, RuntimeError, UnicodeError, ValueError, tomllib.TOMLDecodeError, subprocess.CalledProcessError) as error:
        print(f"Theme install failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
