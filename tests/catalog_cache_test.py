"""Discovery remains available when optional badge metadata is unavailable."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "theme_catalog_cache", Path(__file__).resolve().parent.parent / "catalog-cache.py"
)
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class CatalogCacheTest(unittest.TestCase):
    def test_badge_failure_does_not_hide_valid_themes(self):
        themes = [{"name": "Example", "github_url": "https://github.com/example/theme"}]
        for failure in (OSError("offline"), RuntimeError("changed HTML"),
                        UnicodeError("invalid encoding"), json.JSONDecodeError("bad", "", 0)):
            with self.subTest(failure=failure), mock.patch.object(
                catalog, "refresh", side_effect=[themes, failure]
            ), mock.patch("sys.stderr", new_callable=io.StringIO) as errors:
                result = json.loads(catalog.render_catalog(0, 21600, False))
                self.assertEqual(result["themes"][0]["name"], "Example")
                self.assertEqual(result["officialRepositories"], [])
                self.assertIn("Official theme badges unavailable", errors.getvalue())

    def test_discovery_failure_is_still_reported(self):
        with mock.patch.object(catalog, "refresh", side_effect=RuntimeError("invalid dataset")):
            with self.assertRaisesRegex(RuntimeError, "invalid dataset"):
                catalog.render_catalog(0, 21600, False)

    def test_official_badges_survive_when_available(self):
        with mock.patch.object(catalog, "refresh", side_effect=[[], ["https://github.com/a/b"]]):
            result = json.loads(catalog.render_catalog(0, 21600, False))
            self.assertEqual(result["officialRepositories"], ["https://github.com/a/b"])

    def test_curl_ignores_personal_config_before_other_options(self):
        self.assertEqual(catalog.curl_command(catalog.CATALOG_URL, 100, 4)[:2], ["curl", "-q"])
