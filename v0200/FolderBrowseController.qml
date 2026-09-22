import Quickshell
import QtQuick
import "../omakit"
import "FolderBrowseModel.js" as FolderBrowseModel

// One directory at a time, through browse-folder.sh. Every path is normalized
// against the home directory here before the helper sees it, and the helper
// resolves and checks it again; a listing that arrives for a directory the
// user has already left is dropped on its serial.
Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string scriptPath: ""
  // The closed environment browse-folder.sh runs in: the XDG paths, for the
  // thumbnail cache Omarchy's own picker fills (ImagePicker.qml names them).
  property var helperEnvironment: ({})
  property bool showHidden: false
  property int requestSerial: 0
  property string errorMessage: ""

  readonly property bool loading: listProc.running
  // browse-folder.sh stops emitting at 1 MiB; this leaves room for the rows
  // that ceiling admits without ever letting the stream run away.
  readonly property int maxListingBytes: 2 * 1024 * 1024

  signal listingReady(string directory, var listing)
  signal listingFailed(string directory, string message)

  function reset() {
    requestSerial += 1
    errorMessage = ""
  }

  function open(path) {
    const target = FolderBrowseModel.normalizeDir(path, homeDir)
    if (!scriptPath || !target) {
      errorMessage = "That folder is outside your home directory"
      listingFailed(String(path || ""), errorMessage)
      return false
    }

    requestSerial += 1
    errorMessage = ""
    listProc.activeSerial = requestSerial
    listProc.activeDirectory = target
    const command = [scriptPath, target]
    if (showHidden) command.push("--hidden")
    listProc.command = command
    listProc.start()
    return true
  }

  // browse-folder.sh runs one find per directory it previews, so a cold cache
  // over a network home is the slow case: 30 s covers it, and the output is
  // bounded by the helper before Run's own ceiling is reached.
  Run {
    id: listProc

    property int activeSerial: 0
    property string activeDirectory: ""
    environment: root.helperEnvironment
    deadlineMs: 30000
    maxBytes: root.maxListingBytes
    keepBytes: root.maxListingBytes

    onFinished: function(result) {
      if (activeSerial !== root.requestSerial) return

      if (result.state === "ok") {
        root.errorMessage = ""
        root.listingReady(
          activeDirectory,
          FolderBrowseModel.parseListing(result.stdout, activeDirectory, root.homeDir))
        return
      }

      root.errorMessage = result.state === "timeout"
        ? "Reading this folder took too long"
        : (result.state === "overflow"
            ? "This folder holds more than the picker can list"
            : "This folder could not be read")
      root.listingFailed(activeDirectory, root.errorMessage)
    }
  }
}
