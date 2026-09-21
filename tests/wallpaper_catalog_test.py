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


def home_environment(home, **overrides):
    """HOME plus XDG cache and data homes inside it, as the helper requires."""
    values = {
        "HOME": home,
        "XDG_CACHE_HOME": os.path.join(home, "cache"),
        "XDG_DATA_HOME": os.path.join(home, "data"),
    }
    values.update(overrides)
    return values


def foreign_owner(path):
    """An os.fstat replacement that reports one directory as owned by another user."""
    real_fstat = os.fstat

    def fstat(fd):
        info = real_fstat(fd)
        if os.readlink(f"/proc/self/fd/{fd}") == str(path):
            return os.stat_result((*info[:4], info.st_uid + 1, *info[5:10]))
        return info

    return fstat


PLUGIN_DIRECTORIES = (
    ("XDG_CACHE_HOME", lambda: catalog.plugin_cache_dir("wallpaper-search")),
    ("XDG_DATA_HOME", catalog.wallpaper_dir),
)


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
            with mock.patch.dict(os.environ, home_environment(directory)):
                cache = catalog.search_cache_path(params)
                cache.write_text(json.dumps({"wallpapers": [], "meta": {"current_page": 1}}))
                with mock.patch.object(catalog, "search_ocs", side_effect=AssertionError("network used")):
                    result = catalog.search_page(params)
        self.assertTrue(result["meta"]["cached"])

    def test_uses_expired_cache_only_as_an_outage_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            params = catalog.normalize(arguments(collection="community-dark"))
            with mock.patch.dict(os.environ, home_environment(directory)):
                cache = catalog.search_cache_path(params)
                cache.write_text(json.dumps({"wallpapers": [], "meta": {"current_page": 1}}))
                old = time.time() - catalog.SEARCH_CACHE_TTL_SECONDS - 60
                os.utime(cache, (old, old))
                with mock.patch.object(catalog, "search_ocs", side_effect=catalog.CatalogError("offline")):
                    result = catalog.search_page(params)
        self.assertTrue(result["meta"]["stale"])

    def test_creates_default_cache_and_data_chains_below_home(self):
        with tempfile.TemporaryDirectory() as home:
            with mock.patch.dict(os.environ, {"HOME": home}):
                os.environ.pop("XDG_CACHE_HOME", None)
                os.environ.pop("XDG_DATA_HOME", None)
                cache = catalog.plugin_cache_dir("wallpaper-search").path
                data = catalog.wallpaper_dir().path
                published = catalog.atomic_write(catalog.wallpaper_dir(), "one.png", b"png")
            self.assertEqual(cache, Path(home, ".cache", "omarchy-theme-manager", "wallpaper-search"))
            self.assertEqual(data, Path(home, ".local", "share", "omarchy-theme-manager", "wallpapers"))
            created = (Path(home, ".cache"), cache.parent, cache, Path(home, ".local"), data.parent.parent, data.parent, data)
            for directory in created:
                self.assertEqual(os.lstat(directory).st_mode & 0o777, 0o700, directory)
            self.assertEqual(published, data / "one.png")
            self.assertTrue(published.is_file())
            self.assertEqual(os.lstat(published).st_mode & 0o777, 0o600)

    def test_rejects_a_symlinked_intermediate_component(self):
        for variable, plugin_directory in PLUGIN_DIRECTORIES:
            with self.subTest(variable=variable), tempfile.TemporaryDirectory() as home:
                victim = Path(home, "victim-directory")
                victim.mkdir(mode=0o700)
                planted = Path(home, "cache" if variable == "XDG_CACHE_HOME" else "data")
                planted.symlink_to(victim)
                with mock.patch.dict(os.environ, home_environment(home)):
                    with self.assertRaises((catalog.CatalogError, OSError)) as raised:
                        plugin_directory()
                self.assertRegex(str(raised.exception), r"Not a directory|symbolic link|Too many levels")
                self.assertEqual(list(victim.iterdir()), [])

    def test_rejects_a_component_owned_by_another_user(self):
        for variable, plugin_directory in PLUGIN_DIRECTORIES:
            with self.subTest(variable=variable), tempfile.TemporaryDirectory() as home:
                component = Path(home, "cache" if variable == "XDG_CACHE_HOME" else "data")
                component.mkdir(mode=0o700)
                with mock.patch.dict(os.environ, home_environment(home)):
                    with mock.patch.object(os, "fstat", foreign_owner(component)):
                        with self.assertRaises(catalog.CatalogError) as raised:
                            plugin_directory()
                self.assertEqual(str(raised.exception), f"{variable} directory is not owned by the current user")
                self.assertEqual(list(component.iterdir()), [])

    def test_rejects_an_xdg_directory_outside_home(self):
        for variable, plugin_directory in PLUGIN_DIRECTORIES:
            with self.subTest(variable=variable), tempfile.TemporaryDirectory() as root:
                home = Path(root, "home")
                home.mkdir(mode=0o700)
                outside = Path(root, "elsewhere")
                with mock.patch.dict(os.environ, home_environment(str(home), **{variable: str(outside)})):
                    with self.assertRaises(catalog.CatalogError) as raised:
                        plugin_directory()
                self.assertEqual(str(raised.exception), f"{variable} must be inside HOME")
                self.assertFalse(outside.exists())

    def test_rejects_a_relative_xdg_value(self):
        for variable, plugin_directory in PLUGIN_DIRECTORIES:
            with self.subTest(variable=variable), tempfile.TemporaryDirectory() as home:
                with mock.patch.dict(os.environ, home_environment(home, **{variable: "cache"})):
                    with self.assertRaises(catalog.CatalogError) as raised:
                        plugin_directory()
                self.assertEqual(str(raised.exception), f"HOME and {variable} must be absolute")
                self.assertEqual(sorted(os.listdir(home)), [])

    def test_image_signature_rejects_html_error_pages(self):
        self.assertTrue(catalog.image_signature(b"\xff\xd8\xffimage"))
        self.assertTrue(catalog.image_signature(b"\x89PNG\r\n\x1a\nimage"))
        self.assertFalse(catalog.image_signature(b"<html>provider error</html>"))


if __name__ == "__main__":
    unittest.main()
