#!/usr/bin/env python3
"""Publish a wallpaper without following or replacing destination links."""

import errno
import os
import secrets
import stat
import sys


ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}
MIN_WALLPAPER_BYTES = 4096


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


def write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            fail("Could not write wallpaper")
        view = view[written:]


def copy_source(source_fd, destination_fd):
    while True:
        block = os.read(source_fd, 1024 * 1024)
        if not block:
            return
        write_all(destination_fd, block)


def candidate_names(base, name_max):
    stem, extension = os.path.splitext(base)
    for index in range(1000):
        suffix = "" if index == 0 else f"-{index + 1}"
        max_stem = name_max - len(extension.encode()) - len(suffix.encode())
        if max_stem < 1:
            fail("Wallpaper filename is too long")
        trimmed = stem.encode()[:max_stem].decode(errors="ignore")
        yield f"{trimmed}{suffix}{extension}"


def validate_arguments(theme, source_path):
    if not theme or theme in {".", ".."} or "/" in theme or len(theme.encode()) > 255:
        fail("Invalid theme name")
    if not source_path or not os.path.isabs(source_path) or len(source_path) > 4096:
        fail("Invalid wallpaper path")


def require_home():
    home = os.environ.get("HOME", "")
    if not home or not os.path.isabs(home):
        fail("HOME is not absolute")
    return home


def wallpaper_basename(source_path):
    base = os.path.basename(source_path)
    extension = os.path.splitext(base)[1].lower()
    if not base or base in {".", ".."} or extension not in ALLOWED_EXTENSIONS:
        fail(f"Unsupported wallpaper type: {base}")
    return base


def verify_source(source_fd, source_path, home):
    source_info = os.fstat(source_fd)
    if not stat.S_ISREG(source_info.st_mode):
        fail("Wallpaper source is not a regular file")
    if source_info.st_uid != os.getuid():
        fail("Wallpaper source is not owned by the current user")
    if source_info.st_size < MIN_WALLPAPER_BYTES:
        fail(f"Wallpaper file too small ({source_info.st_size} bytes): {source_path}")

    home_real = os.path.realpath(home)
    source_real = os.path.realpath(f"/proc/self/fd/{source_fd}")
    if os.path.commonpath([home_real, source_real]) != home_real:
        fail("Wallpaper path must be under HOME")


def open_theme_directory(home, theme, directory_fds):
    """Open HOME/.config/omarchy/backgrounds/<theme>, creating missing links of the chain.

    Every opened descriptor is appended to directory_fds so the caller can close them.
    """
    parent_fd = open_owned_directory(home, "HOME")
    directory_fds.append(parent_fd)
    for name, label in (
        (".config", "configuration directory"),
        ("omarchy", "Omarchy configuration directory"),
        ("backgrounds", "wallpaper directory"),
        (theme, "theme wallpaper directory"),
    ):
        parent_fd = open_or_create_child(parent_fd, name, label)
        directory_fds.append(parent_fd)
    return parent_fd


def write_temporary(source_fd, backgrounds_fd, temporary_name):
    destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
    destination_fd = os.open(temporary_name, destination_flags, 0o600, dir_fd=backgrounds_fd)
    try:
        copy_source(source_fd, destination_fd)
        os.fchmod(destination_fd, 0o644)
        os.fsync(destination_fd)
    finally:
        os.close(destination_fd)


def link_within(directory_fd, source, target):
    """Hard-link source to target inside one directory; False when target exists."""
    try:
        os.link(source, target, src_dir_fd=directory_fd, dst_dir_fd=directory_fd, follow_symlinks=False)
    except FileExistsError:
        return False
    return True


def link_unused_name(backgrounds_fd, temporary_name, base):
    """Hard-link the temporary file to the first free candidate name; returns that name."""
    name_max = os.fpathconf(backgrounds_fd, "PC_NAME_MAX")
    for candidate in candidate_names(base, name_max):
        if link_within(backgrounds_fd, temporary_name, candidate):
            return candidate
    fail("Could not choose an unused wallpaper filename")


def remove_temporary(backgrounds_fd, temporary_name):
    try:
        os.unlink(temporary_name, dir_fd=backgrounds_fd)
    except FileNotFoundError:
        pass


class Staging:
    """The temporary file inside the theme wallpaper directory, until it is linked into place."""

    def __init__(self):
        self.directory_fds = []
        self.backgrounds_fd = -1
        self.temporary_name = ""

    def open(self, home, theme):
        self.backgrounds_fd = open_theme_directory(home, theme, self.directory_fds)
        self.temporary_name = f".theme-manager-{os.getpid()}-{secrets.token_hex(8)}.tmp"
        return self.backgrounds_fd, self.temporary_name

    def linked(self):
        os.unlink(self.temporary_name, dir_fd=self.backgrounds_fd)
        self.temporary_name = ""
        os.fsync(self.backgrounds_fd)

    def close(self):
        if self.temporary_name and self.backgrounds_fd >= 0:
            remove_temporary(self.backgrounds_fd, self.temporary_name)
        for fd in reversed(self.directory_fds):
            os.close(fd)


def publish_from(source_fd, source_path, home, theme, base, staging):
    verify_source(source_fd, source_path, home)
    backgrounds_fd, temporary_name = staging.open(home, theme)
    write_temporary(source_fd, backgrounds_fd, temporary_name)
    candidate = link_unused_name(backgrounds_fd, temporary_name, base)
    staging.linked()
    return os.path.join(home, ".config", "omarchy", "backgrounds", theme, candidate)


def publish(theme, source_path):
    validate_arguments(theme, source_path)
    home = require_home()
    base = wallpaper_basename(source_path)
    source_fd = os.open(source_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    staging = Staging()
    try:
        return publish_from(source_fd, source_path, home, theme, base, staging)
    finally:
        staging.close()
        os.close(source_fd)


def main():
    if len(sys.argv) != 3:
        print("Usage: publish-wallpaper.py <theme-name> <source-path>", file=sys.stderr)
        return 2
    try:
        installed_path = publish(sys.argv[1], sys.argv[2])
    except (OSError, RuntimeError, ValueError) as error:
        if isinstance(error, OSError) and error.errno == errno.ELOOP:
            print("Refusing to follow a symbolic link", file=sys.stderr)
        else:
            print(str(error), file=sys.stderr)
        return 1
    print(installed_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
