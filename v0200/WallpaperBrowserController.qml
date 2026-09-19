import Quickshell
import Quickshell.Io
import QtQuick
import "WallpaperBrowserModel.js" as WallpaperBrowserModel

Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (homeDir + "/.cache")
  property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
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
  readonly property int maxErrorOutputBytes: 64 * 1024
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
    searchProc.outputTooLarge = false
    searchProc.stdoutText = ""
    searchProc.stderrText = ""
    searchProc.command = WallpaperBrowserModel.searchArguments(
      request.query,
      request.page,
      pagesPerRequest,
      request.filters
    )
    searchProc.running = true
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
    downloadProc.outputTooLarge = false
    downloadProc.stdoutText = ""
    downloadProc.stderrText = ""
    downloadProc.command = command
    downloadProc.running = true
  }

  Process {
    id: searchProc

    property int activeSerial: 0
    property string activeQuery: ""
    property string activeFilterKey: ""
    property int activePage: 1
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
        root.errorMessage = "Aether returned too much Wallhaven output"
      } else if (isCurrent && exitCode === 0) {
        const result = WallpaperBrowserModel.parseSearchResponse(
          stdoutText,
          root.cacheHome
        )
        if (result.error) {
          root.errorMessage = result.error
        } else {
          root.activeQuery = activeQuery
          root.activeFilterKey = activeFilterKey
          root.currentPage = result.meta.currentPage
          root.lastPage = result.meta.lastPage
          root.totalResults = result.meta.total
          root.nextRawPage = activePage + root.pagesPerRequest
          root.errorMessage = ""
          root.resultsReady(result.rows, activeAppend)
        }
      } else if (isCurrent) {
        root.errorMessage = WallpaperBrowserModel.processError(
          stdoutText,
          stderrText,
          "Wallhaven search failed. Aether 4.19 or newer is required."
        )
      }

      if (root.queuedRequest) Qt.callLater(root.startQueuedSearch)
      else root.focusRequested()
    }
  }

  Process {
    id: downloadProc

    property int activeSerial: 0
    property bool outputTooLarge: false
    property string stdoutText: ""
    property string stderrText: ""

    stdout: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!downloadProc.outputTooLarge
            && data.length > root.maxDownloadOutputBytes) {
          downloadProc.outputTooLarge = true
          downloadProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!downloadProc.outputTooLarge)
          downloadProc.stdoutText = String(text || "")
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onDataChanged: {
        if (!downloadProc.outputTooLarge
            && data.length > root.maxErrorOutputBytes) {
          downloadProc.outputTooLarge = true
          downloadProc.signal(9)
        }
      }
      onStreamFinished: {
        if (!downloadProc.outputTooLarge)
          downloadProc.stderrText = String(text || "")
      }
    }

    onExited: function(exitCode) {
      if (activeSerial !== root.downloadSerial) return

      if (outputTooLarge) {
        root.errorMessage = "Aether returned too much download output"
      } else if (exitCode === 0) {
        const result = WallpaperBrowserModel.parseDownloadResponse(
          stdoutText,
          root.homeDir,
          root.dataHome
        )
        if (result.error) root.errorMessage = result.error
        else root.wallpaperReady(result.path)
      } else {
        root.errorMessage = WallpaperBrowserModel.processError(
          stdoutText,
          stderrText,
          "Aether could not download this wallpaper"
        )
      }

      root.focusRequested()
    }
  }
}
