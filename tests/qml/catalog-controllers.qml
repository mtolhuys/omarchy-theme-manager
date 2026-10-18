import QtQuick
import Quickshell
import "runtime"
import "runtime/ImagePickerModel.js" as ImagePickerModel

// No window, compositor, user session or installed plugin is used here.
ShellRoot {
  id: suite
  property int stage: 0
  property int themeResponses: 0
  property int wallpaperResponses: 0
  property string fixtureCase: "ok"
  property double resetAt: 0
  property int appliedCount: 0
  property int applyFailures: 0
  readonly property string chosenPath: Quickshell.env("HOME") + "/wallpapers/with spaces.png"

  function check(value, message) {
    if (!value) {
      console.log("CONTROLLERS FAIL " + message)
      Qt.quit()
      return false
    }
    return true
  }

  ThemeCatalogController {
    id: themes
    pickerOpen: true
    inventoryReady: true
    catalogScriptPath: Quickshell.env("FIXTURE_DIR") + "/themes"
    installScriptPath: Quickshell.env("FIXTURE_DIR") + "/themes"
    helperEnvironment: ({ FIXTURE_CASE: suite.fixtureCase })
    onCatalogLoaded: delivered => {
      const rows = ImagePickerModel.signalRows(delivered)
      if (suite.check(Array.isArray(rows) && rows.length === 1 && Array.isArray(rows[0].apps), "theme signal rows and nested lists are arrays")) suite.themeResponses++
    }
  }
  WallpaperBrowserController {
    id: wallpapers
    commandPath: Quickshell.env("FIXTURE_DIR") + "/wallpapers"
    cacheHome: Quickshell.env("HOME") + "/.cache"
    helperEnvironment: ({ FIXTURE_CASE: suite.fixtureCase })
    onResultsReady: delivered => {
      const rows = ImagePickerModel.signalRows(delivered)
      if (suite.check(Array.isArray(rows) && rows.length === 1, "wallpaper rows survived Run as an array")) suite.wallpaperResponses++
    }
  }

  WallpaperApplyController {
    id: applyWallpaper
    commandPath: Quickshell.env("FIXTURE_DIR") + "/apply"
    helperEnvironment: ({ FIXTURE_CASE: suite.fixtureCase })
    onApplied: function(path, serial) {
      if (suite.check(path === suite.chosenPath && serial === 17, "apply preserves path and request identity")) suite.appliedCount++
    }
    onFailed: function(message, serial) {
      if (suite.check(message.indexOf("Fixture provider is unavailable") >= 0 && serial === 18, "apply failure is reported")) suite.applyFailures++
    }
  }

  Timer {
    interval: 200
    running: true
    repeat: true
    onTriggered: {
      if (suite.stage === 0) {
        suite.stage = 1
        themes.load()
        wallpapers.search("", false)
      } else if (suite.stage === 1 && !themes.loading && !wallpapers.loading) {
        if (!suite.check(suite.themeResponses === 1 && suite.wallpaperResponses === 1, "initial results")) return
        themes.selectedEntry = themes.rows[0]
        if (!suite.check(themes.canInstallSelected, "ready inventory enables installation")) return
        themes.inventoryReady = false
        if (!suite.check(!themes.canInstallSelected, "missing inventory blocks installation")) return
        themes.pendingEntry = themes.selectedEntry
        themes.confirmInstall()
        if (!suite.check(!themes.busy, "confirmation cannot bypass the inventory gate")) return
        // Browsing itself remains available while the inventory is unavailable.
        suite.fixtureCase = "failure"
        suite.stage = 2
        themes.load()
        wallpapers.search("", false)
      } else if (suite.stage === 2 && !themes.loading && !wallpapers.loading) {
        if (!suite.check(!!themes.errorMessage && !!wallpapers.errorMessage, "failed requests remain visible")) return
        suite.fixtureCase = "ok"
        suite.stage = 3
        themes.load()
        wallpapers.search("", false)
      } else if (suite.stage === 3 && !themes.loading && !wallpapers.loading) {
        if (!suite.check(suite.themeResponses === 2 && suite.wallpaperResponses === 2, "retry recovers both catalogs")) return
        if (!suite.check(!themes.errorMessage && !wallpapers.errorMessage, "retry clears failure")) return
        suite.fixtureCase = "slow"
        suite.stage = 4
        wallpapers.search("old request", false)
      } else if (suite.stage === 4) {
        wallpapers.reset()
        suite.fixtureCase = "ok"
        suite.resetAt = Date.now()
        suite.stage = 5
        wallpapers.search("new request", false)
      } else if (suite.stage === 5 && !wallpapers.loading) {
        if (!suite.check(suite.wallpaperResponses === 3, "cancelled response was ignored")) return
        if (!suite.check(Date.now() - suite.resetAt < 2000, "reset cancels the slow request before retry")) return
        suite.stage = 6
        if (!suite.check(applyWallpaper.apply(suite.chosenPath, 17), "wallpaper application starts")) return
      } else if (suite.stage === 6 && !applyWallpaper.busy) {
        if (!suite.check(suite.appliedCount === 1, "wallpaper command completed before success")) return
        suite.fixtureCase = "failure"
        suite.stage = 7
        applyWallpaper.apply(suite.chosenPath, 18)
      } else if (suite.stage === 7 && !applyWallpaper.busy) {
        if (!suite.check(suite.appliedCount === 1 && suite.applyFailures === 1, "failed apply never reports success")) return
        console.log("CONTROLLERS PASS")
        Qt.quit()
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: { console.log("CONTROLLERS FAIL timed out"); Qt.quit() }
  }
}
