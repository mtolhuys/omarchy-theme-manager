"""The theme fetch against hostile repositories, over a real socket.

The marketplace review blocked 0.6.8 at cc6486a because a partial clone's
`git cat-file -s` downloaded a remote blob before the size check and the
initial tree and pack fetch were not byte-bounded. The fetch is now one
commit-pinned archive from codeload, read under a declared-length check, a
streamed byte cap, an expanded-bytes cap and one deadline. This file proves
that against repositories built here with git and served by a local HTTP
server: a theme whose image is over MAX_IMAGE_BYTES, an archive over
MAX_ARCHIVE_BYTES with and without a Content-Length, and a server that
trickles. No network, no desktop command; git only builds the fixtures.

    python3 -I -S -B tests/theme-install-hostile.py
"""

import http.server
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "install-theme.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

MIB = 1024 * 1024
SHA = "b" * 40


def git(*args, cwd):
    subprocess.run(["/usr/bin/git", *args], cwd=cwd, check=True, capture_output=True, env={"PATH": "/usr/bin", "HOME": str(cwd), "GIT_CONFIG_NOSYSTEM": "1"})


def build_repository(root, name, files):
    """A real repository with the given files, committed; its archive at <name>-<SHA>.tar.gz."""
    repo = root / name
    repo.mkdir()
    for relative, size in files.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as handle:
            if relative.endswith(".toml"):
                handle.write(b'[colors]\nbackground = "#000000"\nforeground = "#ffffff"\n')
            else:
                remaining = size
                while remaining > 0:
                    chunk = os.urandom(min(MIB, remaining)) if relative.startswith("pack") else b"\0" * min(MIB, remaining)
                    handle.write(chunk)
                    remaining -= len(chunk)
    git("init", "-q", "-b", "main", cwd=repo)
    git("-c", "user.name=fixture", "-c", "user.email=fixture@localhost", "add", "--all", cwd=repo)
    git("-c", "user.name=fixture", "-c", "user.email=fixture@localhost", "commit", "-q", "-m", "hostile", cwd=repo)
    archive = root / f"{name}-{SHA}.tar.gz"
    git("archive", "--format=tar.gz", f"--prefix={name}-{SHA}/", "-o", str(archive), "HEAD", cwd=repo)
    return archive


def packet(payload):
    return f"{len(payload) + 4:04x}".encode("ascii") + payload


ADVERTISEMENT = b"".join((
    packet(b"# service=git-upload-pack\n"),
    b"0000",
    packet(f"{SHA} HEAD\0symref=HEAD:refs/heads/main\n".encode("ascii")),
    packet(f"{SHA} refs/heads/main\n".encode("ascii")),
    b"0000",
))


