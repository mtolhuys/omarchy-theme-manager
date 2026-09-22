import Quickshell
import Quickshell.Io
import QtQuick
import "../omakit"
import "ThemeManagerModel.js" as ThemeManagerModel

Item {
  id: root

  property string selectedPath: ""
  property bool pickerOpen: false
  property string inventoryScriptPath: ""
  // Omarchy's bin directory, for `omarchy theme remove`; the closed
  // environment every helper runs in, with the session variables the
  // Omarchy command needs (ImagePicker.qml names them).
  property string omarchyBin: ""
  property var helperEnvironment: ({})
  property var omarchyEnvironment: ({})
  property string currentThemeName: ""
  property var installedThemes: ({})
  property var stockThemes: ({})
  property var installedRepositories: []
  property var packageIcons: ({})
  property bool inventoryReady: false
  property bool confirmationOpen: false
  property bool busy: false
  property string pendingTheme: ""
  property string errorMessage: ""
  property string uninstallStderr: ""

  readonly property string currentThemeFile: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  readonly property string selectedThemeName: ThemeManagerModel.themeNameForPath(selectedPath)
  readonly property bool themePickerActive: selectedThemeName !== ""
  readonly property bool selectedThemeInstalled: inventoryReady
    && ThemeManagerModel.hasTheme(installedThemes, selectedThemeName)
  readonly property bool selectedThemeIsCurrent: themePickerActive
    && selectedThemeName === currentThemeName
  readonly property bool canUninstallSelectedTheme: selectedThemeInstalled
    && ThemeManagerModel.isSafeThemeName(selectedThemeName)
    && !selectedThemeIsCurrent
    && !busy

  signal themeRemoved(string name)
  signal focusRequested()

  onPickerOpenChanged: {
    if (pickerOpen) {
      if (themePickerActive) refreshInventory()
    } else {
      resetTransientState()
    }
  }

  onThemePickerActiveChanged: {
    if (pickerOpen && themePickerActive) refreshInventory()
  }

  onSelectedPathChanged: errorMessage = ""

  function resetTransientState() {
    confirmationOpen = false
    pendingTheme = ""
    errorMessage = ""
  }

  function refreshInventory() {
    if (inventoryProc.running) {
      inventoryProc.refreshQueued = true
      return
    }

    inventoryReady = false
    errorMessage = ""
    inventoryProc.refreshQueued = false
    inventoryProc.command = [inventoryScriptPath]
    inventoryProc.start()
  }

  function requestUninstall() {
    if (!canUninstallSelectedTheme) return

    pendingTheme = selectedThemeName
    confirmationOpen = true
  }

  function cancelUninstall() {
    confirmationOpen = false
    pendingTheme = ""
    focusRequested()
  }

  function confirmUninstall() {
    const themeName = pendingTheme
    confirmationOpen = false
    pendingTheme = ""

    if (themeName !== selectedThemeName
        || !ThemeManagerModel.hasTheme(installedThemes, themeName)
        || !canUninstallSelectedTheme) {
      focusRequested()
      return
    }

    busy = true
    errorMessage = ""
    uninstallStderr = ""
    uninstallProc.targetTheme = themeName
    uninstallProc.command = [omarchyBin + "/omarchy", "theme", "remove", themeName]
    uninstallProc.start()
  }

  FileView {
    path: root.currentThemeFile
    watchChanges: true
    printErrors: false
    onLoaded: root.currentThemeName = String(text() || "").trim()
    onFileChanged: reload()
  }

  // theme-inventory.sh lists directories and reads small files: 10 s is
  // ten times a slow disk, and the whole inventory is well under the 1 MiB
  // cap (a few hundred themes are a few KiB).
  Run {
    id: inventoryProc
    property bool refreshQueued: false
    environment: root.helperEnvironment
    deadlineMs: 10000
    maxBytes: 1048576
    keepBytes: 1048576

    onFinished: function(result) {
      if (result.state === "ok") {
        const inventory = ThemeManagerModel.themeInventoryFromText(String(result.stdout || ""))
        root.installedThemes = inventory.installedThemes
        root.stockThemes = inventory.stockThemes
        root.installedRepositories = inventory.installedRepositories
        root.packageIcons = inventory.packageIcons || ({})
        root.inventoryReady = true
      } else {
        root.installedThemes = ({})
        root.stockThemes = ({})
        root.installedRepositories = []
        root.packageIcons = ({})
        root.inventoryReady = false
        root.errorMessage = "Could not read the installed theme inventory"
      }

      if (refreshQueued) {
        refreshQueued = false
        Qt.callLater(root.refreshInventory)
      }
    }
  }

  // `omarchy theme remove` deletes a directory and restarts parts of the
  // session; 60 s covers a theme switch on a slow machine, and its output
  // is a few lines.
  Run {
    id: uninstallProc
    property string targetTheme: ""
    environment: root.omarchyEnvironment
    deadlineMs: 60000
    maxBytes: 65536

    onFinished: function(result) {
      const removedTheme = targetTheme
      targetTheme = ""
      root.busy = false
      root.uninstallStderr = String(result.stderr || "").trim()

      if (result.state === "ok") {
        root.installedThemes = ThemeManagerModel.withoutTheme(root.installedThemes, removedTheme)
        root.inventoryReady = true
        root.themeRemoved(removedTheme)
      } else {
        root.errorMessage = root.uninstallStderr
          || "Could not uninstall " + ThemeManagerModel.labelForThemeName(removedTheme)
        root.refreshInventory()
      }

      root.focusRequested()
    }
  }
}
