"""Check Qt's signal/list boundary without Quickshell or a desktop session."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class QtCompatibilityTest(unittest.TestCase):
    def test_signal_lists_on_the_selected_qt_runtime(self):
        prefix = Path(os.environ.get("OMARCHY_QT_COMPAT_ROOT", "/"))
        runner = prefix / "usr/lib/qt6/bin/qmltestrunner"
        self.assertTrue(runner.is_file(), f"Qt test runner is required: {runner}")
        with tempfile.TemporaryDirectory(prefix="theme-manager-qt-") as temporary:
            target = Path(temporary)
            (target / "runtime").mkdir()
            (target / "session").mkdir(mode=0o700)
            shutil.copy(ROOT / "tests/qml/tst_signal-compatibility.qml", target)
            shutil.copy(ROOT / "v0200/ImagePickerModel.js", target / "runtime")
            environment = {
                "PATH": "/usr/bin", "LANG": "C.UTF-8", "HOME": temporary,
                "XDG_RUNTIME_DIR": str(target / "session"),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
            }
            if prefix != Path("/"):
                environment.update({
                    "LD_LIBRARY_PATH": str(prefix / "usr/lib"),
                    "QML_IMPORT_PATH": str(prefix / "usr/lib/qt6/qml"),
                    "QT_PLUGIN_PATH": str(prefix / "usr/lib/qt6/plugins"),
                })
            result = subprocess.run(
                [str(runner), "-input", str(target / "tst_signal-compatibility.qml")],
                env=environment, capture_output=True, text=True, timeout=20,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("6 passed, 0 failed", output)
            print("\n" + "\n".join(line for line in output.splitlines()
                                   if line.startswith("Config:") or "SIGNAL_SOURCE_ARRAY=" in line))
