"""Theme catalog and Pling previews settle through the real preview controller."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

FAKE_HELPER = """#!/usr/bin/bash
echo "$*" >> "$(dirname "$0")/calls"
folder="$HOME/.cache/omarchy-theme-manager/preview-thumbs"
printf '{"previews":[{"url":"https://images.pling.com/img/good.png","path":"%s/0123456789abcdef0123456789abcdef.png"},' "$folder"
printf '{"url":"https://images.pling.com/img/failed.png","error":"HTTP 404"},'
printf '{"url":"https://images.pling.com/img/escaped.png","path":"%s/../../../.ssh/id.png"}]}\\n' "$folder"
"""


class RemotePreviewTest(unittest.TestCase):
    def test_previews_settle_once_and_only_as_cached_files(self):
        self.assertIsNotNone(shutil.which("quickshell"), "quickshell is required for controller tests")
        with tempfile.TemporaryDirectory(prefix="theme-manager-qml-") as temporary:
            target = Path(temporary)
            (target / "runtime").mkdir()
            (target / "session").mkdir(mode=0o700)
            (target / "home").mkdir(mode=0o700)
            helper = target / "helper" / "fake-helper"
            helper.parent.mkdir()
            helper.write_text(FAKE_HELPER)
            helper.chmod(0o700)
            shutil.copy(ROOT / "tests/qml/remote-preview.qml", target / "shell.qml")
            shutil.copytree(ROOT / "omakit", target / "omakit")
            for name in ("RemotePreviewController.qml", "WallpaperBrowserModel.js"):
                shutil.copy(ROOT / "v0200" / name, target / "runtime" / name)
            environment = {
                "PATH": "/usr/bin", "LANG": "C.UTF-8", "HOME": str(target / "home"),
                "XDG_RUNTIME_DIR": str(target / "session"), "FAKE_HELPER": str(helper),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
            }
            result = subprocess.run(
                ["/usr/bin/quickshell", "-p", str(target)], env=environment,
                capture_output=True, text=True, timeout=20,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("REMOTE PREVIEW FAIL", output)
            self.assertNotRegex(output, r"TypeError|ReferenceError|Failed to load configuration")
            self.assertIn("REMOTE PREVIEW PASS", output)
            calls = (helper.parent / "calls").read_text().splitlines()
            self.assertEqual(calls, [
                "--preview https://images.pling.com/img/good.png"
                " --preview https://images.pling.com/img/failed.png"
                " --preview https://images.pling.com/img/escaped.png --json"
            ])


if __name__ == "__main__":
    unittest.main()
