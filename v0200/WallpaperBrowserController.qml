import Quickshell
import QtQuick
import "../omakit"
import "WallpaperBrowserModel.js" as WallpaperBrowserModel

Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (homeDir + "/.cache")
  property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
  // The closed environment aether runs in: XDG paths for its cache
  // (ImagePicker.qml names them).
  property var helperEnvironment: ({})
  property int pagesPerRequest: 2
  property string categories: "111"
  property string sorting: "date_added"
  property string order: "desc"
  property string atLeast: "1920x1080"
  property string colors: ""
  property int requestSerial: 0
  property int downloadSerial: 0
  readonly property int maxSearchOutputBytes: 4 * 1024 * 1024
  readonly property int maxDownloadOutputBytes: 8 * 1024
  property var queuedRequest: null
  property string activeQuery: ""
  property string activeFilterKey: ""
  property int nextRawPage: 1
  property int currentPage: 0
  property int lastPage: 0
  property int totalResults: 0
  property string errorMessage: ""
  property bool downloading: downloadProc.running
  readonly property bool loading: searchProc.running || queuedRequest !== null
  readonly property bool hasMore: currentPage > 0 && currentPage < lastPage

  signal resultsReady(var rows, bool append)
  signal wallpaperReady(string path)
  signal focusRequested()

  function reset() {
    requestSerial += 1
    downloadSerial += 1
    queuedRequest = null
    activeQuery = ""
    activeFilterKey = ""
    nextRawPage = 1
    currentPage = 0
    lastPage = 0
    totalResults = 0
    errorMessage = ""
  }

  function search(query, append) {
    const normalizedQuery = WallpaperBrowserModel.normalizeQuery(query)
    const filters = WallpaperBrowserModel.normalizeFilters({
      categories: categories,
      sorting: sorting,
      order: order,
      atLeast: atLeast,
      colors: colors
    })
    const nextFilterKey = WallpaperBrowserModel.filterKey(filters)
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
      page: append === true ? nextRawPage : 1
    }
    if (append !== true) errorMessage = ""
    if (!searchProc.running) startQueuedSearch()
  }

  function startQueuedSearch() {
    if (!queuedRequest || searchProc.running) return

    const request = queuedRequest
    queuedRequest = null
    searchProc.activeSerial = request.serial
    searchProc.activeQuery = request.query
    searchProc.activeFilterKey = request.filterKey
    searchProc.activePage = request.page
    searchProc.activeAppend = request.append
    searchProc.command = WallpaperBrowserModel.searchArguments(
      request.query,
      request.page,
      pagesPerRequest,
      request.filters
    )
    searchProc.start()
  }

  function loadMore() {
    search(activeQuery, true)
  }

  function download(id) {
    if (downloadProc.running) return

    const command = WallpaperBrowserModel.downloadArguments(id)
    if (command.length === 0) {
      errorMessage = "The selected Wallhaven wallpaper has an invalid id"
      focusRequested()
      return
    }

    errorMessage = ""
    downloadSerial += 1
    downloadProc.activeSerial = downloadSerial
    downloadProc.command = command
    downloadProc.start()
  }

  // aether --wallhaven-thumbs fetches two pages of thumbnails; 60 s covers
  // a slow link, and the cap is the browser's own 4 MiB search bound plus
  // the error bound.
  Run {
    id: searchProc

    property int activeSerial: 0
    property string activeQuery: ""
    property string activeFilterKey: ""
    property int activePage: 1
    property bool activeAppend: false
    environment: root.helperEnvironment
    deadlineMs: 60000
    maxBytes: root.maxSearchOutputBytes
    keepBytes: root.maxSearchOutputBytes

    onFinished: function(result) {
      const isCurrent = activeSerial === root.requestSerial

      if (isCurrent && result.state === "overflow") {
        root.errorMessage = "Aether returned too much Wallhaven output"
      } else if (isCurrent && result.state === "ok") {
        const parsed = WallpaperBrowserModel.parseSearchResponse(
          result.stdout,
          root.cacheHome
        )
        if (parsed.error) {
          root.errorMessage = parsed.error
        } else {
          root.activeQuery = activeQuery
          root.activeFilterKey = activeFilterKey
          root.currentPage = parsed.meta.currentPage
          root.lastPage = parsed.meta.lastPage
          root.totalResults = parsed.meta.total
          root.nextRawPage = activePage + root.pagesPerRequest
          root.errorMessage = ""
          root.resultsReady(parsed.rows, activeAppend)
        }
      } else if (isCurrent) {
        root.errorMessage = WallpaperBrowserModel.errorFromStderr(
          result.stderr,
          result.state === "timeout"
            ? "Wallhaven did not answer within 60 seconds"
            : "Wallhaven search failed. Aether 4.19 or newer is required."
        )
      }

      if (root.queuedRequest) Qt.callLater(root.startQueuedSearch)
      else root.focusRequested()
    }
  }

  // aether --wallhaven-download fetches one full-size wallpaper, up to a
  // few tens of MiB; 120 s covers a slow link, and its report is one JSON
  // line (maxDownloadOutputBytes).
  Run {
    id: downloadProc

    property int activeSerial: 0
    environment: root.helperEnvironment
    deadlineMs: 120000
    maxBytes: root.maxDownloadOutputBytes

    onFinished: function(result) {
      if (activeSerial !== root.downloadSerial) return

      if (result.state === "overflow") {
        root.errorMessage = "Aether returned too much download output"
      } else if (result.state === "ok") {
        const parsed = WallpaperBrowserModel.parseDownloadResponse(
          result.stdout,
          root.homeDir,
          root.dataHome
        )
        if (parsed.error) root.errorMessage = parsed.error
        else root.wallpaperReady(parsed.path)
      } else {
        root.errorMessage = WallpaperBrowserModel.errorFromStderr(
          result.stderr,
          result.state === "timeout"
            ? "The wallpaper download did not finish within two minutes"
            : "Aether could not download this wallpaper"
        )
      }

      root.focusRequested()
    }
  }
}
