import Quickshell.Io
import QtQuick
import "IconBrowseModel.js" as IconBrowseModel

Item {
  id: root

  property string scriptPath: ""
  property string sorting: "new"
  property int pagesize: IconBrowseModel.defaultPageSize
  property int requestSerial: 0
  property int installSerial: 0
  readonly property int maxSearchOutputBytes: 2 * 1024 * 1024
  readonly property int maxInstallOutputBytes: 16 * 1024
  readonly property int maxErrorOutputBytes: 64 * 1024
  property var queuedRequest: null
  property string activeQuery: ""
  property string activeFilterKey: ""
  property int currentPage: -1
  property int totalResults: 0
  property bool hasMore: false
  property string errorMessage: ""
  property bool confirmationOpen: false
  property var pendingEntry: null
  property string installStderr: ""
  readonly property bool downloading: installProc.running
  readonly property bool loading: searchProc.running || queuedRequest !== null
  readonly property string confirmationMessage:
    IconBrowseModel.installConfirmationMessage(pendingEntry)

  signal resultsReady(var rows, bool append)
  signal iconInstalled(string themeName, var themeNames)
  signal focusRequested()

  function reset() {
    requestSerial += 1
    installSerial += 1
    queuedRequest = null
    activeQuery = ""
    activeFilterKey = ""
    currentPage = -1
    totalResults = 0
    hasMore = false
    errorMessage = ""
    confirmationOpen = false
    pendingEntry = null
    installStderr = ""
  }

  function search(query, append) {
    if (!scriptPath) {
      errorMessage = "Icon browse helper is unavailable"
      focusRequested()
      return
    }

    const normalizedQuery = IconBrowseModel.normalizeQuery(query)
    const filters = IconBrowseModel.normalizeFilters({ sorting: sorting })
    const nextFilterKey = IconBrowseModel.filterKey(filters)
    if (append && (loading
                   || !hasMore
                   || normalizedQuery !== activeQuery
                   || nextFilterKey !== activeFilterKey)) return

    requestSerial += 1
    queuedRequest = {
      serial: requestSerial,
      query: normalizedQuery,
      filters: filters,
      filterKey: nextFilterKey,
      append: append === true,
      page: append === true ? currentPage + 1 : 0
    }
    if (append !== true) errorMessage = ""
    if (!searchProc.running) startQueuedSearch()
  }

  function startQueuedSearch() {
    if (!queuedRequest || searchProc.running) return

    const request = queuedRequest
    queuedRequest = null
    const command = IconBrowseModel.searchArguments(
      scriptPath,
      request.query,
      request.page,
      request.filters,
      pagesize
    )
    if (command.length === 0) {
      errorMessage = "Icon browse helper path is invalid"
      focusRequested()
      return
    }

    searchProc.activeSerial = request.serial
    searchProc.activeQuery = request.query
    searchProc.activeFilterKey = request.filterKey
    searchProc.activePage = request.page
    searchProc.activeAppend = request.append
    searchProc.outputTooLarge = false
    searchProc.stdoutText = ""
    searchProc.stderrText = ""
    searchProc.command = command
    searchProc.running = true
  }

  function loadMore() {
    search(activeQuery, true)
  }

  function requestInstall(entry) {
    if (!entry || !entry.id || downloading || loading) return
    pendingEntry = entry
    confirmationOpen = true
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
    if (!entry || !entry.id || downloading) {
      focusRequested()
      return
    }

    const command = IconBrowseModel.installArguments(scriptPath, entry.id)
    if (command.length === 0) {
      errorMessage = "The selected icon pack has an invalid id"
      focusRequested()
      return
    }

    errorMessage = ""
    installStderr = ""
    installSerial += 1
    installProc.activeSerial = installSerial
    installProc.targetName = String(entry.displayName || entry.name || entry.id)
    installProc.outputTooLarge = false
    installProc.stdoutText = ""
    installProc.stderrText = ""
    installProc.command = command
    installProc.running = true
  }

  Process {
    id: searchProc

    property int activeSerial: 0
    property string activeQuery: ""
    property string activeFilterKey: ""
    property int activePage: 0
    property bool activeAppend: false
    property bool outputTooLarge: false
    property string stdoutText: ""
    property string stderrText: ""

    stdout: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!searchProc.outputTooLarge
            && data.length > root.maxSearchOutputBytes) {
          searchProc.outputTooLarge = true
          searchProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!searchProc.outputTooLarge)
          searchProc.stdoutText = String(text || "")
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!searchProc.outputTooLarge
            && data.length > root.maxErrorOutputBytes) {
          searchProc.outputTooLarge = true
          searchProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!searchProc.outputTooLarge)
          searchProc.stderrText = String(text || "")
      }
    }

    onExited: function(exitCode) {
      const isCurrent = activeSerial === root.requestSerial

      if (isCurrent && outputTooLarge) {
        root.errorMessage = "Icon catalog returned too much output"
      } else if (isCurrent && exitCode === 0) {
        const result = IconBrowseModel.parseSearchResponse(stdoutText)
        if (result.error) {
          root.errorMessage = result.error
        } else {
          root.activeQuery = activeQuery
          root.activeFilterKey = activeFilterKey
          root.currentPage = result.meta.page
          root.totalResults = result.meta.total
          root.hasMore = result.meta.hasMore === true
          root.errorMessage = ""
          root.resultsReady(result.rows, activeAppend)
        }
      } else if (isCurrent) {
        root.errorMessage = IconBrowseModel.errorFromStderr(
          stderrText,
          "Could not search Pling icon themes"
        )
      }

      if (root.queuedRequest) Qt.callLater(root.startQueuedSearch)
      else root.focusRequested()
    }
  }

  Process {
    id: installProc

    property int activeSerial: 0
    property string targetName: ""
    property bool outputTooLarge: false
    property string stdoutText: ""
    property string stderrText: ""

    stdout: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!installProc.outputTooLarge
            && data.length > root.maxInstallOutputBytes) {
          installProc.outputTooLarge = true
          installProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!installProc.outputTooLarge)
          installProc.stdoutText = String(text || "")
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!installProc.outputTooLarge
            && data.length > root.maxErrorOutputBytes) {
          installProc.outputTooLarge = true
          installProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!installProc.outputTooLarge)
          installProc.stderrText = String(text || "")
      }
    }

    onExited: function(exitCode) {
      if (activeSerial !== root.installSerial) return

      root.installStderr = stderrText
      if (outputTooLarge) {
        root.errorMessage = "Icon install returned too much output"
        root.focusRequested()
      } else if (exitCode === 0) {
        const result = IconBrowseModel.parseInstallResponse(stdoutText)
        if (result.error) {
          root.errorMessage = result.error
          root.focusRequested()
        } else {
          root.errorMessage = ""
          root.iconInstalled(result.themeName, result.themeNames)
        }
      } else {
        root.errorMessage = IconBrowseModel.errorFromStderr(
          stderrText,
          "Could not install " + (targetName || "the icon theme")
        )
        root.focusRequested()
      }
    }
  }
}
