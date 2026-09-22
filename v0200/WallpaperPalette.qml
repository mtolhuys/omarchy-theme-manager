import QtQuick
import qs.Commons
import "../omakit"
import "WallpaperPaletteModel.js" as WallpaperPaletteModel

Item {
  id: root

  property string sourcePath: ""
  property color fallbackBase: Color.background
  property color fallbackAccent: Color.accent
  property color base: fallbackBase
  property color accent: fallbackAccent
  property color secondary: fallbackAccent
  property bool ready: false
  property string sampledPath: ""
  property int sourceGeneration: 0
  property var paletteCache: ({})
  property var paletteCacheOrder: []
  readonly property int paletteCacheLimit: 24

  function reset() {
    ready = false
    sampledPath = ""
    base = fallbackBase
    accent = fallbackAccent
    secondary = fallbackAccent
  }

  function queueSample() {
    sampleDelay.restart()
  }

  function restoreCached(path) {
    const cached = paletteCache[path]
    if (!cached) return false
    base = cached.base
    accent = cached.accent
    secondary = cached.secondary
    sampledPath = path
    ready = true
    return true
  }

  function remember(path, palette) {
    const nextCache = Object.assign({}, paletteCache)
    let nextOrder = paletteCacheOrder.filter(function(entry) { return entry !== path })
    nextCache[path] = palette
    nextOrder.push(path)
    while (nextOrder.length > paletteCacheLimit) {
      const expired = nextOrder.shift()
      delete nextCache[expired]
    }
    paletteCache = nextCache
    paletteCacheOrder = nextOrder
  }

  function startSample() {
    const path = String(sourcePath || "")
    if (!path || path.charAt(0) !== "/") {
      reset()
      return
    }
    if (sampler.running) return
    sampler.activePath = path
    sampler.activeGeneration = sourceGeneration
    sampler.command = [
      "/usr/bin/magick", path + "[0]",
      "-alpha", "off",
      "-thumbnail", "64x64^",
      "-gravity", "center",
      "-extent", "64x64",
      "-colorspace", "sRGB",
      "-depth", "8",
      "-colors", "8",
      "-format", "%c",
      "histogram:info:-"
    ]
    sampler.start()
  }

  onSourcePathChanged: {
    sourceGeneration += 1
    sampleDelay.stop()
    if (restoreCached(String(sourcePath || ""))) return
    reset()
    queueSample()
  }
  onFallbackBaseChanged: if (!ready) base = fallbackBase
  onFallbackAccentChanged: if (!ready) {
    accent = fallbackAccent
    secondary = fallbackAccent
  }
  Component.onCompleted: queueSample()

  Behavior on base { ColorAnimation { duration: 360; easing.type: Easing.OutCubic } }
  Behavior on accent { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
  Behavior on secondary { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }

  Timer {
    id: sampleDelay
    interval: 140
    repeat: false
    onTriggered: root.startSample()
  }

  // ImageMagick reduces one wallpaper to an 8-colour histogram: a few
  // hundred milliseconds for a 4K image, so 15 s is generous, and the
  // histogram is under 8 KiB (the previous slice), the cap 64 KiB.
  Run {
    id: sampler
    property string activePath: ""
    property int activeGeneration: 0
    deadlineMs: 15000
    maxBytes: 65536
    keepBytes: 8192

    onFinished: function(result) {
      const currentPath = String(root.sourcePath || "")
      const sourceChanged = activeGeneration !== root.sourceGeneration
        || activePath !== currentPath
      if (result.state === "ok" && !sourceChanged) {
        const palette = WallpaperPaletteModel.paletteFromHistogram(result.stdout)
        if (palette) {
          root.remember(activePath, palette)
          root.base = palette.base
          root.accent = palette.accent
          root.secondary = palette.secondary
          root.sampledPath = activePath
          root.ready = true
        }
      }
      activePath = ""
      activeGeneration = 0
      // A source change while ImageMagick was running needs one fresh sample.
      // A failed sample of the current source must not become a process loop.
      if (currentPath && sourceChanged && root.sampledPath !== currentPath)
        root.queueSample()
    }
  }
}
