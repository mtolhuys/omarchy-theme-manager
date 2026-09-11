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


def publish(theme, source_path):
    if not theme or theme in {".", ".."} or "/" in theme or len(theme.encode()) > 255:
        fail("Invalid theme name")
    if not source_path or not os.path.isabs(source_path) or len(source_path) > 4096:
        fail("Invalid wallpaper path")

    home = os.environ.get("HOME", "")
    if not home or not os.path.isabs(home):
        fail("HOME is not absolute")

    base = os.path.basename(source_path)
    extension = os.path.splitext(base)[1].lower()
    if not base or base in {".", ".."} or extension not in ALLOWED_EXTENSIONS:
        fail(f"Unsupported wallpaper type: {base}")

    open_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
    source_fd = os.open(source_path, open_flags)
    directory_fds = []
    temporary_name = ""
    backgrounds_fd = -1
    try:
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

        home_fd = open_owned_directory(home, "HOME")
        directory_fds.append(home_fd)
        parent_fd = home_fd
        for name, label in (
            (".config", "configuration directory"),
            ("omarchy", "Omarchy configuration directory"),
            ("backgrounds", "wallpaper directory"),
            (theme, "theme wallpaper directory"),
        ):
            parent_fd = open_or_create_child(parent_fd, name, label)
            directory_fds.append(parent_fd)
        backgrounds_fd = parent_fd

        temporary_name = f".theme-manager-{os.getpid()}-{secrets.token_hex(8)}.tmp"
        destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        destination_fd = os.open(temporary_name, destination_flags, 0o600, dir_fd=backgrounds_fd)
        try:
            copy_source(source_fd, destination_fd)
            os.fchmod(destination_fd, 0o644)
            os.fsync(destination_fd)
        finally:
            os.close(destination_fd)

        name_max = os.fpathconf(backgrounds_fd, "PC_NAME_MAX")
        for candidate in candidate_names(base, name_max):
            try:
                os.link(
                    temporary_name,
                    candidate,
                    src_dir_fd=backgrounds_fd,
                    dst_dir_fd=backgrounds_fd,
                    follow_symlinks=False,
                )
            except FileExistsError:
                continue
            os.unlink(temporary_name, dir_fd=backgrounds_fd)
            temporary_name = ""
            os.fsync(backgrounds_fd)
            return os.path.join(home, ".config", "omarchy", "backgrounds", theme, candidate)

        fail("Could not choose an unused wallpaper filename")
    finally:
        if temporary_name and backgrounds_fd >= 0:
            try:
                os.unlink(temporary_name, dir_fd=backgrounds_fd)
            except FileNotFoundError:
                pass
        for fd in reversed(directory_fds):
            os.close(fd)
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
