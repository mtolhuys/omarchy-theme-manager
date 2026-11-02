import QtQuick
import Quickshell
import "runtime"

// The real RemotePreviewController against a stand-in helper: duplicate
// requests share one run, every requested URL settles, and only a path in
// the preview cache comes back.
ShellRoot {
  id: root
  readonly property string cacheHome: Quickshell.env("HOME") + "/.cache"
  readonly property string good: "https://images.pling.com/img/good.png"
  readonly property string failed: "https://images.pling.com/img/failed.png"
  readonly property string escaped: "https://images.pling.com/img/escaped.png"
  property bool reported: false

  function check(condition, message) {
    if (condition) return true
    console.log("REMOTE PREVIEW FAIL: " + message)
    return false
  }

  RemotePreviewController {
    id: previews
    commandPath: Quickshell.env("FAKE_HELPER")
    cacheHome: root.cacheHome
    onEpochChanged: if (!root.reported && settled(root.good) && settled(root.failed) && settled(root.escaped)) {
      root.reported = true
      const expected = root.cacheHome + "/omarchy-theme-manager/preview-thumbs/0123456789abcdef0123456789abcdef.png"
      const ok = root.check(pathFor(root.good) === expected, "good preview path: " + pathFor(root.good))
        && root.check(pathFor(root.failed) === "", "failed preview has a path")
        && root.check(pathFor(root.escaped) === "", "escaping path accepted")
      // Settled URLs never start another run.
      request(root.good)
      if (ok) console.log("REMOTE PREVIEW PASS")
      Qt.callLater(function() { Qt.quit() })
    }
  }

  Component.onCompleted: {
    previews.request(good)
    previews.request(good)
    previews.request(failed)
    previews.request(escaped)
  }

  Timer {
    interval: 10000
    running: true
    onTriggered: {
      console.log("REMOTE PREVIEW FAIL: no answer")
      Qt.quit()
    }
  }
}
