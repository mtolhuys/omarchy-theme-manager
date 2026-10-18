import QtQuick
import Quickshell
import "runtime"

// No window, compositor, user session or installed plugin is used here.
ShellRoot {
  id: suite
  property int stage: 0
  property int themeResponses: 0
  property int wallpaperResponses: 0
  property string fixtureCase: "ok"
  property double resetAt: 0

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
    onCatalogLoaded: rows => {
      if (suite.check(rows.length === 1, "theme rows survived Run")) suite.themeResponses++
    }
  }
  WallpaperBrowserController {
    id: wallpapers
    commandPath: Quickshell.env("FIXTURE_DIR") + "/wallpapers"
    cacheHome: Quickshell.env("HOME") + "/.cache"
    helperEnvironment: ({ FIXTURE_CASE: suite.fixtureCase })
    onResultsReady: rows => {
      if (suite.check(rows.length === 1, "wallpaper rows survived Run")) suite.wallpaperResponses++
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
