"""Transport regressions; no network or desktop commands are executed."""

import importlib.util
import io
import sys
import tarfile
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "install-theme.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
URL = "https://codeload.github.com/example/theme/tar.gz/" + "a" * 40
REF_URL = "https://github.com/example/theme.git/info/refs?service=git-upload-pack"
SHA = "a" * 40


def packet(payload):
    return f"{len(payload) + 4:04x}".encode("ascii") + payload


def advertisement(sha=SHA):
    return b"".join((
        packet(b"# service=git-upload-pack\n"),
        b"0000",
        packet(f"{sha} HEAD\0symref=HEAD:refs/heads/main\n".encode("ascii")),
        packet(f"{sha} refs/heads/main\n".encode("ascii")),
        b"0000",
    ))


class Response(io.BytesIO):
    status = 200

    def __init__(self, data, headers=None):
        super().__init__(data)
        self.headers = headers or {}
        self.consumed = 0
        self.requests = []

    def read1(self, maximum):
        self.requests.append(maximum)
        data = super().read1(maximum)
        self.consumed += len(data)
        return data


class Opener:
    def __init__(self, response):
        self.response = response
        self.calls = 0

    def open(self, request, timeout):
        self.calls += 1
        return self.response


class ErrorOpener:
    def __init__(self, error):
        self.error = error

    def open(self, request, timeout):
        raise self.error


