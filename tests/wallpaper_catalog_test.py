import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("wallpaper_catalog", ROOT / "wallpaper-catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


def arguments(**values):
    defaults = {
        "query": "",
        "collection": "omarchy",
        "sorting": "featured",
        "license": "any",
        "page": 1,
    }
    defaults.update(values)
    return argparse.Namespace(**defaults)


class WallpaperCatalogTest(unittest.TestCase):
    def test_normalizes_every_supported_filter_without_shell_interpolation(self):
        normalized = catalog.normalize(
            arguments(
                query="  neon\ncity; touch /tmp/nope  ",
                collection="community-neon",
                sorting="newest",
                license="share-alike",
                page=-4,
            )
        )
        self.assertEqual(normalized["query"], "neon city; touch /tmp/nope")
        self.assertEqual(normalized["collection"], "community-neon")
        self.assertEqual(normalized["sorting"], "newest")
        self.assertEqual(normalized["license"], "share-alike")
        self.assertEqual(normalized["page"], 1)

    def test_trusts_exact_provider_hosts_not_lookalike_suffixes(self):
        self.assertTrue(catalog.trusted_host("commons.wikimedia.org"))
        self.assertTrue(catalog.trusted_host("files01.pling.com"))
        self.assertTrue(catalog.trusted_host("ocs-dl.fra1.cdn.digitaloceanspaces.com"))
        self.assertFalse(catalog.trusted_host("commons.wikimedia.org.evil.test"))
        self.assertFalse(catalog.trusted_host("files.pling.com.evil.test"))
        self.assertFalse(catalog.trusted_host("example.test"))

    def test_encodes_provider_filename_spaces_without_changing_the_host(self):
        cleaned = catalog.clean_https(
            "https://files06.pling.com/api/files/Gradient Glow Orange.jpg"
        )
        self.assertEqual(
            cleaned,
            "https://files06.pling.com/api/files/Gradient%20Glow%20Orange.jpg",
        )

    def test_community_items_require_free_images_explicit_licenses_and_no_branding(self):
        record = {
            "id": "123",
            "name": "Midnight Geometry 4K",
            "summary": "abstract wallpaper",
            "description": "dark geometric shapes",
            "tags": "wallpaper,cc-by-sa",
            "personid": "artist",
            "previewpic1": "https://images.pling.com/img/preview.jpg",
            "detailpage": "https://www.opendesktop.org/p/123",
            "downloadlink1": "https://files01.pling.com/api/files/download.png",
            "downloadname1": "midnight-3840x2160.png",
            "downloadprice1": "0",
            "downloadsize1": "1048576",
            "downloadtags1": "mimetype=image/png",
        }
        item = catalog.ocs_item(record, "community-dark", "share-alike")
        self.assertEqual(item["id"], "ocs-123")
        self.assertEqual(item["resolution"], "3840x2160")
        self.assertIsNone(catalog.ocs_item({**record, "name": "GNOME Midnight"}, "community-dark", "any"))
        self.assertIsNone(catalog.ocs_item({**record, "tags": "wallpaper"}, "community-dark", "any"))
        self.assertIsNone(catalog.ocs_item({**record, "downloadprice1": "2.99"}, "community-dark", "any"))

    def test_reads_bundled_omarchy_wallpapers_without_redistributing_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            background = root / "themes" / "matte-black" / "backgrounds" / "night.png"
            background.parent.mkdir(parents=True)
            background.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0" * 8 + (3840).to_bytes(4, "big") + (2160).to_bytes(4, "big"))
            (background.parent / "omarchy.png").write_bytes(background.read_bytes())
            with mock.patch.dict(os.environ, {"OMARCHY_PATH": str(root)}):
                items = catalog.discover_omarchy()
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "Matte Black — Night")
        self.assertEqual(items[0]["resolution"], "3840x2160")
        self.assertTrue(items[0]["id"].startswith("omarchy-"))

    def test_reuses_fresh_remote_search_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            params = catalog.normalize(arguments(collection="community-abstract"))
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": directory}):
                cache = catalog.search_cache_path(params)
                cache.write_text(json.dumps({"wallpapers": [], "meta": {"current_page": 1}}))
                with mock.patch.object(catalog, "search_ocs", side_effect=AssertionError("network used")):
                    result = catalog.search_page(params)
        self.assertTrue(result["meta"]["cached"])

    def test_uses_expired_cache_only_as_an_outage_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            params = catalog.normalize(arguments(collection="community-dark"))
            with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": directory}):
                cache = catalog.search_cache_path(params)
                cache.write_text(json.dumps({"wallpapers": [], "meta": {"current_page": 1}}))
                old = time.time() - catalog.SEARCH_CACHE_TTL_SECONDS - 60
                os.utime(cache, (old, old))
                with mock.patch.object(catalog, "search_ocs", side_effect=catalog.CatalogError("offline")):
                    result = catalog.search_page(params)
        self.assertTrue(result["meta"]["stale"])

    def test_image_signature_rejects_html_error_pages(self):
        self.assertTrue(catalog.image_signature(b"\xff\xd8\xffimage"))
        self.assertTrue(catalog.image_signature(b"\x89PNG\r\n\x1a\nimage"))
        self.assertFalse(catalog.image_signature(b"<html>provider error</html>"))


if __name__ == "__main__":
    unittest.main()
