import Quickshell.Io
import QtQuick
import "ThemeCatalogModel.js" as ThemeCatalogModel

Item {
  id: root

  property string catalogScriptPath: ""
  property string installScriptPath: ""
  property bool pickerOpen: false
  property var installedThemes: ({})
  property var stockThemes: ({})
  property var installedRepositories: []
  property var payload: ({})
  property var rows: []
  property var selectedEntry: null
  property bool loading: false
  property bool busy: false
  property bool confirmationOpen: false
  property var pendingEntry: null
  property string catalogStderr: ""
  property string installStderr: ""
  property string errorMessage: ""
  property string sourceFallbackRepository: ""

  readonly property int temporaryFailureExitCode: 75

  readonly property bool canInstallSelected: !!selectedEntry
    && selectedEntry.canInstall === true
    && !busy
  readonly property bool canOpenSelectedSource: !!selectedEntry
    && String(selectedEntry.repositoryUrl || "") === sourceFallbackRepository
    && !busy
  readonly property bool canActivateSelected: canOpenSelectedSource || canInstallSelected
  readonly property string selectedStatus: busy
    ? "Installing…"
    : (canOpenSelectedSource
        ? "View source"
        : (selectedEntry ? String(selectedEntry.status || "Install") : "Install"))
  readonly property string confirmationMessage:
    ThemeCatalogModel.installConfirmationMessage(pendingEntry)

  signal catalogLoaded(var rows)
  signal themeInstalled(string name)
  signal sourceRequested(string repositoryUrl)
  signal focusRequested()

  onPickerOpenChanged: if (!pickerOpen) resetTransientState()
  onSelectedEntryChanged: if (!busy) {
    errorMessage = ""
    sourceFallbackRepository = ""
  }
  onInstalledThemesChanged: rebuildRows(false)
  onStockThemesChanged: rebuildRows(false)
  onInstalledRepositoriesChanged: rebuildRows(false)

  function resetTransientState() {
    confirmationOpen = false
    pendingEntry = null
    errorMessage = ""
    sourceFallbackRepository = ""
  }

  function inventory() {
    return {
      installedThemes,
      stockThemes,
      installedRepositories
    }
  }

  function rebuildRows(notify) {
    if (!payload || !Array.isArray(payload.themes)) return
    rows = ThemeCatalogModel.catalogRows(payload, inventory())
    if (notify === true) catalogLoaded(rows)
  }

  function load() {
    if (loading || busy || !catalogScriptPath) return

    loading = true
    errorMessage = ""
    catalogStderr = ""
    catalogProc.command = [catalogScriptPath]
    catalogProc.running = true
  }

  function requestInstall() {
    if (!canInstallSelected) return
    pendingEntry = selectedEntry
    confirmationOpen = true
  }

  function requestPrimaryAction() {
    if (canOpenSelectedSource) {
      const repositoryUrl = sourceFallbackRepository
      sourceFallbackRepository = ""
      errorMessage = ""
      sourceRequested(repositoryUrl)
      focusRequested()
      return
    }
    requestInstall()
  }

  function cancelInstall() {
    confirmationOpen = false
    pendingEntry = null
    focusRequested()
  }

  function confirmInstall() {
    const entry = pendingEntry
    confirmationOpen = false
    pendingEntry = null

    if (!entry || entry !== selectedEntry || entry.canInstall !== true || busy || !installScriptPath) {
      focusRequested()
      return
    }

    busy = true
    errorMessage = ""
    installStderr = ""
    installProc.targetEntry = entry
    installProc.command = [installScriptPath, entry.repositoryUrl]
    installProc.running = true
  }

  Process {
    id: catalogProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(text || "{}"))
          root.payload = parsed
          root.rebuildRows(true)
          if (root.rows.length === 0)
            root.errorMessage = "No themes were found in the catalog"
        } catch (_) {
          root.rows = []
          root.errorMessage = "The theme catalog returned invalid data"
        }
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.catalogStderr = String(text || "").trim()
        if (!catalogProc.running && root.errorMessage !== "" && root.catalogStderr !== "")
          root.errorMessage = root.catalogStderr
      }
    }

    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        root.rows = []
        root.errorMessage = root.catalogStderr || "Could not load the theme catalog"
        root.focusRequested()
      }
    }
  }

  Process {
    id: installProc
    property var targetEntry: null

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.installStderr = String(text || "").trim()
        if (!installProc.running && root.errorMessage !== "" && root.installStderr !== "")
          root.errorMessage = root.installStderr
      }
    }

    onExited: function(exitCode) {
      const installedEntry = targetEntry
      targetEntry = null
      root.busy = false

      if (exitCode === 0 && installedEntry) {
        root.themeInstalled(installedEntry.installSlug)
      } else if (installedEntry !== root.selectedEntry) {
        root.errorMessage = ""
        root.sourceFallbackRepository = ""
        root.focusRequested()
      } else if (exitCode === root.temporaryFailureExitCode && installedEntry) {
        root.sourceFallbackRepository = String(installedEntry.repositoryUrl || "")
        root.errorMessage = "GitHub rate limit reached — view the source or retry shortly"
        root.focusRequested()
      } else {
        root.sourceFallbackRepository = ""
        root.errorMessage = root.installStderr
          || "Could not install " + (installedEntry ? installedEntry.displayName : "the theme")
        root.focusRequested()
      }
    }
  }

}