class Handler(http.server.BaseHTTPRequestHandler):
    """Serves the advertisement and the archives; `/chunked/` without a length, `/trickle/` a byte a second."""

    files = {}
    sent = {}

    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.endswith("info/refs?service=git-upload-pack"):
            return self.send_bytes(ADVERTISEMENT, "application/x-git-upload-pack-advertisement")
        mode, _, name = self.path.lstrip("/").partition("/")
        data = self.files.get(name)
        if data is None:
            self.send_error(404)
            return
        if mode == "chunked":
            return self.send_chunked(name, data)
        if mode == "trickle":
            return self.send_trickle(name, data)
        return self.send_bytes(data, "application/octet-stream", name)

    def send_bytes(self, data, content_type, name=None):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        sent = 0
        try:
            for offset in range(0, len(data), 64 * 1024):
                self.wfile.write(data[offset:offset + 64 * 1024])
                sent += min(64 * 1024, len(data) - offset)
        except (BrokenPipeError, ConnectionResetError):
            pass
        if name:
            self.sent[name] = sent

    def send_chunked(self, name, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        sent = 0
        try:
            for offset in range(0, len(data), 64 * 1024):
                chunk = data[offset:offset + 64 * 1024]
                self.wfile.write(f"{len(chunk):x}\r\n".encode("ascii") + chunk + b"\r\n")
                sent += len(chunk)
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.sent[name] = sent

    def send_trickle(self, name, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        sent = 0
        try:
            for byte in data[:30]:
                self.wfile.write(bytes([byte]))
                self.wfile.flush()
                sent += 1
                time.sleep(1)
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.sent[name] = sent


class HostileFetch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="theme-hostile-"))
        # A theme whose preview is one byte over the image cap, in a small archive.
        cls.blob = build_repository(cls.root, "blob-theme", {"colors.toml": 0, "preview.png": installer.MAX_IMAGE_BYTES + 1})
        # A theme whose tree is over the archive cap: incompressible, so the archive is too.
        cls.pack = build_repository(cls.root, "pack-theme", {"colors.toml": 0, "pack.bin": installer.MAX_ARCHIVE_BYTES + MIB})
        Handler.files = {"blob-theme": cls.blob.read_bytes(), "pack-theme": cls.pack.read_bytes()}
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        shutil.rmtree(cls.root, ignore_errors=True)

    def local(self, mode):
        """Route the allow-listed GitHub URLs to the local server, the rest of the stack untouched."""
        port = self.port

        def open_response(downloader, url, host):
            if "info/refs" in url:
                path = "/x.git/info/refs?service=git-upload-pack"
            else:
                path = f"/{mode}/{url.split('/')[4]}"
            timeout = min(installer.SOCKET_TIMEOUT_SECONDS, downloader.deadline - time.monotonic())
            return urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=max(0.001, timeout))

        return patch.object(installer.Downloader, "open_response", open_response)

    def snapshot(self, name, mode="plain"):
        storage = self.root / f"storage-{name}-{mode}-{time.monotonic_ns()}"
        Handler.sent.pop(name, None)
        with self.local(mode):
            with self.assertRaises(installer.ThemeResourceLimitError) as raised:
                installer.Snapshot(f"https://github.com/hostile/{name}", storage)
        return storage, str(raised.exception)

    def test_oversized_blob_is_refused_before_any_theme_file_lands(self):
        storage, message = self.snapshot("blob-theme")
        self.assertIn("preview.png", message)
        self.assertIn(installer.human_size(installer.MAX_IMAGE_BYTES), message)
        # The archive was read under its cap and inventoried; no entry was extracted.
        self.assertEqual(sorted(p.name for p in storage.iterdir()), ["snapshot.tar.gz"])
        self.assertLessEqual(storage.joinpath("snapshot.tar.gz").stat().st_size, installer.MAX_ARCHIVE_BYTES)

    def test_oversized_pack_with_a_declared_length_is_refused_before_a_byte_of_body(self):
        storage, message = self.snapshot("pack-theme")
        self.assertIn("Theme source archive", message)
        self.assertFalse(storage.joinpath("snapshot.tar.gz").exists(), "nothing landed")
        # The server got to write at most one socket buffer before the client closed.
        self.assertLess(Handler.sent.get("pack-theme", 0), 4 * MIB)

    def test_oversized_pack_without_a_length_is_refused_at_the_cap_while_streaming(self):
        storage, message = self.snapshot("pack-theme", "chunked")
        self.assertIn("Theme source archive", message)
        on_disk = storage.joinpath("snapshot.tar.gz").stat().st_size
        self.assertGreater(on_disk, installer.MAX_ARCHIVE_BYTES - 64 * 1024)
        self.assertLessEqual(on_disk, installer.MAX_ARCHIVE_BYTES + 64 * 1024, "at most one read past the cap")
        # What the server pushed into loopback buffers after the client stopped
        # reading is the kernel's, not the client's: the bound is what landed.

    def test_a_trickling_server_hits_the_deadline_not_the_socket(self):
        storage = self.root / "storage-trickle"
        with patch.object(installer, "DOWNLOAD_SECONDS", 3), self.local("trickle"):
            started = time.monotonic()
            with self.assertRaises(RuntimeError) as raised:
                installer.Snapshot("https://github.com/hostile/blob-theme", storage)
            elapsed = time.monotonic() - started
        self.assertIn("timed out", str(raised.exception))
        self.assertLess(elapsed, 3 + installer.SOCKET_TIMEOUT_SECONDS + 1)
        self.assertLess(storage.joinpath("snapshot.tar.gz").stat().st_size, 64)

    def test_the_fixtures_are_what_they_claim(self):
        self.assertGreater(len(Handler.files["pack-theme"]), installer.MAX_ARCHIVE_BYTES)
        self.assertLess(len(Handler.files["blob-theme"]), MIB, "zeros compress; the blob is over the image cap, the archive is not")
        with io.BytesIO(Handler.files["blob-theme"]) as data:
            import gzip
            import tarfile
            with tarfile.open(fileobj=gzip.GzipFile(fileobj=data), mode="r|") as tar:
                sizes = {member.name.split("/", 1)[1]: member.size for member in tar if member.isfile()}
        self.assertEqual(sizes["preview.png"], installer.MAX_IMAGE_BYTES + 1)


if __name__ == "__main__":
    unittest.main()
