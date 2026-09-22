import QtQuick
import "../omakit"
import "IconBrowseModel.js" as IconBrowseModel

Item {
  id: root

  property string scriptPath: ""
  // The closed environment icons-browse.sh runs in (ImagePicker.qml names it).
  property var helperEnvironment: ({})
  property string sorting: "new"
  property int pagesize: IconBrowseModel.defaultPageSize
  property int requestSerial: 0
  property int installSerial: 0
  readonly property int maxSearchOutputBytes: 2 * 1024 * 1024
  readonly property int maxInstallOutputBytes: 16 * 1024
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
    searchProc.command = command
    searchProc.start()
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
    installProc.command = command
    installProc.start()
  }

  // icons-browse.sh search: one OCS API page through curl under the
  // script's own 2 MiB and timeout limits; 45 s covers a slow API, and the
  // cap is the script's own bound (maxSearchOutputBytes) plus the error cap.
  Run {
    id: searchProc

    property int activeSerial: 0
    property string activeQuery: ""
    property string activeFilterKey: ""
    property int activePage: 0
    property bool activeAppend: false
    environment: root.helperEnvironment
    deadlineMs: 45000
    maxBytes: root.maxSearchOutputBytes
    keepBytes: root.maxSearchOutputBytes

    onFinished: function(result) {
      const isCurrent = activeSerial === root.requestSerial

      if (isCurrent && result.state === "overflow") {
        root.errorMessage = "Icon catalog returned too much output"
      } else if (isCurrent && result.state === "ok") {
        const parsed = IconBrowseModel.parseSearchResponse(result.stdout)
        if (parsed.error) {
          root.errorMessage = parsed.error
        } else {
          root.activeQuery = activeQuery
          root.activeFilterKey = activeFilterKey
          root.currentPage = parsed.meta.page
          root.totalResults = parsed.meta.total
          root.hasMore = parsed.meta.hasMore === true
          root.errorMessage = ""
          root.resultsReady(parsed.rows, activeAppend)
        }
      } else if (isCurrent) {
        root.errorMessage = IconBrowseModel.errorFromStderr(
          result.stderr,
          result.state === "timeout"
            ? "Pling did not answer within 45 seconds"
            : "Could not search Pling icon themes"
        )
      }

      if (root.queuedRequest) Qt.callLater(root.startQueuedSearch)
      else root.focusRequested()
    }
  }

  // icons-browse.sh install: a download of up to 200 MiB under the
  // script's own curl limits and an extraction of up to 50,000 files;
  // 5 minutes covers that on a slow link, and its report is one JSON line
  // (maxInstallOutputBytes).
  Run {
    id: installProc

    property int activeSerial: 0
    property string targetName: ""
    environment: root.helperEnvironment
    deadlineMs: 300000
    maxBytes: root.maxInstallOutputBytes

    onFinished: function(result) {
      if (activeSerial !== root.installSerial) return

      root.installStderr = result.stderr
      if (result.state === "overflow") {
        root.errorMessage = "Icon install returned too much output"
        root.focusRequested()
      } else if (result.state === "ok") {
        const parsed = IconBrowseModel.parseInstallResponse(result.stdout)
        if (parsed.error) {
          root.errorMessage = parsed.error
          root.focusRequested()
        } else {
          root.errorMessage = ""
          root.iconInstalled(parsed.themeName, parsed.themeNames)
        }
      } else {
        root.errorMessage = IconBrowseModel.errorFromStderr(
          result.stderr,
          result.state === "timeout"
            ? "Installing " + (targetName || "the icon theme") + " did not finish within five minutes"
            : "Could not install " + (targetName || "the icon theme")
        )
        root.focusRequested()
      }
    }
  }
}
