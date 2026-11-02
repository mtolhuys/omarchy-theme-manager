import Quickshell
import QtQuick
import "../omakit"
import "WallpaperBrowserModel.js" as WallpaperBrowserModel

// Theme catalog and Pling icon previews are community URLs. The shell decodes
// images in its own process, so a card never loads one by URL: it asks for it
// here, wallpaper-catalog.py --preview fetches and strips it into the plugin's
// cache, and the card shows that file. Requests queue while one batch runs.
Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string commandPath: "wallpaper-catalog"
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (homeDir + "/.cache")
  property var helperEnvironment: ({})
  // URL -> cached path, or "" once the helper had no preview for it.
  property var paths: ({})
  property int epoch: 0
  property var queued: []

  function pathFor(url) {
    const key = String(url || "")
    return epoch >= 0 && key && Object.prototype.hasOwnProperty.call(paths, key) ? paths[key] : ""
  }

  function settled(url) {
    return Object.prototype.hasOwnProperty.call(paths, String(url || ""))
  }

  function request(url) {
    const key = String(url || "")
    if (!key || settled(key) || queued.indexOf(key) >= 0 || previewProc.batch.indexOf(key) >= 0) return
    queued = queued.concat([key])
    Qt.callLater(root.startNext)
  }

  function startNext() {
    if (previewProc.running || queued.length === 0) return
    const batch = queued.slice(0, WallpaperBrowserModel.maxPreviewsPerRequest)
    queued = queued.slice(batch.length)
    const command = WallpaperBrowserModel.previewArguments(batch)
    command[0] = root.commandPath
    previewProc.batch = batch
    previewProc.command = command
    previewProc.start()
  }

  // Twelve previews of up to 12 MiB, four at a time, each under the helper's
  // 30 s socket timeout: 120 s covers a slow link, and the report is one
  // short JSON line per preview.
  Run {
    id: previewProc

    property var batch: []
    environment: root.helperEnvironment
    deadlineMs: 120000
    maxBytes: 65536

    onFinished: function(result) {
      // A run that failed as a whole settles nothing: a card asks again when
      // it next comes into view.
      if (result.state !== "ok") {
        batch = []
        Qt.callLater(root.startNext)
        return
      }
      const resolved = WallpaperBrowserModel.parsePreviewResponse(result.stdout, batch, root.cacheHome)
      const next = Object.assign({}, root.paths)
      for (const url in resolved) next[url] = resolved[url]
      batch = []
      root.paths = next
      root.epoch += 1
      Qt.callLater(root.startNext)
    }
  }
}
