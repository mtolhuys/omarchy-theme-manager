"""Run the real QML controllers and unmodified Run block without a desktop."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HELPER = '''#!/usr/bin/python3
import json, os, sys, time
if os.environ.get("FIXTURE_CASE") == "slow":
    time.sleep(5)
if os.environ.get("FIXTURE_CASE") == "failure":
    print(json.dumps({"error": "Fixture provider is unavailable"}))
    print("Fixture provider is unavailable", file=sys.stderr)
    sys.exit(1)
if os.path.basename(sys.argv[0]) == "themes":
    data = {"themes": [{"name": "Example", "repositoryUrl": "https://github.com/example/omarchy-example-theme"}]}
else:
    data = {"wallpapers": [{"id": "omarchy-1", "title": "Example", "path": "https://example.invalid/wallpaper.png", "url": "https://www.opendesktop.org/p/1", "resolution": "3840x2160", "collection": "omarchy", "source": "Bundled with Omarchy", "license": "See Omarchy source", "thumbnailPath": os.environ["HOME"] + "/.cache/omarchy-theme-manager/wallpaper-thumbs/omarchy-1.png"}], "meta": {"current_page": 1, "last_page": 1, "total": 1}}
print(json.dumps(data))
'''


class CatalogControllersTest(unittest.TestCase):
    def test_real_qml_request_failure_and_retry(self):
        self.assertIsNotNone(shutil.which("quickshell"), "quickshell is required for controller tests")
        with tempfile.TemporaryDirectory(prefix="theme-manager-qml-") as temporary:
            target = Path(temporary)
            (target / "runtime").mkdir()
            (target / "session").mkdir(mode=0o700)
            (target / "home").mkdir(mode=0o700)
            shutil.copy(ROOT / "tests/qml/catalog-controllers.qml", target / "shell.qml")
            shutil.copytree(ROOT / "omakit", target / "omakit")
            for name in ("ThemeCatalogController.qml", "ThemeCatalogModel.js",
                         "WallpaperBrowserController.qml", "WallpaperBrowserModel.js"):
                shutil.copy(ROOT / "v0200" / name, target / "runtime" / name)
            for name in ("themes", "wallpapers"):
                helper = target / name
                helper.write_text(HELPER)
                helper.chmod(0o700)
            environment = {
                "PATH": "/usr/bin", "LANG": "C.UTF-8", "HOME": str(target / "home"),
                "XDG_RUNTIME_DIR": str(target / "session"), "FIXTURE_DIR": str(target),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
                "QT_QUICK_CONTROLS_STYLE": "Basic",
            }
            result = subprocess.run(
                ["/usr/bin/quickshell", "-p", str(target)], env=environment,
                capture_output=True, text=True, timeout=20,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("CONTROLLERS FAIL", output)
            self.assertNotRegex(output, r"TypeError|ReferenceError|Failed to load configuration")
            self.assertIn("CONTROLLERS PASS", output)
