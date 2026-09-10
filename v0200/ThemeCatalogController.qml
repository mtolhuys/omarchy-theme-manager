import Quickshell.Io
import QtQuick
import "ThemeCatalogModel.js" as ThemeCatalogModel

Item {
  id: root

  property string catalogScriptPath: ""
  property bool pickerOpen: false
  property var installedThemes: ({})
  property var stockThemes: ({})
  property var installedRepositories: []
  property var payload: ({})
  property var rows: []
  property var selectedEntry: null
  property bool loading: false
  property string catalogStderr: ""
  property string errorMessage: ""

  readonly property bool canOpenSelected: !!selectedEntry
    && ThemeCatalogModel.normalizeRepositoryUrl(selectedEntry.repositoryUrl) !== ""

  signal catalogLoaded(var rows)
  signal openRepositoryRequested(string url)
  signal focusRequested()

  onPickerOpenChanged: if (!pickerOpen) errorMessage = ""
  onSelectedEntryChanged: errorMessage = ""
  onInstalledThemesChanged: rebuildRows(false)
  onStockThemesChanged: rebuildRows(false)
  onInstalledRepositoriesChanged: rebuildRows(false)

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
    if (loading || !catalogScriptPath) return

    loading = true
    errorMessage = ""
    catalogStderr = ""
    catalogProc.command = [catalogScriptPath]
    catalogProc.running = true
  }

  function openSelectedRepository() {
    const repositoryUrl = selectedEntry
      ? ThemeCatalogModel.normalizeRepositoryUrl(selectedEntry.repositoryUrl)
      : ""
    if (!repositoryUrl) return
    openRepositoryRequested(repositoryUrl)
    focusRequested()
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

}
