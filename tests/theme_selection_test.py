"""Open theme rows on the current theme through the real collections controller."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ThemeSelectionTest(unittest.TestCase):
    def test_loaded_theme_rows_keep_the_current_theme(self):
        self.assertIsNotNone(shutil.which("quickshell"), "quickshell is required for controller tests")
        with tempfile.TemporaryDirectory(prefix="theme-manager-qml-") as temporary:
            target = Path(temporary)
            (target / "runtime").mkdir()
            (target / "session").mkdir(mode=0o700)
            (target / "home").mkdir(mode=0o700)
            shutil.copy(ROOT / "tests/qml/theme-selection.qml", target / "shell.qml")
            shutil.copytree(ROOT / "omakit", target / "omakit")
            for name in ("ThemeCollectionsController.qml", "ThemeCollectionsModel.js",
                         "ThemeManagerModel.js", "ImagePickerModel.js", "PluginState.qml"):
                shutil.copy(ROOT / "v0200" / name, target / "runtime" / name)
            environment = {
                "PATH": "/usr/bin", "LANG": "C.UTF-8", "HOME": str(target / "home"),
                "XDG_RUNTIME_DIR": str(target / "session"),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
            }
            result = subprocess.run(
                ["/usr/bin/quickshell", "-p", str(target)], env=environment,
                capture_output=True, text=True, timeout=20,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("THEME SELECTION FAIL", output)
            self.assertNotRegex(output, r"TypeError|ReferenceError|Failed to load configuration")
            self.assertIn("THEME SELECTION PASS", output)


if __name__ == "__main__":
    unittest.main()
