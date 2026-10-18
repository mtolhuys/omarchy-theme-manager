import QtQuick
import "../omakit"

// Applying a selection is the picker's responsibility, even when its caller
// only consumes the returned filename (for example cross-navigation).
Item {
  id: root
  property string commandPath: ""
  property var helperEnvironment: ({})
  readonly property bool busy: applyProc.running
  signal applied(string path, int serial)
  signal failed(string message, int serial)

  function apply(path, serial) {
    if (busy || !commandPath || typeof path !== "string" || path.charAt(0) !== "/"
        || /[\u0000-\u001f\u007f]/.test(path)) return false
    applyProc.targetPath = path
    applyProc.requestSerial = serial
    applyProc.command = [commandPath, path]
    applyProc.start()
    return true
  }

  function cancel() { applyProc.cancel() }

  Run {
    id: applyProc
    property string targetPath: ""
    property int requestSerial: 0
    environment: root.helperEnvironment
    deadlineMs: 15000
    maxBytes: 65536
    onFinished: function(result) {
      if (result.state === "ok") root.applied(targetPath, requestSerial)
      else root.failed("Could not apply wallpaper (" + result.state + "): "
        + String(result.stderr || result.reason || "The background command failed").trim(), requestSerial)
    }
  }
}
