#!/usr/bin/env python3
"""Checked no-follow directory descriptors shared by every publishing helper.

A helper that writes outside its own private directory must never resolve a
path the caller handed it. It walks the chain one component at a time, opens
each with O_NOFOLLOW, and checks the descriptor it got rather than the name it
asked for. Every later operation is relative to that descriptor, so a component
swapped after the check cannot redirect the write: the descriptor is bound to
the inode, not to the path.

These primitives were written for publish-wallpaper.py. Keeping them here is
what stops the next helper reimplementing the walk and getting it wrong.
"""

import os
import stat


def fail(message):
    raise RuntimeError(message)


def directory_identity(fd):
    """The device and inode a descriptor is bound to, for revalidation."""
    info = os.fstat(fd)
    return (info.st_dev, info.st_ino)


def verify_owned_directory(fd, label):
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        fail(f"{label} is not a directory")
    if info.st_uid != os.getuid():
        fail(f"{label} is not owned by the current user")
    if info.st_mode & 0o022:
        fail(f"{label} is writable by another user")


def revalidate_directory(fd, identity, label):
    """Re-check a descriptor immediately before it is used to publish.

    The descriptor cannot be redirected once opened, so this catches the
    remaining case: the directory itself being chmodded or chowned after the
    walk and before the write.
    """
    if directory_identity(fd) != identity:
        fail(f"{label} changed while it was being prepared")
    verify_owned_directory(fd, label)


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


def open_chain(home, components, directory_fds):
    """Open HOME then each named component, creating the ones that are missing.

    Every descriptor is appended to directory_fds so the caller can close them.
    Returns the descriptor of the final component.
    """
    parent_fd = open_owned_directory(home, "HOME")
    directory_fds.append(parent_fd)
    for name, label in components:
        parent_fd = open_or_create_child(parent_fd, name, label)
        directory_fds.append(parent_fd)
    return parent_fd


def write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            fail("Could not write the whole file")
        view = view[written:]


def require_home():
    home = os.environ.get("HOME", "")
    if not home or not os.path.isabs(home):
        fail("HOME is not absolute")
    return home
