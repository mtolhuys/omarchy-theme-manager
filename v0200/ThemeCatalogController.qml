import QtQuick
import "../omakit"
import "ThemeCatalogModel.js" as ThemeCatalogModel

Item {
  id: root

  property string catalogScriptPath: ""
  property string installScriptPath: ""
  // The closed environment the helpers run in: XDG paths and, for the
  // install, the session variables `omarchy theme install` needs
  // (ImagePicker.qml names them).
  property var helperEnvironment: ({})
  property var omarchyEnvironment: ({})
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
  readonly property int resourceLimitExitCode: 65

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
    catalogProc.start()
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
    installProc.start()
  }

  // catalog.sh renders at most OUTPUT_MAX_BYTES (4 MiB) from a cache it
  // refreshes with curl under its own 10 s connect and 30 s total limits;
  // 45 s covers that refresh, and the cap is the script's own output bound.
  Run {
    id: catalogProc
    environment: root.helperEnvironment
    deadlineMs: 45000
    maxBytes: 4194304
    keepBytes: 4194304

    onFinished: function(result) {
      root.loading = false
      root.catalogStderr = String(result.stderr || "").trim()
      if (result.state !== "ok") {
        root.rows = []
        root.errorMessage = root.catalogStderr || (result.state === "timeout"
          ? "The theme catalog did not answer in time"
          : "Could not load the theme catalog")
        root.focusRequested()
        return
      }
      try {
        const parsed = JSON.parse(String(result.stdout || "{}"))
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

  // install-theme.py bounds its own download to 60 s (DOWNLOAD_SECONDS) and
  // 89 MiB, then `omarchy theme install` applies the sanitized copy: 120 s is
  // the download's own limit twice over, and the output is one slug line.
  Run {
    id: installProc
    property var targetEntry: null
    environment: root.omarchyEnvironment
    deadlineMs: 120000
    maxBytes: 65536

    onFinished: function(result) {
      const installedEntry = targetEntry
      targetEntry = null
      root.busy = false
      root.installStderr = String(result.stderr || "").trim()
      const exitCode = result.state === "ok" ? 0 : (typeof result.exitCode === "number" ? result.exitCode : -1)

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
      } else if (exitCode === root.resourceLimitExitCode && installedEntry) {
        root.sourceFallbackRepository = String(installedEntry.repositoryUrl || "")
        root.errorMessage = root.installStderr
          || "This theme exceeds Theme Manager's safety limits — view the source for details"
        root.focusRequested()
      } else {
        root.sourceFallbackRepository = ""
        root.errorMessage = root.installStderr
          || (result.state === "timeout" ? "Theme install did not finish within two minutes" : "")
          || "Could not install " + (installedEntry ? installedEntry.displayName : "the theme")
        root.focusRequested()
      }
    }
  }

}
