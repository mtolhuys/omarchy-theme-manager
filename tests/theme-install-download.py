"""Transport regressions; no network or desktop commands are executed."""

import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "install-theme.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
URL = "https://raw.githubusercontent.com/example/theme/" + "a" * 40 + "/colors.toml"


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
        with self.assertRaisesRegex(RuntimeError, "Compressed"):
            self.downloader(response).read(URL, 100)
        self.assertEqual(response.consumed, 0)

    def test_nonallowlisted_host_is_rejected_before_open(self):
        downloader = self.downloader(Response(b""))
        for url in ("http://api.github.com/", "https://api.github.com.evil/", "https://user@api.github.com/"):
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


if __name__ == "__main__":
    unittest.main()