class DownloadTests(unittest.TestCase):
    def downloader(self, response):
        downloader = installer.Downloader()
        downloader.opener = Opener(response)
        return downloader

    def test_no_length_and_false_length_are_bounded_during_read(self):
        for headers in ({}, {"Content-Length": "1"}):
            with self.subTest(headers=headers):
                response = Response(b"x" * (1024 * 1024), headers)
                downloader = self.downloader(response)
                with self.assertRaisesRegex(RuntimeError, "byte limit"):
                    downloader.read(URL, 100)
                self.assertEqual(response.consumed, 101)
                self.assertTrue(response.closed)

    def test_oversized_announced_length_is_rejected_without_body_read(self):
        response = Response(b"x" * 1000, {"Content-Length": "1000"})
        with self.assertRaisesRegex(RuntimeError, "byte limit"):
            self.downloader(response).read(URL, 10)
        self.assertEqual(response.consumed, 0)
        self.assertTrue(response.closed)

    def test_truncated_content_length_fails_closed(self):
        response = Response(b"a", {"Content-Length": "10"})
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            self.downloader(response).read(URL, 10)

    def test_total_download_budget_restricts_next_response(self):
        first = Response(b"abc")
        downloader = self.downloader(first)
        downloader.remaining = 5
        self.assertEqual(downloader.read(URL, 20), b"abc")
        self.assertEqual(downloader.remaining, 2)
        second = Response(b"x" * 100)
        downloader.opener = Opener(second)
        with self.assertRaisesRegex(RuntimeError, "byte limit"):
            downloader.read(URL, 20)
        self.assertEqual(second.consumed, 3)

    def test_compressed_response_is_rejected_without_body_read(self):
        response = Response(b"compressed", {"Content-Encoding": "gzip"})
        with self.assertRaisesRegex(RuntimeError, "content encoding"):
            self.downloader(response).read(URL, 100)
        self.assertEqual(response.consumed, 0)

    def test_nonallowlisted_host_is_rejected_before_open(self):
        downloader = self.downloader(Response(b""))
        for url in ("http://github.com/", "https://github.com.evil/", "https://user@github.com/"):
            with self.assertRaisesRegex(RuntimeError, "host"):
                downloader.read(url, 10)
        self.assertEqual(downloader.opener.calls, 0)

    def test_redirect_cannot_switch_host_or_commit(self):
        handler = installer.NoRedirects()
        for url in ("https://evil.invalid/huge", URL):
            with self.assertRaisesRegex(RuntimeError, "redirects"):
                handler.redirect_request(None, None, 302, "Found", {}, url)

    def test_expired_deadline_prevents_request(self):
        downloader = self.downloader(Response(b""))
        downloader.deadline = 0
        with self.assertRaisesRegex(RuntimeError, "budget"):
            downloader.read(URL, 100)
        self.assertEqual(downloader.opener.calls, 0)

    def test_github_rate_limit_has_a_typed_temporary_failure(self):
        error = urllib.error.HTTPError(
            URL,
            403,
            "rate limit exceeded",
            {"X-RateLimit-Remaining": "0"},
            None,
        )
        downloader = installer.Downloader()
        downloader.opener = ErrorOpener(error)
        with self.assertRaisesRegex(installer.GitHubRateLimitError, "rate limit"):
            downloader.read(URL, 100)

    def test_other_http_errors_remain_normal_install_failures(self):
        error = urllib.error.HTTPError(URL, 403, "Forbidden", {}, None)
        self.addCleanup(error.close)
        downloader = installer.Downloader()
        downloader.opener = ErrorOpener(error)
        with self.assertRaises(urllib.error.HTTPError):
            downloader.read(URL, 100)

    def test_rate_limit_main_exit_is_ex_tempfail(self):
        argv = ["install-theme.py", "https://github.com/example/omarchy-safe-theme"]
        with patch.object(sys, "argv", argv), patch.object(
            installer,
            "Snapshot",
            side_effect=installer.GitHubRateLimitError("GitHub download rate limit reached"),
        ), patch("sys.stderr", new_callable=io.StringIO) as stderr:
            self.assertEqual(installer.main(), installer.TEMPORARY_FAILURE)
        self.assertIn("retry later", stderr.getvalue())

    def test_trickled_response_checks_deadline_after_each_read(self):
        response = Response(b"a" * 100)
        downloader = self.downloader(response)
        downloader.deadline = 10
        with patch.object(installer.time, "monotonic", side_effect=[0, 0, 0, 11]):
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                downloader.read(URL, 100)
        self.assertTrue(response.closed)

    def test_image_total_budget_checked_before_blob_download(self):
        class Snapshot:
            def __init__(self):
                self.limits = []

            def backgrounds(self):
                return ["backgrounds/one.png", "backgrounds/two.png"]

            def blob(self, path, maximum):
                self.limits.append((path, maximum))
                if path == "preview.png":
                    raise RuntimeError("Missing theme file: preview.png")
                if maximum < 8:
                    raise RuntimeError("Oversized theme file")
                return b"\x89PNG\r\n\x1a\n"

        snapshot = Snapshot()
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(installer, "MAX_IMAGE_TOTAL_BYTES", 10):
                with self.assertRaisesRegex(RuntimeError, "Oversized"):
                    installer.copy_images(snapshot, Path(directory))
        self.assertEqual(snapshot.limits[-1], ("backgrounds/two.png", 2))

    def test_git_advertisement_resolves_one_exact_head(self):
        self.assertEqual(installer.advertised_head(advertisement()), SHA)

    def test_git_advertisement_rejects_truncation_and_duplicate_head(self):
        with self.assertRaisesRegex(RuntimeError, "(?:Incomplete|Invalid)"):
            installer.advertised_head(advertisement()[:-2])
        duplicate = advertisement()[:-4] + packet(f"{SHA} HEAD\n".encode("ascii")) + b"0000"
        with self.assertRaisesRegex(RuntimeError, "HEAD"):
            installer.advertised_head(duplicate)

    def test_git_advertisement_requires_upload_pack_service(self):
        body = packet(f"{SHA} HEAD\n".encode("ascii")) + b"0000"
        with self.assertRaisesRegex(RuntimeError, "exact commit"):
            installer.advertised_head(body)

    def write_archive(self, path, root, entries):
        with tarfile.open(path, "w:gz") as archive:
            directory = tarfile.TarInfo(root + "/")
            directory.type = tarfile.DIRTYPE
            archive.addfile(directory)
            for name, data, kind in entries:
                member = tarfile.TarInfo(f"{root}/{name}")
                if kind == "file":
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
                elif kind == "symlink":
                    member.type = tarfile.SYMTYPE
                    member.linkname = data.decode("utf-8")
                    archive.addfile(member)

    def snapshot_for_archive(self):
        snapshot = installer.Snapshot.__new__(installer.Snapshot)
        snapshot.name = "theme"
        snapshot.commit = SHA
        snapshot.downloader = type("State", (), {"deadline": float("inf")})()
        return snapshot

    def test_archive_rejects_selected_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "snapshot.tar.gz"
            self.write_archive(archive, f"theme-{SHA}", [("colors.toml", b"target", "symlink")])
            with self.assertRaisesRegex(RuntimeError, "regular file"):
                self.snapshot_for_archive().inventory(archive)

    def test_archive_rejects_wrong_commit_root(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "snapshot.tar.gz"
            self.write_archive(archive, "theme-wrong", [("colors.toml", b"x", "file")])
            with self.assertRaisesRegex(RuntimeError, "invalid path"):
                self.snapshot_for_archive().inventory(archive)

    def test_archive_accepts_only_a_case_variant_of_the_pinned_root(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "snapshot.tar.gz"
            self.write_archive(archive, f"Theme-{SHA}", [("colors.toml", b"x", "file")])
            entries = self.snapshot_for_archive().inventory(archive)
            self.assertEqual(entries["colors.toml"]["size"], 1)

    def test_archive_expanded_bytes_are_bounded_while_decompressing(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "snapshot.tar.gz"
            self.write_archive(archive, f"theme-{SHA}", [("ignored", b"x" * 4096, "file")])
            with patch.object(installer, "MAX_ARCHIVE_EXPANDED_BYTES", 1024):
                with self.assertRaisesRegex(RuntimeError, "expanded byte limit"):
                    self.snapshot_for_archive().inventory(archive)

    def test_archive_member_count_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "snapshot.tar.gz"
            self.write_archive(archive, f"theme-{SHA}", [("one", b"", "file")])
            with patch.object(installer, "MAX_ARCHIVE_MEMBERS", 1):
                with self.assertRaisesRegex(RuntimeError, "too many entries"):
                    self.snapshot_for_archive().inventory(archive)


if __name__ == "__main__":
    unittest.main()
