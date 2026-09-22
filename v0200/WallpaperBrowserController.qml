import Quickshell
import QtQuick
import "../omakit"
import "WallpaperBrowserModel.js" as WallpaperBrowserModel

Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string commandPath: "wallpaper-catalog"
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (homeDir + "/.cache")
  property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
  // The closed environment wallpaper-catalog.py runs in: the XDG paths for
  // its cache and data roots (ImagePicker.qml names them).
  property var helperEnvironment: ({})
  property int pagesPerRequest: 1
  property string collection: "omarchy"
  property string sorting: "featured"
  property string license: "any"
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
  property bool staleResults: false
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
    staleResults = false
    errorMessage = ""
  }

  function search(query, append) {
    const normalizedQuery = WallpaperBrowserModel.normalizeQuery(query)
    const filters = WallpaperBrowserModel.normalizeFilters({
      collection: collection,
      sorting: sorting,
      license: license
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
    const command = WallpaperBrowserModel.searchArguments(
      request.query,
      request.page,
      pagesPerRequest,
      request.filters
    )
    command[0] = root.commandPath
    searchProc.command = command
    searchProc.start()
  }

  function loadMore() {
    search(activeQuery, true)
  }

  function download(id) {
    if (downloadProc.running) return

    const command = WallpaperBrowserModel.downloadArguments(id)
    if (command.length === 0) {
      errorMessage = "The selected wallpaper has an invalid id"
      focusRequested()
      return
    }

    errorMessage = ""
    downloadSerial += 1
    downloadProc.activeSerial = downloadSerial
    command[0] = root.commandPath
    downloadProc.command = command
    downloadProc.start()
  }

  // wallpaper-catalog.py --wallpaper-thumbs fetches one listing page and its
  // thumbnails, three at a time, each under the provider's own 30 s socket
  // timeout; 120 s covers that on a slow link. Run counts each stream while
  // reading and ends the run over the cap, which is the browser's own 4 MiB
  // search bound (maxSearchOutputBytes); keepBytes matches so the JSON the
  // parser needs survives the trip.
  Run {
    id: searchProc

    property int activeSerial: 0
    property string activeQuery: ""
    property string activeFilterKey: ""
    property int activePage: 1
    property bool activeAppend: false
    environment: root.helperEnvironment
    deadlineMs: 120000
    maxBytes: root.maxSearchOutputBytes
    keepBytes: root.maxSearchOutputBytes

    onFinished: function(result) {
      const isCurrent = activeSerial === root.requestSerial

      if (isCurrent && result.state === "overflow") {
        root.errorMessage = "The wallpaper catalog returned too much output"
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
          root.staleResults = parsed.meta.stale === true
          root.nextRawPage = activePage + root.pagesPerRequest
          root.errorMessage = ""
          root.resultsReady(parsed.rows, activeAppend)
        }
      } else if (isCurrent) {
        root.errorMessage = WallpaperBrowserModel.processError(
          result.stdout,
          result.stderr,
          result.state === "timeout"
            ? "The wallpaper catalog did not answer within two minutes"
            : "Wallpaper search failed. Check the Theme Manager catalog helper."
        )
      }

      if (root.queuedRequest) Qt.callLater(root.startQueuedSearch)
      else root.focusRequested()
    }
  }

  // wallpaper-catalog.py --wallpaper-download fetches one full-size wallpaper
  // of up to 64 MiB under the same socket timeout; 180 s covers that, and its
  // report is one JSON line (maxDownloadOutputBytes).
  Run {
    id: downloadProc

    property int activeSerial: 0
    environment: root.helperEnvironment
    deadlineMs: 180000
    maxBytes: root.maxDownloadOutputBytes

    onFinished: function(result) {
      if (activeSerial !== root.downloadSerial) return

      if (result.state === "overflow") {
        root.errorMessage = "The wallpaper catalog returned too much download output"
      } else if (result.state === "ok") {
        const parsed = WallpaperBrowserModel.parseDownloadResponse(
          result.stdout,
          root.homeDir,
          root.dataHome
        )
        if (parsed.error) root.errorMessage = parsed.error
        else root.wallpaperReady(parsed.path)
      } else {
        root.errorMessage = WallpaperBrowserModel.processError(
          result.stdout,
          result.stderr,
          result.state === "timeout"
            ? "The wallpaper download did not finish within three minutes"
            : "The wallpaper catalog could not download this wallpaper"
        )
      }

      root.focusRequested()
    }
  }
}
