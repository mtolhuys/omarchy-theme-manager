#!/usr/bin/env python3
"""Install the theme-set memory hook without following any path it is given.

Started by Run (omakit/Run.qml) from ImagePicker.qml when the picker loads, so
it writes without a user asking it to. It publishes into Omarchy's hook
directory, which the plugin does not own, so the destination is derived here
rather than trusted: the caller supplies a name, and the directory chain is
walked with checked no-follow descriptors.

Usage: install-hook.py <source> <destination>
"""

import errno
import os
import secrets
import stat
import sys

from safe_paths import (
    fail,
    directory_identity,
    open_chain,
    require_home,
    revalidate_directory,
    write_all,
)

HOOK_DIRECTORY = (
    (".config", "configuration directory"),
    ("omarchy", "Omarchy configuration directory"),
    ("hooks", "Omarchy hook directory"),
    ("theme-set.d", "theme-set hook directory"),
)
HOOK_MODE = 0o755
MAX_HOOK_BYTES = 64 * 1024


def validate_arguments(source_path, destination_path):
    for label, value in (("source", source_path), ("destination", destination_path)):
        if not value or not os.path.isabs(value) or len(value) > 4096:
            fail(f"Invalid hook {label} path")


def expected_directory(home):
    return os.path.join(home, *(name for name, _ in HOOK_DIRECTORY))


def hook_name(home, destination_path):
    """Accept only a name directly inside Omarchy's theme-set hook directory.

    The destination is not resolved. It is compared literally against the one
    directory this helper is allowed to publish into, and only its final
    component is kept; the chain itself is reopened below.
    """
    directory, name = os.path.split(destination_path)
    if directory != expected_directory(home):
        fail("Hook destination is outside the theme-set hook directory")
    if not name or name in {".", ".."} or "/" in name or len(name.encode()) > 255:
        fail("Invalid hook filename")
    return name


def read_source(source_path):
    fd = os.open(source_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            fail("Hook source is not a regular file")
        if info.st_uid != os.getuid():
            fail("Hook source is not owned by the current user")
        if info.st_size > MAX_HOOK_BYTES:
            fail(f"Hook source is too large ({info.st_size} bytes)")
        blocks = []
        while True:
            block = os.read(fd, 65536)
            if not block:
                break
            blocks.append(block)
        return b"".join(blocks)
    finally:
        os.close(fd)


def already_current(directory_fd, name, payload):
    """True when the destination is a regular file with the wanted bytes and mode.

    A symbolic link, a directory or any other kind of entry is never current:
    it is replaced, and it is never opened for writing.
    """
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=directory_fd)
    except FileNotFoundError:
        return False
    except OSError as error:
        if error.errno in {errno.ELOOP, errno.ENXIO}:
            return False
        raise
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            return False
        if stat.S_IMODE(info.st_mode) != HOOK_MODE:
            return False
        if info.st_size != len(payload):
            return False
        return os.read(fd, len(payload) + 1) == payload
    finally:
        os.close(fd)


def publish(directory_fd, identity, name, payload):
    temporary = f".theme-manager-hook-{os.getpid()}-{secrets.token_hex(8)}.tmp"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(temporary, flags, 0o600, dir_fd=directory_fd)
    try:
        try:
            write_all(fd, payload)
            os.fchmod(fd, HOOK_MODE)
            os.fsync(fd)
        finally:
            os.close(fd)
        # The descriptor cannot have been redirected, but the directory could
        # have been made group-writable since the walk; check before publishing.
        revalidate_directory(directory_fd, identity, "theme-set hook directory")
        # rename replaces the name, so a planted symbolic link at the
        # destination is unlinked rather than written through.
        os.rename(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        temporary = ""
        os.fsync(directory_fd)
    finally:
        if temporary:
            try:
                os.unlink(temporary, dir_fd=directory_fd)
            except FileNotFoundError:
                pass


def install(source_path, destination_path):
    validate_arguments(source_path, destination_path)
    home = require_home()
    name = hook_name(home, destination_path)
    payload = read_source(source_path)
    directory_fds = []
    try:
        directory_fd = open_chain(home, HOOK_DIRECTORY, directory_fds)
        identity = directory_identity(directory_fd)
        if already_current(directory_fd, name, payload):
            return os.path.join(expected_directory(home), name)
        publish(directory_fd, identity, name, payload)
    finally:
        for fd in reversed(directory_fds):
            os.close(fd)
    return os.path.join(expected_directory(home), name)


def main():
    if len(sys.argv) != 3:
        print("Usage: install-hook.py <source> <destination>", file=sys.stderr)
        return 2
    try:
        install(sys.argv[1], sys.argv[2])
    except (OSError, RuntimeError, ValueError) as error:
        if isinstance(error, OSError) and error.errno == errno.ELOOP:
            print("Refusing to follow a symbolic link", file=sys.stderr)
        else:
            print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
