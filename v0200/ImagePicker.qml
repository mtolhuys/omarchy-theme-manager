import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "../omakit"
import "ImagePickerModel.js" as ImagePickerModel
import "IconThemeModel.js" as IconThemeModel
import "ThemeManagerModel.js" as ThemeManagerModel
import "ThemeMemoryModel.js" as ThemeMemoryModel
import "ThemeCatalogModel.js" as ThemeCatalogModel
import "WallpaperBrowserModel.js" as WallpaperBrowserModel
import "WallpaperCommandModel.js" as WallpaperCommandModel
import "IconBrowseModel.js" as IconBrowseModel

Item {
  id: root

  readonly property string buildIdentity: "0.8.0"
  // Injected by omarchy-shell; defaults to the session OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Every program starts through Run (omakit/Run.qml) with a closed
  // environment. Omarchy's own commands are named by absolute path under
  // its bin directory, and the variables each kind of program needs are
  // named here, once: the plugin's helpers get the XDG paths and
  // OMARCHY_PATH; Omarchy's commands also get the session, since they talk
  // to the compositor, the shell and the session bus.
  readonly property string omarchyBin: (omarchyPath || (Quickshell.env("HOME") + "/.local/share/omarchy")) + "/bin"
  readonly property var helperEnvironment: namedEnvironment([
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "OMARCHY_PATH",
    "OMARCHY_THEME_CATALOG_MAX_AGE", "OMARCHY_ICONS_OCS_API", "OMARCHY_ICONS_OCS_CATEGORY"
  ], {})
  readonly property var omarchyEnvironment: namedEnvironment([
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "OMARCHY_PATH",
    "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP"
  ], { PATH: "/usr/bin:" + omarchyBin })
  property var manifest: null
  property string stateHome: Quickshell.env("HOME") + "/.local/state"
  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (stateHome + "/omarchy/current/theme/backgrounds")
  property string imageRows: ""
  property string loadedImageRows: ""
  property bool refreshInPlace: false
  property string selectionFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTION_FILE") || Quickshell.env("OMARCHY_BACKGROUND_SELECTION_FILE")
  property string selectedImage: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTED")
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool showLabels: false
  property bool filterable: false
  property bool layoutSettled: false
  property bool requestActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property string doneFile: ""
  property string filterText: ""
  property bool catalogMode: false
  property var catalogPreviousImages: []
  property int catalogPreviousIndex: 0
  property string catalogPreviousFilter: ""
  property bool catalogPreviousFilterable: false
  property bool catalogPreviousShowLabels: false
  property var catalogSourceRows: []
  property var catalogFilters: ({ listing: "all", availability: "all", sort: "best", minStars: 0 })
  property string catalogStickyQuery: ""
  // The 0.8.x locations of the five files the plugin keeps of its own. They
  // are read once, when Store reports nothing under the private state root
  // yet, and then left alone; Store owns every write from here on.
  readonly property string catalogFiltersPath: Quickshell.env("HOME") + "/.config/omarchy/theme-catalog-filters.json"
  property bool wallhavenMode: false
  property string wallhavenStickyQuery: ""
  property bool wallhavenFiltersReady: false
  readonly property string wallhavenFiltersPath: Quickshell.env("HOME") + "/.config/omarchy/wallpaper-browser-filters.json"
  property var localImages: []
  property int localSelectedIndex: 0
  property string localFilterText: ""
  property bool wallpaperPickerRequest: false
  readonly property string wallpaperCommandStatePath: Quickshell.env("HOME") + "/.config/omarchy/wallpaper-command-center.json"
  readonly property string themeMemoryStatePath: Quickshell.env("HOME") + "/.config/omarchy/theme-manager-memory.json"
  readonly property string themeCollectionsStatePath: Quickshell.env("HOME") + "/.config/omarchy/theme-collections.json"
  readonly property string pluginId: "io.github.mtolhuys.theme-manager"
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string themeBackgroundsRoot: homeDir + "/.config/omarchy/backgrounds"
  readonly property string currentThemeRoot: stateHome + "/omarchy/current/theme/backgrounds"
  readonly property string currentThemeNamePath: stateHome + "/omarchy/current/theme.name"
  property string pendingInstallPurpose: ""
  property string pendingInstallSelectionFile: ""
  property string pendingInstallDoneFile: ""
  property string pendingInstallSourcePath: ""
  property int pendingInstallSerial: 0
  readonly property string currentIconsThemePath: stateHome + "/omarchy/current/theme/icons.theme"
  property string currentThemeName: ""
  property string currentIconTheme: ""
  property var favoriteIds: []
  property bool favoritesOnly: false
  property bool iconsMode: false
  property var iconsPreviousImages: []
  property int iconsPreviousIndex: 0
  property string iconsPreviousFilter: ""
  property bool iconsPreviousFilterable: false
  property bool iconsPreviousShowLabels: false
  property bool iconsPreviousWallpaperRequest: false
  property bool iconsBrowseMode: false
  property var iconsBrowsePreviousImages: []
  property int iconsBrowsePreviousIndex: 0
  property string iconsBrowsePreviousFilter: ""
  property var iconsBrowseFilters: ({ sorting: "new" })
  property var themeMemoryState: ({ version: 1, themes: {} })
  property string lastRestoredThemeName: ""
  property bool restoringThemeMemory: false
  property string statusToast: ""
  property var iconsInventoryThemes: []
  property string footerIconFolder: ""
  property string footerIconApp: ""
  property string footerIconMime: ""
  // While browsing themes, preview the highlighted theme's icons (sticky memory
  // first, then package icons.theme) instead of the globally applied icon theme.
  readonly property string footerPreviewIconTheme: {
    if (themeManager.themePickerActive
        && !catalogMode
        && !wallhavenMode
        && !iconsMode
        && !wallpaperPickerActive) {
      const themeName = themeManager.selectedThemeName
      const remembered = ThemeMemoryModel.rememberedIcons(themeMemoryState, themeName)
      if (remembered) return remembered
      const pkg = themeManager.packageIcons && themeManager.packageIcons[themeName]
      if (pkg) return String(pkg)
    }
    return currentIconTheme
  }
  readonly property string footerIconLabel: footerPreviewIconTheme
    ? IconThemeModel.labelForIconTheme(footerPreviewIconTheme)
    : "Icons"
  readonly property bool footerIconHasPreviews: !!(footerIconFolder || footerIconApp || footerIconMime)
  readonly property var wallpaperActionOptions: {
    const options = [
      {
        value: "save",
        label: currentFavorite ? "★ Saved" : "☆ Save"
      },
      {
        value: "favorites",
        label: favoritesOnly ? "★ Favorites" : "All"
      }
    ]
    if (currentThemeName)
      options.push({ value: "reset", label: "Reset wallpaper" })
    if (canRemoveInstalledWallpaper)
      options.push({ value: "remove", label: "Remove" })
    return options
  }
  readonly property bool wallpaperPickerActive: wallpaperPickerRequest
  readonly property bool localWallpaperMode: wallpaperPickerActive && !wallhavenMode && !catalogMode && !iconsMode && !iconsBrowseMode
  readonly property bool iconsPickerActive: iconsMode || iconsBrowseMode
  readonly property bool canOpenIconsMode: !catalogMode && !wallhavenMode && !iconsMode && !iconsBrowseMode
    && (wallpaperPickerActive || themeManager.themePickerActive)
  // Installed-icons carousel (not the Pling browse gallery). Do not gate on
  // themePickerActive — once iconsMode swaps the carousel off themes,
  // selectedThemeName goes empty and that flag falsely drops.
  readonly property bool localIconsMode: iconsMode && !iconsBrowseMode
  // Installed-theme rows are on screen. Keyed off the loaded rows, not the
  // selection, so an empty match set cannot flip it and re-filter itself.
  readonly property bool themeRowsLoaded: imageArray.length > 0
    && ThemeManagerModel.isThemePreviewPath(imageArray[0].filePath)
  readonly property bool themeCollectionsActive: themeRowsLoaded
    && !catalogMode
    && !wallhavenMode
    && !iconsMode
    && !iconsBrowseMode
    && !wallpaperPickerActive
  readonly property bool themeGridActive: themeCollectionsActive && themeCollections.gridMode
  readonly property bool hasWallpaperMemory: ThemeMemoryModel.hasWallpaperOverride(themeMemoryState, currentThemeName)
  readonly property bool hasIconsMemory: ThemeMemoryModel.hasIconsOverride(themeMemoryState, currentThemeName)
  readonly property bool canRemoveInstalledWallpaper: localWallpaperMode
    && !!ThemeMemoryModel.safeThemeName(currentThemeName)
    && ThemeMemoryModel.isUserInstalledWallpaper(currentPath(), homeDir, currentThemeName)
  readonly property bool canResetWallpaper: localWallpaperMode && !!ThemeMemoryModel.safeThemeName(currentThemeName)
  readonly property bool currentFavorite: localWallpaperMode
    && WallpaperCommandModel.isFavorite(favoriteIds, currentPath(), wallpaperFavoriteContext())
  readonly property string wallhavenFilterSummary: WallpaperBrowserModel.filterSummary({
    collection: wallhaven.collection,
    sorting: wallhaven.sorting,
    license: wallhaven.license
  })
  readonly property string iconsBrowseFilterSummary: IconBrowseModel.filterSummary(iconsBrowseFilters)
  readonly property bool iconsBrowseFiltersActive: IconBrowseModel.filterKey(iconsBrowseFilters)
    !== IconBrowseModel.filterKey({})
  readonly property bool wallhavenFiltersActive: WallpaperBrowserModel.filtersActive({
    collection: wallhaven.collection,
    sorting: wallhaven.sorting,
    license: wallhaven.license
  })
  readonly property int wallhavenFilterActiveCount: WallpaperBrowserModel.filterActiveCount({
    collection: wallhaven.collection,
    sorting: wallhaven.sorting,
    license: wallhaven.license
  })
  readonly property string catalogFilterSummary: ThemeCatalogModel.catalogFilterSummary(catalogFilters)
  readonly property bool catalogFiltersActive: ThemeCatalogModel.catalogFiltersActive(catalogFilters)
  readonly property int catalogFilterActiveCount: ThemeCatalogModel.catalogFilterActiveCount(catalogFilters)
  // Bound to the central [image-picker] section in shell.toml via Color.qml.
  // dimColor tints unselected slices and text outlines on top of the scrim.
  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color scrim: Color.imagePicker.scrim
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder
  readonly property bool livePaletteReady: wallpaperPickerActive && wallpaperPalette.ready
  readonly property color livePaletteBase: livePaletteReady
    ? mixColor(Color.background, wallpaperPalette.base, 0.58)
    : Color.background
  readonly property color livePaletteAccent: livePaletteReady
    ? mixColor(Color.accent, wallpaperPalette.accent, 0.78)
    : Color.accent
  readonly property color livePaletteSecondary: livePaletteReady
    ? mixColor(Color.accent, wallpaperPalette.secondary, 0.7)
    : Color.accent
  readonly property color activeSelectedBorder: livePaletteReady
    ? livePaletteAccent
    : selectedBorder
  // A theme may set image-picker.scrim-alpha as low as it likes: over a
  // wallpaper a thin wash looks right. Over a bright window the same alpha
  // drops foreground-on-background below a readable ratio, which is why the
  // footer and its controls became unreadable on light pages. Every backdrop
  // the picker paints text on therefore gets an opacity floor; the theme's
  // own color is kept, and a theme asking for more opacity keeps its value.
  readonly property real minBackdropAlpha: 0.9
  function readableBackdrop(surface, minimum) {
    const floor = minimum === undefined ? minBackdropAlpha : minimum
    return Util.alpha(surface, Math.max(surface.a, floor))
  }
  // Control interiors and caption plates sit above the floored wash.
  readonly property color chromeFill: readableBackdrop(dimColor, 0.94)
  // Glyph halo for text that sits directly on a preview image.
  readonly property color chromeOutline: Util.alpha(dimColor, 0.95)
  readonly property color activeScrim: livePaletteReady
    ? readableBackdrop(Util.alpha(livePaletteBase, 0.82))
    : readableBackdrop(scrim)
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: wallhavenMode || catalogMode || iconsMode || iconsBrowseMode
    ? (catalogMode ? 170 : 150)
    : (wallpaperPickerActive
        ? 96
        : (showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)))

  Component.onCompleted: {
    console.info("Theme Manager runtime " + buildIdentity)
    // Shell injects `manifest` in Loader.onLoaded after this; real boot warm-up
    // runs from onManifestChanged. Call anyway if binding order changes.
    ensureThemeSetMemoryHook()
    ensureFooterIconsReady()
    // Store reads through a helper process, so these land a moment after the
    // FileView preload they replace; every reader here already copes with the
    // state arriving late.
    loadPluginState()
  }

  function loadPluginState() {
    catalogFiltersFile.load()
    wallhavenFiltersFile.load()
    wallpaperCommandState.load()
    themeMemoryStateFile.load()
  }

  onManifestChanged: {
    if (!manifest) return
    ensureThemeSetMemoryHook()
    ensureFooterIconsReady()
  }

  onCurrentIconThemeChanged: updateFooterIconPreviews()
  onFooterPreviewIconThemeChanged: updateFooterIconPreviews()
  onCurrentThemeNameChanged: {
    // Memory / theme name may arrive after inventory; re-resolve once ready.
    if (!String(currentIconTheme || "").trim())
      ensureCurrentIconTheme()
  }

  function runtimeIdentity() {
    return buildIdentity
  }

  function mixColor(from, to, amount) {
    const t = Math.max(0, Math.min(1, Number(amount) || 0))
    return Qt.rgba(
      from.r + (to.r - from.r) * t,
      from.g + (to.g - from.g) * t,
      from.b + (to.b - from.b) * t,
      from.a + (to.a - from.a) * t)
  }

  function runtimeState() {
    return JSON.stringify({
      version: buildIdentity,
      opened: opened,
      layoutSettled: layoutSettled,
      mode: catalogMode
        ? "catalog"
        : (wallhavenMode
            ? "wallhaven"
            : (iconsBrowseMode
                ? "icons-browse"
                : (iconsMode
                ? "icons"
                : (themeManager.themePickerActive
                    ? "themes"
                    : (wallpaperPickerActive ? "wallpapers" : "images"))))),
      hasWallpaperMemory: hasWallpaperMemory,
      hasIconsMemory: hasIconsMemory,
      currentIconTheme: currentIconTheme,
      footerPreviewIconTheme: footerPreviewIconTheme,
      footerIconHasPreviews: footerIconHasPreviews,
      iconsInventoryCount: Array.isArray(iconsInventoryThemes) ? iconsInventoryThemes.length : 0,
      images: imageArray.length,
      matchingImages: matchingIndices.length,
      carouselDelegates: carouselRepeater.count,
      visibleCarouselDelegates: visibleCarouselDelegateCount(),
      selectedIndex: selectedIndex,
      selectedPath: currentPath(),
      carouselCursor: carouselCursor,
      query: wallhavenMode || catalogMode ? filterText : "",
      filtersOpen: filterSheet.opened || catalogFilterSheet.opened,
      catalogInstallConfirmationOpen: themeCatalog.confirmationOpen,
      catalogAction: themeCatalog.selectedStatus,
      catalogCanInstall: themeCatalog.canInstallSelected,
      catalogCanOpenSource: themeCatalog.canOpenSelectedSource,
      catalogError: themeCatalog.errorMessage,
      favoriteCount: favoriteIds.length,
      currentFavorite: currentFavorite,
      favoritesOnly: favoritesOnly,
      themeGrid: themeGridActive,
      themeFavoriteCount: themeCollections.favoriteCount,
      themeCollectionCount: themeCollections.collectionCount,
      themeCollection: themeCollections.selectedCollectionId,
      themeFavoritesOnly: themeCollections.favoritesOnly,
      paletteReady: wallpaperPalette.ready,
      paletteSampledPath: wallpaperPalette.sampledPath,
      paletteSourcePath: currentPaletteSource()
    })
  }

  function visibleCarouselDelegateCount() {
    let count = 0
    for (let index = 0; index < carouselRepeater.count; index++) {
      const delegate = carouselRepeater.itemAt(index)
      if (delegate && delegate.visible) count += 1
    }
    return count
  }

  onOpenedChanged: {
    if (!opened) {
      if (collectionsSheet.opened) collectionsSheet.cancel()
      if (catalogMode) leaveCatalog(false)
      if (wallhavenMode) leaveWallhaven(false)
      if (iconsBrowseMode) leaveIconsBrowse(false)
      if (iconsMode) leaveIcons(false)
      statusToast = ""
      layoutSettled = false
    }
  }

  function scriptPath(name) {
    return omarchyPath + "/shell/plugins/image-picker/" + name
  }

  // The named variables of the shell's environment that are set, plus the
  // fixed ones, as the object Run adds to its base environment.
  function namedEnvironment(names, fixed) {
    const environment = Object.assign({}, fixed)
    for (let index = 0; index < names.length; index++) {
      const value = Quickshell.env(names[index])
      if (value) environment[names[index]] = value
    }
    return environment
  }

  // A small file written from this process, synchronously, so it is there
  // before anything else happens and survives a rescan that destroys this
  // object: the selection and done files a waiting omarchy-menu-images
  // reads. A child process could be ended by that teardown (Run ends its
  // group on destruction), which is why these two writes are not processes.
  function writeSmallFile(path, text) {
    const target = String(path || "")
    if (!target.startsWith("/")) return false
    smallFileWriter.path = target
    smallFileWriter.setText(String(text || ""))
    return true
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try {
      return decodeURIComponent(value)
    } catch (e) {
      return value
    }
  }

  function pluginScriptPath(name) {
    // Third-party manifests do not expose the host's private source directory
    // (Omarchy 4.0.3 sanitizes it), so resolve from this file, which lives one
    // level under the plugin root (v0200/).
    const dir = localPath(Qt.resolvedUrl("../")).replace(/\/$/, "")
    return dir ? dir + "/" + name : ""
  }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled)
      keyHandler.forceActiveFocus()
  }

  function currentWallhavenFilters() {
    return {
      collection: wallhaven.collection,
      sorting: wallhaven.sorting,
      license: wallhaven.license
    }
  }

  function revealWhenSettled(serial) {
    Qt.callLater(function() {
      if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) {
        root.layoutSettled = true
        root.focusPicker()
      }
    })
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function wallpaperFavoriteContext() {
    return {
      themeRoot: currentThemeRoot,
      themeName: currentThemeName
    }
  }

  function loadWallpaperCommandState(raw) {
    const state = WallpaperCommandModel.parseState(raw, wallpaperFavoriteContext())
    favoriteIds = state.favorites
    if (localWallpaperMode && imageArray.length > 0) reorderWallpapers()
  }

  function saveWallpaperCommandState() {
    wallpaperCommandState.save(WallpaperCommandModel.serializeState(favoriteIds))
  }

  function loadThemeMemoryState(raw) {
    themeMemoryState = ThemeMemoryModel.parseState(raw)
  }

  function saveThemeMemoryState() {
    themeMemoryStateFile.save(ThemeMemoryModel.serializeState(themeMemoryState))
  }

  function showStatus(message) {
    statusToast = String(message || "")
    if (statusToast) statusToastTimer.restart()
  }

  function clearPendingInstall() {
    pendingInstallPurpose = ""
    pendingInstallSelectionFile = ""
    pendingInstallDoneFile = ""
    pendingInstallSourcePath = ""
    pendingInstallSerial = 0
  }

  function installWallpaperCommand(themeName, sourcePath) {
    const script = pluginScriptPath("install-wallpaper.sh")
    const name = ThemeMemoryModel.safeThemeName(themeName)
    const target = ThemeMemoryModel.safePath(sourcePath)
    if (!script || !name || !target) return null
    return [script, name, target]
  }

  function beginWallpaperInstall(purpose, sourcePath, selectionPath, donePath, serial) {
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const target = ThemeMemoryModel.safePath(sourcePath)
    const command = installWallpaperCommand(themeName, target)
    if (!command) return false
    if (wallpaperInstallProc.running) return false

    pendingInstallPurpose = String(purpose || "")
    pendingInstallSelectionFile = String(selectionPath || "")
    pendingInstallDoneFile = String(donePath || "")
    pendingInstallSourcePath = target
    pendingInstallSerial = serial || 0
    wallpaperInstallProc.command = command
    wallpaperInstallProc.start()
    return true
  }

  function carouselHasWallpaper(path) {
    const target = ThemeMemoryModel.safePath(path)
    const base = ThemeMemoryModel.imageBasename(target)
    if (!target) return -1
    for (let index = 0; index < imageArray.length; index++) {
      const item = imageArray[index]
      if (!item) continue
      if (item.filePath === target) return index
      if (base && item.fileName === base) return index
    }
    return -1
  }

  function injectWallpaperIntoCarousel(path) {
    const target = ThemeMemoryModel.safePath(path)
    if (!target || !localWallpaperMode) return false
    const base = ThemeMemoryModel.imageBasename(target) || target.split("/").pop()
    const existing = carouselHasWallpaper(target)
    if (existing >= 0) {
      const item = imageArray[existing]
      if (item && item.filePath !== target) {
        const next = imageArray.slice()
        next[existing] = {
          filePath: target,
          fileName: base,
          thumbnailPath: target
        }
        imageArray = next
      }
      selectedIndex = existing
      selectedImage = target
      return true
    }

    const row = {
      filePath: target,
      fileName: base,
      thumbnailPath: target
    }
    imageArray = [row].concat(imageArray)
    selectedIndex = 0
    selectedImage = target
    reorderWallpapers()
    return true
  }

  // Wallhaven keeps a snapshot in localImages; finish closes via selection files
  // but onOpenedChanged → leaveWallhaven restores that snapshot. Keep it in sync
  // so an intermittent leave/reopen race still shows the newly installed tile.
  function syncInstalledWallpaperIntoLocalSnapshot(path) {
    const target = ThemeMemoryModel.safePath(path)
    if (!target) return false
    const base = ThemeMemoryModel.imageBasename(target) || target.split("/").pop()
    const row = {
      filePath: target,
      fileName: base,
      thumbnailPath: target
    }
    let next = Array.isArray(localImages) ? localImages.slice() : []
    for (let index = 0; index < next.length; index++) {
      const item = next[index]
      if (!item) continue
      if (item.filePath === target || (base && item.fileName === base)) {
        next[index] = row
        localImages = next
        localSelectedIndex = index
        return true
      }
    }
    localImages = [row].concat(next)
    localSelectedIndex = 0
    return true
  }

  function localWallpaperScanDirs() {
    // omarchy-menu-images opens with precomputed imageRows and an empty imageDirs
    // argument. Keep a real dir list so Remove/Reset can always re-run list.sh.
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const seen = {}
    const dirs = []

    function pushDir(value) {
      const dir = String(value || "").replace(/\/+$/, "")
      if (!dir || seen[dir]) return
      seen[dir] = true
      dirs.push(dir)
    }

    String(imageDirs || "").split("\n").forEach(pushDir)
    pushDir(ThemeMemoryModel.themeBackgroundsDir(homeDir, themeName))
    pushDir(ThemeMemoryModel.currentThemeBackgroundsDir(homeDir))
    pushDir(themeBackgroundsRoot + (themeName ? "/" + themeName : ""))
    pushDir(currentThemeRoot)
    return dirs.join("\n")
  }

  function pruneRememberedWallpaper(themeName) {
    const name = ThemeMemoryModel.safeThemeName(themeName)
    if (!name) return
    if (!ThemeMemoryModel.rememberedWallpaper(themeMemoryState, name)) return
    themeMemoryState = ThemeMemoryModel.clearWallpaper(themeMemoryState, name)
    saveThemeMemoryState()
  }

  function ensureRememberedWallpaperInPicker() {
    if (!localWallpaperMode) return
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const remembered = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, themeName)
    if (!themeName || !remembered) return

    // External catalog path: copy into theme backgrounds when the source still exists.
    if (ThemeMemoryModel.needsWallpaperInstall(remembered, homeDir, themeName)) {
      beginWallpaperInstall("ensure", remembered, "", "", 0)
      return
    }

    // Picker path already under stock/theme backgrounds. list.sh is the source of
    // truth — never inject a remembered path that the scan did not return (deleted
    // or <4KiB). Blind inject was the root cause of live Remove "stale" tiles and
    // the empty black "Wallhaven Zp92gy" ghost after reopen.
    const existing = carouselHasWallpaper(remembered)
    if (existing >= 0) {
      selectedIndex = existing
      selectedImage = imageArray[existing].filePath
      return
    }

    pruneRememberedWallpaper(themeName)
  }

  function migrateRememberedWallpaperIfNeeded() {
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const remembered = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, themeName)
    if (!themeName || !remembered) return
    if (!ThemeMemoryModel.needsWallpaperInstall(remembered, homeDir, themeName)) return
    beginWallpaperInstall("migrate", remembered, "", "", 0)
  }

  function acceptInstalledWallpaper(installedPath) {
    const installed = ThemeMemoryModel.safePath(installedPath)
    const purpose = String(pendingInstallPurpose || "")
    const selectionPath = pendingInstallSelectionFile
    const donePath = pendingInstallDoneFile
    const serial = pendingInstallSerial
    clearPendingInstall()

    if (!installed) {
      if (purpose === "finish") cancel()
      else if (purpose) showStatus("Wallpaper install failed")
      return
    }

    if (purpose === "finish") {
      rememberWallpaperSelection(installed)
      if (wallhavenMode)
        syncInstalledWallpaperIntoLocalSnapshot(installed)
      // Belt-and-suspenders: menu-images waiter also bg-sets after the selection
      // file is written. Direct set covers the intermittent case where accept ran
      // but the waiter already moved on / selection handoff raced.
      if (!memoryBgProc.running) {
        memoryBgProc.command = [omarchyBin + "/omarchy-theme-bg-set", installed]
        memoryBgProc.start()
      }
      applySerial = serial || requestSerial
      writeSmallFile(selectionPath, installed + "\n")
      writeSmallFile(donePath, "")
      if (applySerial === requestSerial)
        opened = false
      return
    }

    // ensure / migrate: persist installed path and optionally retarget bg symlink
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    if (themeName) {
      const previous = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, themeName)
      if (previous !== installed) {
        themeMemoryState = ThemeMemoryModel.setWallpaper(themeMemoryState, themeName, installed)
        saveThemeMemoryState()
        if (purpose === "migrate" || purpose === "ensure")
          showStatus("Wallpaper saved for " + themeName)
      }
    }

    if (purpose === "migrate" || purpose === "migrate-restore") {
      restoringThemeMemory = true
      memoryBgProc.command = [omarchyBin + "/omarchy-theme-bg-set", installed]
      memoryBgProc.start()
      if (purpose === "migrate-restore" && themeName) {
        themeMemoryVerifyTimer.themeName = themeName
        themeMemoryVerifyTimer.expectedWallpaper = installed
        themeMemoryVerifyTimer.restart()
      }
    }

    if (wallhavenMode)
      syncInstalledWallpaperIntoLocalSnapshot(installed)

    if (localWallpaperMode)
      injectWallpaperIntoCarousel(installed)
  }

  function rememberWallpaperSelection(path) {
    if (restoringThemeMemory || !wallpaperPickerActive) return
    const themeName = String(currentThemeName || "").trim()
    const target = ThemeMemoryModel.safePath(path)
    if (!themeName || !target) return
    themeMemoryState = ThemeMemoryModel.setWallpaper(themeMemoryState, themeName, target)
    saveThemeMemoryState()
    showStatus("Wallpaper saved for " + themeName)
  }

  function rememberIconSelection(iconName, iconsDefault) {
    const themeName = String(currentThemeName || "").trim()
    const icons = ThemeMemoryModel.safeIconName(iconName)
    if (!themeName || !icons) return
    themeMemoryState = ThemeMemoryModel.setIcons(
      themeMemoryState,
      themeName,
      icons,
      iconsDefault || currentIconTheme)
    saveThemeMemoryState()
  }

  function ensureThemeSetMemoryHook() {
    const source = pluginScriptPath("hooks/theme-set.d/50-theme-manager-memory")
    if (!source) return
    const dest = Quickshell.env("HOME") + "/.config/omarchy/hooks/theme-set.d/50-theme-manager-memory"
    const script = pluginScriptPath("install-hook.sh")
    if (!script) return
    hookInstallProc.command = [script, source, dest]
    hookInstallProc.start()
  }

  function ensureFooterIconsReady() {
    ensureCurrentIconTheme()
    ensureFooterIconsInventory()
  }

  function ensureCurrentIconTheme() {
    if (String(currentIconTheme || "").trim()) return

    const remembered = ThemeMemoryModel.rememberedIcons(themeMemoryState, currentThemeName)
    if (remembered) {
      currentIconTheme = remembered
      return
    }

    if (iconThemeProbeProc.running) return
    iconThemeProbeProc.command = [
      "/usr/bin/gsettings",
      "get",
      "org.gnome.desktop.interface",
      "icon-theme"
    ]
    iconThemeProbeProc.start()
  }

  function acceptIconThemeProbe(text) {
    if (String(currentIconTheme || "").trim()) return
    let value = String(text || "").trim()
    if ((value.startsWith("'") && value.endsWith("'"))
        || (value.startsWith("\"") && value.endsWith("\"")))
      value = value.slice(1, -1)
    value = ThemeMemoryModel.safeIconName(value)
    if (value)
      currentIconTheme = value
  }

  function ensureFooterIconsInventory() {
    if (footerIconsInventoryProc.running) return
    if (Array.isArray(iconsInventoryThemes) && iconsInventoryThemes.length > 0)
      return
    const script = pluginScriptPath("icons-inventory.sh")
    if (!script) return
    footerIconsInventoryProc.command = [script]
    footerIconsInventoryProc.start()
  }

  function updateFooterIconPreviews() {
    const selected = String(footerPreviewIconTheme || "").trim()
    let folder = ""
    let app = ""
    let mime = ""
    if (selected && Array.isArray(iconsInventoryThemes)) {
      for (let i = 0; i < iconsInventoryThemes.length; i++) {
        const theme = iconsInventoryThemes[i]
        if (theme && theme.name === selected) {
          folder = String(theme.folder || "")
          app = String(theme.app || "")
          mime = String(theme.mime || "")
          break
        }
      }
    }
    footerIconFolder = folder
    footerIconApp = app
    footerIconMime = mime
  }

  function scheduleThemeMemoryRestore(themeName, force) {
    const name = String(themeName || "").trim()
    if (!name) return
    if (!force && name === lastRestoredThemeName
        && !themeMemoryRestoreTimer.running
        && !themeMemoryVerifyTimer.running)
      return
    themeMemoryRestoreTimer.themeName = name
    themeMemoryRestoreTimer.waitedMs = 0
    themeMemoryRestoreTimer.lockFree = false
    themeMemoryRestoreTimer.restart()
  }

  function restoreThemeMemory(themeName) {
    const name = String(themeName || currentThemeName || "").trim()
    if (!name) return

    lastRestoredThemeName = name
    let wallpaper = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, name)
    const icons = ThemeMemoryModel.rememberedIcons(themeMemoryState, name)

    if (wallpaper) {
      if (ThemeMemoryModel.needsWallpaperInstall(wallpaper, homeDir, name)) {
        if (beginWallpaperInstall("migrate-restore", wallpaper, "", "", 0)) {
          if (icons && icons !== currentIconTheme)
            applyIconTheme(icons, false)
          return
        }
      }
      restoringThemeMemory = true
      memoryBgProc.command = [omarchyBin + "/omarchy-theme-bg-set", wallpaper]
      memoryBgProc.start()
    }

    if (icons && icons !== currentIconTheme)
      applyIconTheme(icons, false)

    themeMemoryVerifyTimer.themeName = name
    themeMemoryVerifyTimer.expectedWallpaper = wallpaper
    themeMemoryVerifyTimer.restart()
  }

  function verifyThemeMemoryRestore(themeName, expectedWallpaper) {
    const name = String(themeName || "").trim()
    const expected = ThemeMemoryModel.safePath(expectedWallpaper)
    if (!name || !expected) return
    const script = pluginScriptPath("verify-wallpaper.sh")
    if (!script) return
    themeMemoryVerifyProc.command = [script, expected]
    themeMemoryVerifyProc.themeName = name
    themeMemoryVerifyProc.expectedWallpaper = expected
    themeMemoryVerifyProc.start()
  }

  function applyIconTheme(iconName, persist) {
    const icons = ThemeMemoryModel.safeIconName(iconName)
    if (!icons) return
    const previous = String(currentIconTheme || "").trim()
    if (persist !== false)
      rememberIconSelection(icons, previous)

    const script = pluginScriptPath("apply-icons.sh")
    if (!script) return
    iconApplyProc.command = [script, icons, currentIconsThemePath]
    iconApplyProc.start()
    currentIconTheme = icons
    showStatus("Icons · " + IconThemeModel.labelForIconTheme(icons))
  }

  function resetWallpaperDefaults() {
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const script = pluginScriptPath("reset-wallpaper.sh")
    if (!themeName || !script) return
    if (wallpaperResetProc.running) return

    themeMemoryState = ThemeMemoryModel.clearWallpaper(themeMemoryState, themeName)
    saveThemeMemoryState()
    restoringThemeMemory = true
    wallpaperResetProc.themeName = themeName
    wallpaperResetProc.command = [script, themeName]
    wallpaperResetProc.start()
  }

  function acceptResetWallpaper(stockPath) {
    const themeName = ThemeMemoryModel.safeThemeName(wallpaperResetProc.themeName)
    wallpaperResetProc.themeName = ""
    restoringThemeMemory = false

    const stock = ThemeMemoryModel.safePath(stockPath)

    // Same stale-tile class as Remove: rebuild from list.sh after disk wipe.
    if (localWallpaperMode)
      reloadLocalWallpapersFromDisk(stock, "")
    else if (stock)
      selectedImage = stock

    showStatus(themeName
      ? "Wallpaper defaults restored for " + themeName
      : "Wallpaper defaults restored")
    Qt.callLater(focusPicker)
  }

  function removeCurrentInstalledWallpaper() {
    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const target = ThemeMemoryModel.safePath(currentPath())
    const script = pluginScriptPath("remove-wallpaper.sh")
    if (!themeName || !target || !script) return
    if (!ThemeMemoryModel.isUserInstalledWallpaper(target, homeDir, themeName)) return
    if (wallpaperRemoveProc.running) return

    const remembered = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, themeName)
    const rememberedBase = ThemeMemoryModel.imageBasename(remembered)
    const removedBase = ThemeMemoryModel.imageBasename(target)
    wallpaperRemoveProc.clearMemory = !!remembered && (
      remembered === target
      || (!!rememberedBase && rememberedBase === removedBase))
    wallpaperRemoveProc.removedPath = target
    wallpaperRemoveProc.themeName = themeName

    // Optimistic UI drop BEFORE Process starts. Script success still runs
    // acceptRemovedInstalledWallpaper (prune memory/favorites + list.sh rescan).
    // Nonzero exit restores the carousel from disk.
    const previousIndex = selectedIndex
    dropWallpaperFromCarousel(target, "", previousIndex)

    wallpaperRemoveProc.command = [script, themeName, target]
    wallpaperRemoveProc.start()
  }

  function acceptRemovedInstalledWallpaper(nextBackground) {
    const removed = ThemeMemoryModel.safePath(wallpaperRemoveProc.removedPath)
    const themeName = ThemeMemoryModel.safeThemeName(wallpaperRemoveProc.themeName)
    const clearMemory = wallpaperRemoveProc.clearMemory === true
    wallpaperRemoveProc.removedPath = ""
    wallpaperRemoveProc.themeName = ""
    wallpaperRemoveProc.clearMemory = false

    if (themeName) {
      const remembered = ThemeMemoryModel.rememberedWallpaper(themeMemoryState, themeName)
      const rememberedBase = ThemeMemoryModel.imageBasename(remembered)
      const removedBase = ThemeMemoryModel.imageBasename(removed)
      if (clearMemory
          || (remembered && remembered === removed)
          || (rememberedBase && removedBase && rememberedBase === removedBase))
        pruneRememberedWallpaper(themeName)
    }

    if (removed && WallpaperCommandModel.isFavorite(favoriteIds, removed, wallpaperFavoriteContext())) {
      favoriteIds = WallpaperCommandModel.toggleFavorite(favoriteIds, removed, wallpaperFavoriteContext())
      saveWallpaperCommandState()
    }

    // Tile already dropped optimistically before Process; re-apply preferred
    // path from script stdout and run authoritative list.sh rescan.
    const preferred = ThemeMemoryModel.safePath(nextBackground)
    reloadLocalWallpapersFromDisk(preferred, removed)
    showStatus("Wallpaper removed")
    Qt.callLater(focusPicker)
  }

  function runWallpaperAction(action) {
    const next = String(action || "").trim()
    if (next === "save") root.toggleCurrentFavorite()
    else if (next === "favorites") root.toggleFavoritesOnly()
    else if (next === "reset") root.resetWallpaperDefaults()
    else if (next === "remove") root.removeCurrentInstalledWallpaper()
    Qt.callLater(root.focusPicker)
  }

  function reloadLocalWallpapersFromDisk(preferredPath, removedPath) {
    const preferred = ThemeMemoryModel.safePath(preferredPath)
    const removed = ThemeMemoryModel.safePath(removedPath)
    const previousIndex = selectedIndex

    // Live Remove must paint immediately — same class as Wallhaven/theme-row
    // updates: mutate the open model while the card stays visible. Blanking via
    // imagesLoaded=false + imageArray=[] deferred Repeater teardown and left the
    // old tile on screen until Escape/reopen rebuilt delegates.
    if (removed)
      dropWallpaperFromCarousel(removed, preferred, previousIndex)
    else if (preferred)
      selectedImage = preferred

    imagesLoaded = true
    layoutSettled = true

    const dirs = localWallpaperScanDirs()
    if (dirs)
      imageDirs = dirs

    // Authoritative rescan in the background; keep optimistic tiles until then.
    if (localWallpaperMode && String(dirs || "").trim()) {
      loadedImageRows = ""
      refreshInPlace = true
      startImageScan(requestSerial, dirs)
    }
  }

  function dropWallpaperFromCarousel(removedPath, nextBackground, previousIndex) {
    const removed = ThemeMemoryModel.safePath(removedPath)
    const removedBase = ThemeMemoryModel.imageBasename(removed)
    if (!removed && !removedBase) return

    const nextImages = []
    for (let index = 0; index < imageArray.length; index++) {
      const item = imageArray[index]
      if (!item || !item.filePath) continue
      if (item.filePath === removed) continue
      if (removedBase && item.fileName === removedBase) continue
      if (removedBase && String(item.filePath).split("/").pop() === removedBase) continue
      nextImages.push(item)
    }

    // Keep row-cache in sync so Escape/reopen cannot revive the ghost tile.
    if (loadedImageRows) {
      const lines = String(loadedImageRows).split("\n").filter(function(line) {
        if (!line) return false
        const filePath = line.split("\t")[0]
        if (!filePath) return false
        if (removed && filePath === removed) return false
        if (removedBase && filePath.split("/").pop() === removedBase) return false
        return true
      })
      loadedImageRows = lines.join("\n")
    }

    // Fresh array + epoch so length-model Repeater rebinds surviving indices.
    replaceImageArray(nextImages)

    if (imageArray.length === 0) {
      selectedIndex = 0
      selectedImage = ""
      return
    }

    const preferred = ThemeMemoryModel.safePath(nextBackground)
    let index = preferred ? carouselHasWallpaper(preferred) : -1
    if (index < 0) {
      const fallback = typeof previousIndex === "number" ? previousIndex : selectedIndex
      index = Math.min(Math.max(0, fallback), imageArray.length - 1)
    }
    select(index, true)
    selectedImage = imageArray[index].filePath
  }

  function resetIconDefaults() {
    const themeName = String(currentThemeName || "").trim()
    if (!themeName) return
    const fallback = ThemeMemoryModel.rememberedIconsDefault(themeMemoryState, themeName)
    themeMemoryState = ThemeMemoryModel.clearIcons(themeMemoryState, themeName)
    saveThemeMemoryState()
    const script = pluginScriptPath("reset-icons.sh")
    if (!script) return
    iconResetProc.command = fallback ? [script, themeName, fallback] : [script, themeName]
    iconResetProc.start()
  }

  function openIcons() {
    if (!canOpenIconsMode || iconsBrowseMode) return
    const script = pluginScriptPath("icons-inventory.sh")
    if (!script) return

    if (!iconsMode) {
      iconsPreviousImages = imageArray
      iconsPreviousIndex = selectedIndex
      iconsPreviousFilter = filterText
      iconsPreviousFilterable = filterable
      iconsPreviousShowLabels = showLabels
      iconsPreviousWallpaperRequest = wallpaperPickerRequest
    }

    iconsMode = true
    filterSheet.opened = false
    catalogFilterSheet.opened = false
    imageArray = []
    selectedIndex = 0
    filterText = ""
    filterable = true
    showLabels = true
    imagesLoaded = true
    layoutSettled = true
    iconsInventoryProc.command = [script]
    iconsInventoryProc.start()
    Qt.callLater(focusPicker)
  }

  function acceptIconsInventory(text) {
    const themes = IconThemeModel.loadInventoryRows(String(text || ""))
    iconsInventoryThemes = themes
    updateFooterIconPreviews()
    if (!iconsMode) return
    const rows = IconThemeModel.carouselRows(themes, currentIconTheme)
    imageArray = rows
    selectedIndex = IconThemeModel.indexForIconTheme(rows, currentIconTheme)
    imagesLoaded = true
    layoutSettled = true
    if (rows.length === 0) showStatus("No icon themes found")
    Qt.callLater(focusPicker)
  }

  function leaveIcons(restoreFocus) {
    if (iconsBrowseMode) leaveIconsBrowse(false)
    if (!iconsMode) return
    iconsMode = false
    imageArray = iconsPreviousImages
    selectedIndex = Math.min(iconsPreviousIndex, Math.max(0, imageArray.length - 1))
    filterText = iconsPreviousFilter
    filterable = iconsPreviousFilterable
    showLabels = iconsPreviousShowLabels
    wallpaperPickerRequest = iconsPreviousWallpaperRequest
    iconsPreviousImages = []
    iconsPreviousIndex = 0
    iconsPreviousFilter = ""
    iconsPreviousFilterable = false
    iconsPreviousShowLabels = false
    iconsPreviousWallpaperRequest = false
    if (restoreFocus !== false) Qt.callLater(focusPicker)
  }

  function openIconsBrowse() {
    if (!iconsMode || iconsBrowseMode) return
    const script = pluginScriptPath("icons-browse.sh")
    if (!script) {
      showStatus("Icon browse helper missing")
      return
    }

    iconsBrowsePreviousImages = imageArray
    iconsBrowsePreviousIndex = selectedIndex
    iconsBrowsePreviousFilter = filterText
    iconsBrowseMode = true
    iconBrowseFilterSheet.opened = false
    filterSheet.opened = false
    catalogFilterSheet.opened = false
    imageArray = []
    selectedIndex = 0
    filterText = ""
    filterable = true
    showLabels = true
    imagesLoaded = true
    layoutSettled = true
    iconBrowse.sorting = IconBrowseModel.normalizeFilters(iconsBrowseFilters).sorting
    iconBrowse.search("", false)
    Qt.callLater(focusPicker)
  }

  function leaveIconsBrowse(restoreFocus) {
    if (!iconsBrowseMode) return
    iconsBrowseSearchTimer.stop()
    iconBrowseFilterSheet.opened = false
    iconBrowse.reset()
    iconsBrowseMode = false
    imageArray = iconsBrowsePreviousImages
    selectedIndex = Math.min(iconsBrowsePreviousIndex, Math.max(0, imageArray.length - 1))
    filterText = iconsBrowsePreviousFilter
    iconsBrowsePreviousImages = []
    iconsBrowsePreviousIndex = 0
    iconsBrowsePreviousFilter = ""
    if (restoreFocus !== false) Qt.callLater(focusPicker)
  }

  function acceptIconsBrowseResults(rows, append) {
    if (!iconsBrowseMode || !Array.isArray(rows)) return
    const previousIndex = selectedIndex
    imageArray = append
      ? IconBrowseModel.appendUniqueRows(imageArray, rows)
      : rows
    selectedIndex = append
      ? Math.min(previousIndex, Math.max(0, imageArray.length - 1))
      : 0
    imagesLoaded = true
    layoutSettled = true
    Qt.callLater(focusPicker)
  }

  function searchIconsBrowse() {
    if (!iconsBrowseMode) return
    imageArray = []
    selectedIndex = 0
    iconBrowse.search(filterText, false)
  }

  function maybeLoadMoreIconsBrowse() {
    if (!iconsBrowseMode
        || iconBrowse.loading
        || !iconBrowse.hasMore
        || imageArray.length === 0
        || selectedIndex < Math.max(0, imageArray.length - 10)) return
    iconBrowse.loadMore()
  }

  function currentIconsBrowseFilters() {
    return IconBrowseModel.normalizeFilters(iconsBrowseFilters)
  }

  function openIconsBrowseFilters() {
    if (!iconsBrowseMode || iconBrowse.downloading) return
    iconBrowseFilterSheet.openWith(currentIconsBrowseFilters())
  }

  function applyIconsBrowseFilters(filters) {
    const normalized = IconBrowseModel.normalizeFilters(filters)
    const changed = IconBrowseModel.filterKey(normalized)
      !== IconBrowseModel.filterKey(currentIconsBrowseFilters())
    iconsBrowseFilters = normalized
    iconBrowse.sorting = normalized.sorting
    if (changed) searchIconsBrowse()
  }

  function onIconPackInstalled(themeName, themeNames) {
    const name = String(themeName || "").trim()
    if (!name) return
    leaveIconsBrowse(false)
    if (!iconsMode) openIcons()
    applyIconTheme(name, true)
    const script = pluginScriptPath("icons-inventory.sh")
    if (script) {
      iconsInventoryProc.command = [script]
      iconsInventoryProc.start()
    }
    showStatus("Installed icons · " + IconThemeModel.labelForIconTheme(name))
  }

  function reorderWallpapers() {
    if (!localWallpaperMode || imageArray.length === 0) return
    const selectedPath = currentPath()
    imageArray = WallpaperCommandModel.prioritizeFavorites(
      imageArray,
      favoriteIds,
      wallpaperFavoriteContext())
    selectedIndex = ImagePickerModel.indexForSelectedImage(imageArray, selectedPath)
  }

  function toggleCurrentFavorite() {
    if (!localWallpaperMode) return
    const path = currentPath()
    if (!path) return
    favoriteIds = WallpaperCommandModel.toggleFavorite(
      favoriteIds,
      path,
      wallpaperFavoriteContext())
    if (favoritesOnly && favoriteIds.length === 0) favoritesOnly = false
    reorderWallpapers()
    saveWallpaperCommandState()
    Qt.callLater(focusPicker)
  }

  function toggleFavoritesOnly() {
    if (!localWallpaperMode || favoriteIds.length === 0) return
    favoritesOnly = !favoritesOnly
    if (!itemMatches(selectedIndex)) selectedIndex = firstMatchingIndex()
    Qt.callLater(focusPicker)
  }

  function currentItem() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return null
    return imageArray[selectedIndex]
  }

  function currentPaletteSource() {
    if (!opened || !wallpaperPickerActive) return ""
    const item = currentItem()
    if (!item) return ""
    return String(item.thumbnailPath || item.filePath || "")
  }

  function nameForPath(path) {
    return ImagePickerModel.nameForPath(path)
  }

  function labelForPath(path) {
    return ImagePickerModel.labelForPath(path)
  }

  function currentLabel() {
    const item = currentItem()
    if (!item) return filterText ? "No matches" : ""

    if (wallhavenMode) {
      const parts = [String(item.displayName || "Open wallpaper")]
      if (item.resolution) parts.push(String(item.resolution))
      if (item.category) parts.push(String(item.category))
      if (item.license) parts.push(String(item.license))
      if (item.author) parts.push("by " + String(item.author))
      return parts.join("  ·  ")
    }

    if (iconsBrowseMode) {
      const parts = [String(item.displayName || "Icon pack")]
      if (item.score) parts.push("score " + item.score)
      if (item.downloads) parts.push(item.downloads + " downloads")
      return parts.join("  ·  ")
    }

    if (iconsMode) {
      const parts = [String(item.displayName || item.iconTheme || "Icons")]
      if (item.current || item.iconTheme === currentIconTheme) parts.push("active")
      return parts.join("  ·  ")
    }

    if (item.displayName) return String(item.displayName)
    return labelForPath(item.filePath)
  }

  function currentCatalogMeta() {
    const item = catalogMode ? currentItem() : null
    if (!item) return ""

    const parts = []
    if (item.official) parts.push("Official Omarchy listing")
    else parts.push("Community catalog")
    if (item.owner) parts.push("@" + item.owner)
    if (item.stars > 0) parts.push(item.stars + " ★")
    if (item.warnings && item.warnings.length > 0) parts.push(item.warnings.length + " notes")
    return parts.join("  ·  ")
  }

  function openCatalog() {
    if (wallhavenMode
        || iconsMode
        || !themeManager.themePickerActive
        || !themeManager.inventoryReady
        || catalogMode) return
    themeCatalog.load()
  }

  function openThemeMemberships() {
    if (!themeCollectionsActive || !themeManager.selectedThemeName) return
    collectionsSheet.openMemberships(
      themeCollections.themeLabel(themeManager.selectedThemeName),
      themeManager.selectedThemeName,
      themeCollections.membershipRows())
  }

  function openThemeCollectionCreate() {
    if (!themeCollectionsActive || !themeManager.selectedThemeName) return
    collectionsSheet.openCreate(themeCollections.themeLabel(themeManager.selectedThemeName))
  }

  function openThemeCollectionRename() {
    if (!themeCollections.canRename) {
      showStatus("Highlight a collection in the grid first (Ctrl+G)")
      return
    }
    collectionsSheet.openRename(
      themeCollections.selectedCollection.id,
      themeCollections.selectedCollection.name)
  }

  function filterTypingActive() {
    return wallhavenMode || iconsBrowseMode || iconsMode || catalogMode || filterable
  }

  function canUseLetterShortcut(event) {
    if (!event) return false
    if ((event.modifiers & Qt.ControlModifier) !== 0) return true
    if (filterTypingActive()) return false
    return event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier
  }

  // Cross-nav closes this picker request and opens the other Omarchy switcher.
  function openWallpapersSwitcher() {
    if (wallpaperPickerActive || iconsMode || iconsBrowseMode) return
    if (!(themeManager.themePickerActive || catalogMode)) return
    switcherRun.command = [omarchyBin + "/omarchy-theme-bg-switcher"]
    switcherRun.start()
    cancel()
  }

  function openThemesSwitcher() {
    if (themeManager.themePickerActive && !wallpaperPickerActive && !iconsMode && !iconsBrowseMode) return
    if (!(localWallpaperMode || wallhavenMode || iconsMode || iconsBrowseMode)) return
    switcherRun.command = [omarchyBin + "/omarchy-theme-switcher"]
    switcherRun.start()
    cancel()
  }

  function browseForCurrentMode() {
    if (localWallpaperMode) {
      openWallhaven()
      return true
    }
    if (localIconsMode) {
      openIconsBrowse()
      return true
    }
    if (themeManager.themePickerActive && !catalogMode && !wallpaperPickerActive && !iconsMode && !iconsBrowseMode) {
      openCatalog()
      return true
    }
    return false
  }

  function enterCatalog(rows) {
    if (wallhavenMode || iconsMode || iconsBrowseMode || !Array.isArray(rows) || rows.length === 0) return

    if (!catalogMode) {
      catalogPreviousImages = imageArray
      catalogPreviousIndex = selectedIndex
      catalogPreviousFilter = filterText
      catalogPreviousFilterable = filterable
      catalogPreviousShowLabels = showLabels
    }

    catalogMode = true
    catalogSourceRows = rows
    filterable = true
    showLabels = true
    filterText = catalogStickyQuery
    refreshCatalogRows()
    Qt.callLater(focusPicker)
  }

  function leaveCatalog(restoreFocus) {
    if (!catalogMode) return

    catalogStickyQuery = ThemeCatalogModel.normalizeCatalogQuery(filterText)
    persistCatalogFilters()
    catalogFilterSheet.opened = false
    catalogMode = false
    catalogSourceRows = []
    imageArray = catalogPreviousImages
    selectedIndex = Math.min(catalogPreviousIndex, Math.max(0, imageArray.length - 1))
    filterText = catalogPreviousFilter
    filterable = catalogPreviousFilterable
    showLabels = catalogPreviousShowLabels
    catalogPreviousImages = []
    catalogPreviousIndex = 0
    catalogPreviousFilter = ""
    catalogPreviousFilterable = false
    catalogPreviousShowLabels = false

    if (restoreFocus !== false) Qt.callLater(focusPicker)
  }

  function removeThemeFromRows(name) {
    if (catalogMode || wallhavenMode || iconsMode || iconsBrowseMode) return

    const previousIndex = selectedIndex
    const nextImages = ThemeManagerModel.withoutNamedImage(imageArray, name)
    imageArray = nextImages
    loadedImageRows = ""

    if (nextImages.length === 0) {
      cancel()
      return
    }

    selectedIndex = Math.min(previousIndex, nextImages.length - 1)
    Qt.callLater(focusPicker)
  }

  function itemMatches(index) {
    return index >= 0
      && index < matchingPositions.length
      && matchingPositions[index] >= 0
  }

  function firstMatchingIndex() {
    return matchingIndices.length > 0 ? matchingIndices[0] : -1
  }

  function filteredPosition(index) {
    return index >= 0 && index < matchingPositions.length
      ? matchingPositions[index]
      : -1
  }

  function selectedFilteredPosition() {
    return filteredPosition(selectedIndex)
  }

  function syncCarouselCursor() {
    const position = selectedFilteredPosition()
    if (position >= 0) {
      carouselCursor = ImagePickerModel.nearestWrappedCursor(
        carouselCursor,
        position,
        matchingIndices.length)
    } else if (matchingIndices.length > 0) {
      carouselCursor = 0
      selectedIndex = matchingIndices[0]
    } else {
      carouselCursor = 0
    }
  }

  function select(index, immediate, virtualCursor) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    const position = filteredPosition(index)
    carouselCursor = Number.isFinite(virtualCursor)
      ? virtualCursor
      : ImagePickerModel.nearestWrappedCursor(
          carouselCursor,
          position,
          matchingIndices.length)
    selectedIndex = index
    if (wallhavenMode) Qt.callLater(maybeLoadMoreWallhaven)
    if (iconsBrowseMode) Qt.callLater(maybeLoadMoreIconsBrowse)
  }

  function selectAdjacent(direction) {
    const count = matchingIndices.length
    if (count === 0) return

    const nextCursor = carouselCursor + direction
    const position = ImagePickerModel.wrappedIndex(nextCursor, count)
    select(matchingIndices[position], false, nextCursor)
  }

  function updateFilter(nextFilterText) {
    if (wallhavenMode) {
      filterText = WallpaperBrowserModel.normalizeQuery(nextFilterText)
      wallhavenStickyQuery = filterText
      wallhavenSearchTimer.restart()
      wallhavenPersistTimer.restart()
      return
    }

    if (iconsBrowseMode) {
      filterText = IconBrowseModel.normalizeQuery(nextFilterText)
      iconsBrowseSearchTimer.restart()
      return
    }

    if (catalogMode) {
      filterText = ThemeCatalogModel.normalizeCatalogQuery(nextFilterText)
      catalogStickyQuery = filterText
      refreshCatalogRows()
      catalogPersistTimer.restart()
      return
    }

    filterText = nextFilterText
    if (!itemMatches(selectedIndex)) {
      const first = firstMatchingIndex()
      if (first >= 0) selectedIndex = first
    }
  }

  function searchWallhaven() {
    if (!wallhavenMode) return

    imageArray = []
    selectedIndex = 0
    wallhaven.search(filterText, false)
  }

  function maybeLoadMoreWallhaven() {
    if (!wallhavenMode
        || wallhaven.loading
        || !wallhaven.hasMore
        || imageArray.length === 0
        || selectedIndex < Math.max(0, imageArray.length - 10)) return

    wallhaven.loadMore()
  }

  function openWallhavenFilters() {
    if (!wallhavenMode || wallhaven.downloading) return
    wallhavenSearchTimer.stop()
    filterSheet.openWith(currentWallhavenFilters())
  }

  function applyWallhavenFilters(filters) {
    const normalized = WallpaperBrowserModel.normalizeFilters(filters)
    const changed = WallpaperBrowserModel.filterKey(normalized)
      !== WallpaperBrowserModel.filterKey(currentWallhavenFilters())
    wallhaven.collection = normalized.collection
    wallhaven.sorting = normalized.sorting
    wallhaven.license = normalized.license
    persistWallhavenFilters()

    if (changed) searchWallhaven()
    else Qt.callLater(focusPicker)
  }

  function currentCatalogFilters() {
    return ThemeCatalogModel.normalizeCatalogFilters(catalogFilters)
  }

  function loadCatalogFiltersState(raw) {
    const state = ThemeCatalogModel.parseCatalogFilterState(raw)
    catalogFilters = state.filters
    catalogStickyQuery = state.query
    if (catalogMode) refreshCatalogRows()
  }

  function persistCatalogFilters() {
    catalogFiltersFile.save(
      ThemeCatalogModel.serializeCatalogFilters(catalogFilters, catalogStickyQuery)
    )
  }

  function refreshCatalogRows() {
    if (!catalogMode) return

    const source = Array.isArray(catalogSourceRows) ? catalogSourceRows : []
    const selectedPath = currentPath()
    const textMatched = ImagePickerModel.matchingIndices(source, filterText)
      .map(function(index) { return source[index] })

    // Prefer AND of text + sheet filters. If that yields nothing but the name
    // search itself hits rows, fall back to text-only so sticky stars/listing
    // filters do not create false "no results" for an exact theme name.
    let nextRows = ThemeCatalogModel.applyCatalogFilters(textMatched, catalogFilters)
    if (nextRows.length === 0 && filterText && textMatched.length > 0 && catalogFiltersActive) {
      // Name search wins over restrictive sticky sheet filters (keep sort only).
      nextRows = ThemeCatalogModel.applyCatalogFilters(textMatched, {
        listing: "all",
        availability: "all",
        sort: catalogFilters.sort,
        minStars: 0
      })
    }

    imageArray = nextRows
    if (imageArray.length === 0) {
      selectedIndex = 0
      return
    }

    const restored = ImagePickerModel.indexForSelectedImage(imageArray, selectedPath)
    selectedIndex = selectedPath && imageArray[restored] && imageArray[restored].filePath === selectedPath
      ? restored
      : 0
  }

  function openCatalogFilters() {
    if (!catalogMode) return
    catalogFilterSheet.openWith(currentCatalogFilters())
  }

  function applyThemeCatalogFilters(filters) {
    const normalized = ThemeCatalogModel.normalizeCatalogFilters(filters)
    catalogFilters = normalized
    persistCatalogFilters()

    if (!catalogMode) {
      Qt.callLater(focusPicker)
      return
    }

    refreshCatalogRows()
    Qt.callLater(focusPicker)
  }

  function loadWallhavenFiltersState(raw) {
    const state = WallpaperBrowserModel.parseFilters(raw)
    wallhaven.collection = state.filters.collection
    wallhaven.sorting = state.filters.sorting
    wallhaven.license = state.filters.license
    wallhavenStickyQuery = state.query
    wallhavenFiltersReady = true
  }

  function persistWallhavenFilters() {
    wallhavenFiltersFile.save(
      WallpaperBrowserModel.serializeFilters(currentWallhavenFilters(), wallhavenStickyQuery)
    )
  }

  function openWallhaven() {
    if (catalogMode || iconsMode || iconsBrowseMode || !wallpaperPickerActive || wallhavenMode) return

    localImages = imageArray
    localSelectedIndex = selectedIndex
    localFilterText = filterText
    wallhavenMode = true
    filterSheet.opened = false
    catalogFilterSheet.opened = false
    imageArray = []
    selectedIndex = 0
    filterText = wallhavenStickyQuery
    imagesLoaded = true
    layoutSettled = true
    wallhaven.search(filterText, false)
    Qt.callLater(focusPicker)
  }

  function leaveWallhaven(restoreFocus) {
    if (!wallhavenMode) return

    wallhavenStickyQuery = WallpaperBrowserModel.normalizeQuery(filterText)
    persistWallhavenFilters()
    wallhavenSearchTimer.stop()
    wallhavenPersistTimer.stop()
    filterSheet.opened = false
    wallhaven.reset()
    wallhavenMode = false
    imageArray = localImages
    selectedIndex = Math.min(localSelectedIndex, Math.max(0, imageArray.length - 1))
    filterText = localFilterText
    localImages = []
    localSelectedIndex = 0
    localFilterText = ""

    if (restoreFocus !== false) Qt.callLater(focusPicker)
  }

  function acceptWallhavenResults(rows, append) {
    if (!wallhavenMode || !Array.isArray(rows)) return

    const previousIndex = selectedIndex
    imageArray = append
      ? WallpaperBrowserModel.appendUniqueRows(imageArray, rows)
      : rows
    selectedIndex = append
      ? Math.min(previousIndex, Math.max(0, imageArray.length - 1))
      : 0
    imagesLoaded = true
    layoutSettled = true
    Qt.callLater(focusPicker)
  }

  function finishDoneFile(path) {
    if (!path) return
    // A plugin rescan destroys this QML object immediately after close(), so
    // the completion mark is written from this process, synchronously.
    writeSmallFile(path, "")
  }

  function finishSelection(path) {
    if (!path || !selectionFile) {
      cancel()
      return
    }

    const themeName = ThemeMemoryModel.safeThemeName(currentThemeName)
    const target = ThemeMemoryModel.safePath(path)
    if (wallpaperPickerActive && themeName && target
        && ThemeMemoryModel.needsWallpaperInstall(target, homeDir, themeName)) {
      const activeSelectionFile = selectionFile
      const activeDoneFile = doneFile
      const serial = requestSerial
      applySerial = serial
      requestActive = false
      selectionFile = ""
      doneFile = ""
      if (beginWallpaperInstall("finish", target, activeSelectionFile, activeDoneFile, serial))
        return
      // Fall through with the original path if install could not start.
      selectionFile = activeSelectionFile
      doneFile = activeDoneFile
      requestActive = !!doneFile
    }

    if (wallpaperPickerActive) rememberWallpaperSelection(path)

    const activeSelectionFile = selectionFile
    const activeDoneFile = doneFile
    applySerial = requestSerial
    requestActive = false
    selectionFile = ""
    doneFile = ""

    writeSmallFile(activeSelectionFile, path + "\n")
    writeSmallFile(activeDoneFile, "")
    if (applySerial === requestSerial)
      opened = false
  }

  function applySelected() {
    if (catalogMode) {
      themeCatalog.requestPrimaryAction()
      return
    }

    if (iconsBrowseMode) {
      const item = currentItem()
      if (!item || iconBrowse.downloading) return
      iconBrowse.requestInstall(item)
      return
    }

    if (iconsMode) {
      const item = currentItem()
      if (!item || !item.iconTheme) return
      applyIconTheme(String(item.iconTheme), true)
      return
    }

    if (wallhavenMode) {
      const item = currentItem()
      if (!item || wallhaven.downloading) return
      wallhaven.download(String(item.id || ""))
      return
    }

    finishSelection(currentPath())
  }

  function cancel() {
    if (catalogMode) leaveCatalog(false)
    if (wallhavenMode) leaveWallhaven(false)
    if (iconsBrowseMode) leaveIconsBrowse(false)
    if (iconsMode) leaveIcons(false)

    if (requestActive)
      finishDoneFile(doneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    root.opened = false
  }

  function closeSelector(nextDoneFile) {
    if (catalogMode) leaveCatalog(false)
    if (wallhavenMode) leaveWallhaven(false)
    if (iconsBrowseMode) leaveIconsBrowse(false)
    if (iconsMode) leaveIcons(false)
    requestSerial += 1

    if (requestActive)
      finishDoneFile(doneFile)

    if (nextDoneFile && nextDoneFile !== doneFile)
      finishDoneFile(nextDoneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    filterText = ""
    root.opened = false
  }

  function loadRows(rows, reveal) {
    let newImages = ImagePickerModel.loadRows(rows)
    if (wallpaperPickerActive)
      newImages = WallpaperCommandModel.prioritizeFavorites(
        newImages,
        favoriteIds,
        wallpaperFavoriteContext())

    root.loadedImageRows = rows
    root.selectedIndex = root.indexForSelectedImage(newImages)
    root.replaceImageArray(newImages)
    root.imagesLoaded = true
    root.layoutSettled = true

    if (localWallpaperMode)
      ensureRememberedWallpaperInPicker()

    if (reveal !== false) {
      root.opened = true
      root.revealWhenSettled(root.requestSerial)
    }
  }

  function openSelector(nextImageDirs, nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
    // Warm the Icons chip before first paint.
    ensureFooterIconsReady()
    if (catalogMode) leaveCatalog(false)
    if (wallhavenMode) leaveWallhaven(false)
    if (iconsBrowseMode) leaveIconsBrowse(false)
    if (iconsMode) leaveIcons(false)
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageDirs = nextImageDirs
    imageRows = nextImageRows
    wallpaperPickerRequest = WallpaperBrowserModel.isWallpaperPickerRequest(
      imageDirs,
      imageRows
    )
    // Row-backed wallpaper opens leave imageDirs empty; keep scan dirs ready for Remove.
    if (wallpaperPickerRequest)
      imageDirs = localWallpaperScanDirs() || imageDirs
    selectedImage = nextSelectedImage
    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    favoritesOnly = false
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      root.select(root.selectedImageIndex(), true)
      imagesLoaded = true
      opened = true
      root.revealWhenSettled(requestSerial)
      return
    }

    if (imageRows) {
      const rowsToLoad = imageRows
      const rowsSerial = requestSerial
      imageArray = []
      selectedIndex = 0
      imagesLoaded = true
      opened = true
      Qt.callLater(function() {
        if (rowsSerial === root.requestSerial)
          root.loadRows(rowsToLoad, true)
      })
      return
    }

    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    startImageScan(requestSerial, imageDirs)
  }

  property var imageArray: []
  // Bumped on every intentional model replace so index-bound delegates re-read
  // root.imageArray[index] even when length stays the same.
  property int imageModelEpoch: 0
  readonly property bool searchAlreadyApplied: wallhavenMode || iconsBrowseMode || catalogMode
  readonly property var textMatchingIndices: ImagePickerModel.matchingIndices(
    imageArray,
    searchAlreadyApplied ? "" : filterText)
  readonly property var matchingIndices: {
    if (!(localWallpaperMode && favoritesOnly))
      return themeCollectionsActive ? themeCollections.matchingIndices : textMatchingIndices
    const next = []
    for (let position = 0; position < textMatchingIndices.length; position++) {
      const index = textMatchingIndices[position]
      const item = index >= 0 && index < imageArray.length ? imageArray[index] : null
      if (item && WallpaperCommandModel.isFavorite(
          favoriteIds,
          item.filePath,
          wallpaperFavoriteContext())) next.push(index)
    }
    return next
  }
  readonly property var matchingPositions: ImagePickerModel.positionsForIndices(
    matchingIndices,
    imageArray.length)
  readonly property int carouselPoolSize: 17
  property int carouselCursor: 0

  onMatchingIndicesChanged: syncCarouselCursor()
  onSelectedIndexChanged: syncCarouselCursor()

  function replaceImageArray(next) {
    imageArray = Array.isArray(next) ? next.slice() : []
    imageModelEpoch += 1
  }

  function startImageScan(serial, dirs) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      loadImagesProc.queuedDirs = dirs
      return
    }

    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.queuedDirs = ""
    loadImagesProc.command = [root.scriptPath("list.sh"), dirs]
    loadImagesProc.start()
  }

  function indexForSelectedImage(images) {
    return ImagePickerModel.indexForSelectedImage(images, selectedImage)
  }

  function selectedImageIndex() {
    return indexForSelectedImage(imageArray)
  }

  // Omarchy's list.sh walks the wallpaper directories and makes missing
  // thumbnails with ImageMagick: a first run over a few hundred images can
  // take a while, so 120 s; one line per image, so 1 MiB holds thousands.
  Run {
    id: loadImagesProc

    property int activeSerial: 0
    property int queuedSerial: 0
    property string queuedDirs: ""
    environment: root.helperEnvironment
    deadlineMs: 120000
    maxBytes: 1048576
    keepBytes: 1048576

    onFinished: function(result) {
      if (activeSerial === root.requestSerial) {
        const reveal = !root.refreshInPlace
        root.refreshInPlace = false
        root.loadRows(result.state === "ok" ? String(result.stdout || "") : "", reveal)
        if (!reveal)
          Qt.callLater(root.focusPicker)
      }
      const serial = queuedSerial
      const dirs = queuedDirs
      activeSerial = 0
      queuedSerial = 0
      queuedDirs = ""
      if (serial > 0 && serial === root.requestSerial)
        root.startImageScan(serial, dirs)
    }
  }

  PluginState {
    id: catalogFiltersFile
    pluginId: root.pluginId
    name: "theme-catalog-filters.json"
    legacyPath: root.catalogFiltersPath
    onTextReady: function(text) { root.loadCatalogFiltersState(text) }
    onSaveFailed: root.showStatus("Catalog filters could not be saved")
  }

  PluginState {
    id: wallhavenFiltersFile
    pluginId: root.pluginId
    name: "wallpaper-browser-filters.json"
    legacyPath: root.wallhavenFiltersPath
    onTextReady: function(text) { root.loadWallhavenFiltersState(text) }
    onSaveFailed: root.showStatus("Wallpaper filters could not be saved")
  }

  PluginState {
    id: wallpaperCommandState
    pluginId: root.pluginId
    name: "wallpaper-command-center.json"
    legacyPath: root.wallpaperCommandStatePath
    onTextReady: function(text) { root.loadWallpaperCommandState(text) }
    onSaveFailed: root.showStatus("Starred wallpapers could not be saved")
  }

  PluginState {
    id: themeMemoryStateFile
    pluginId: root.pluginId
    name: "theme-manager-memory.json"
    legacyPath: root.themeMemoryStatePath
    onTextReady: function(text) {
      root.loadThemeMemoryState(text)
      root.lastRestoredThemeName = ""
      if (root.currentThemeName)
        root.scheduleThemeMemoryRestore(root.currentThemeName, true)
    }
    onSaveFailed: root.showStatus("Theme memory could not be saved")
  }

  FileView {
    id: currentThemeNameFile
    path: root.currentThemeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      const nextName = String(text() || "").trim().slice(0, 255)
      const changed = nextName !== root.currentThemeName
      root.currentThemeName = nextName
      if (changed) {
        root.lastRestoredThemeName = ""
        root.scheduleThemeMemoryRestore(nextName, true)
      }
      if (root.localWallpaperMode && root.imageArray.length > 0)
        root.reorderWallpapers()
    }
    onLoadFailed: root.currentThemeName = ""
    onFileChanged: reload()
  }

  FileView {
    id: currentIconsThemeFile
    path: root.currentIconsThemePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      const value = String(text() || "").trim().slice(0, 255)
      if (value) {
        root.currentIconTheme = value
      } else {
        root.ensureCurrentIconTheme()
      }
    }
    onLoadFailed: root.ensureCurrentIconTheme()
    onFileChanged: reload()
  }

  WallpaperPalette {
    id: wallpaperPalette
    sourcePath: root.currentPaletteSource()
    fallbackBase: Color.background
    fallbackAccent: Color.accent
  }

  // Lifecycle hooks invoked by omarchy-shell summon/hide. The shell host owns
  // the stable image-selector IPC target and forwards positional calls here.
  function open(payload) {
    let args = {}
    if (payload) {
      try { args = JSON.parse(payload) || {} } catch (_error) { args = {} }
    }
    const dirs = String(args.imageDirs || imageDirs)
    const rows = String(args.imageRows || "")
    const sel = String(args.selectedImage || selectedImage)
    const selFile = String(args.selectionFile || "")
    const doneF = String(args.doneFile || "")
    const labels = args.showLabels === true || args.showLabels === "true"
    const filter = args.filterable === true || args.filterable === "true"
    openSelector(dirs, rows, sel, selFile, doneF, labels, filter)
  }

  function close() {
    cancel()
  }

  function preloadRows(nextImageRows, nextSelectedImage, nextShowLabels, nextFilterable) {
    // Ignore warmups while a visible request is active. Otherwise a preload
    // resets layoutSettled and can leave only the fullscreen scrim visible.
    if (opened || requestActive) return

    requestSerial += 1
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      selectedIndex = selectedImageIndex()
      imagesLoaded = true
    } else if (imageRows) {
      loadRows(imageRows, false)
    }
  }

  Timer {
    id: wallhavenSearchTimer
    interval: 450
    repeat: false
    onTriggered: {
      if (root.wallhavenMode)
        root.searchWallhaven()
    }
  }

  Timer {
    id: wallhavenPersistTimer
    interval: 500
    repeat: false
    onTriggered: root.persistWallhavenFilters()
  }

  Timer {
    id: catalogPersistTimer
    interval: 500
    repeat: false
    onTriggered: root.persistCatalogFilters()
  }

  Timer {
    id: iconsBrowseSearchTimer
    interval: 450
    repeat: false
    onTriggered: {
      if (root.iconsBrowseMode)
        root.searchIconsBrowse()
    }
  }

  Timer {
    id: themeMemoryRestoreTimer
    interval: 250
    repeat: true
    property string themeName: ""
    property int waitedMs: 0
    property bool lockFree: false
    onTriggered: {
      waitedMs += interval
      // Lock file persists after unlock; probe flock ownership instead of existence.
      if (!themeSetLockProbe.running) {
        themeSetLockProbe.command = [root.pluginScriptPath("probe-theme-lock.sh")]
        themeSetLockProbe.start()
      }
      if (waitedMs >= 8000) {
        stop()
        root.restoreThemeMemory(themeName)
      }
    }
  }

  Timer {
    id: themeMemoryVerifyTimer
    interval: 3500
    repeat: false
    property string themeName: ""
    property string expectedWallpaper: ""
    onTriggered: root.verifyThemeMemoryRestore(themeName, expectedWallpaper)
  }

  Timer {
    id: statusToastTimer
    interval: 2200
    repeat: false
    onTriggered: root.statusToast = ""
  }

  // The small file writer behind writeSmallFile: the selection and done
  // files, written synchronously from this process.
  FileView {
    id: smallFileWriter
    blockWrites: true
    printErrors: false
  }

  // omarchy-theme-bg-set links the background and tells the shell over IPC:
  // a second at most, 15 s is generous; a line or two of output.
  Run {
    id: memoryBgProc
    environment: root.omarchyEnvironment
    deadlineMs: 15000
    maxBytes: 65536
    onFinished: root.restoringThemeMemory = false
  }

  // xdg-open hands a repository URL to the browser and returns; 30 s covers
  // a handler that waits for the browser to start.
  Run {
    id: sourceOpener
    environment: root.omarchyEnvironment
    deadlineMs: 30000
    maxBytes: 4096
  }

  // The switchers open Omarchy's own menus and live as long as the picker
  // they open; a menu the user left open for half an hour is ended.
  Run {
    id: switcherRun
    environment: root.omarchyEnvironment
    deadlineMs: 1800000
    maxBytes: 65536
  }

  // flock -n answers at once: 5 s covers a stalled runtime directory.
  Run {
    id: themeSetLockProbe
    deadlineMs: 5000
    maxBytes: 4096
    onFinished: function(result) {
      if (result.state === "ok")
        themeMemoryRestoreTimer.lockFree = true
      if (!themeMemoryRestoreTimer.running)
        return
      if (themeMemoryRestoreTimer.lockFree || themeMemoryRestoreTimer.waitedMs >= 8000) {
        themeMemoryRestoreTimer.stop()
        root.restoreThemeMemory(themeMemoryRestoreTimer.themeName)
      }
    }
  }

  // verify-wallpaper.sh stats one file and reads one symlink: 5 s; one word.
  Run {
    id: themeMemoryVerifyProc
    property string themeName: ""
    property string expectedWallpaper: ""
    deadlineMs: 5000
    maxBytes: 4096
    onFinished: function(result) {
      const status = result.state === "ok" ? String(result.stdout || "").trim() : ""
      if (status === "MISSING")
        root.pruneRememberedWallpaper(themeName)
      else if (status === "MISMATCH")
        root.restoreThemeMemory(themeName)
    }
  }

  // install-hook.sh copies one small file: 5 s; no output.
  Run {
    id: hookInstallProc
    deadlineMs: 5000
    maxBytes: 4096
  }

  // gsettings get answers the session bus once: 10 s covers a busy dconf.
  Run {
    id: iconThemeProbeProc
    environment: root.omarchyEnvironment
    deadlineMs: 10000
    maxBytes: 4096
    onFinished: function(result) {
      if (result.state === "ok") root.acceptIconThemeProbe(String(result.stdout || ""))
    }
  }

  // icons-inventory.sh walks the icon directories: 30 s for a slow disk,
  // one row per theme, 1 MiB holds hundreds.
  Run {
    id: footerIconsInventoryProc
    environment: root.helperEnvironment
    deadlineMs: 30000
    maxBytes: 1048576
    keepBytes: 1048576
    onFinished: function(result) {
      if (result.state !== "ok") return
      root.iconsInventoryThemes = IconThemeModel.loadInventoryRows(String(result.stdout || ""))
      root.updateFooterIconPreviews()
    }
  }

  // apply-icons.sh writes one file and sets one gsettings key: 10 s.
  Run {
    id: iconApplyProc
    environment: root.omarchyEnvironment
    deadlineMs: 10000
    maxBytes: 4096
  }

  // reset-icons.sh reads the theme directory through omarchy-theme-dir and
  // sets one gsettings key: 10 s; one word of output.
  Run {
    id: iconResetProc
    environment: root.omarchyEnvironment
    deadlineMs: 10000
    maxBytes: 4096
    onFinished: function(result) {
      const value = result.state === "ok" ? String(result.stdout || "").trim() : ""
      if (value) {
        root.currentIconTheme = value
        root.showStatus("Icon defaults · " + IconThemeModel.labelForIconTheme(value))
      } else {
        root.showStatus("Icon defaults restored")
      }
    }
  }

  // icons-inventory.sh again, for icons mode: the same bounds.
  Run {
    id: iconsInventoryProc
    environment: root.helperEnvironment
    deadlineMs: 30000
    maxBytes: 1048576
    keepBytes: 1048576
    onFinished: function(result) {
      if (result.state === "ok") {
        root.acceptIconsInventory(String(result.stdout || ""))
      } else if (root.iconsMode) {
        root.acceptIconsInventory("")
        root.showStatus("Icon inventory failed")
      }
    }
  }

  // remove-wallpaper.sh deletes one file and may set the next background
  // through omarchy-theme-bg-set: 15 s; one path of output.
  Run {
    id: wallpaperRemoveProc
    property bool clearMemory: false
    property string removedPath: ""
    property string themeName: ""
    environment: root.omarchyEnvironment
    deadlineMs: 15000
    maxBytes: 65536
    onFinished: function(result) {
      if (result.state === "ok") {
        root.acceptRemovedInstalledWallpaper(String(result.stdout || "").trim())
        return
      }
      wallpaperRemoveProc.removedPath = ""
      wallpaperRemoveProc.themeName = ""
      wallpaperRemoveProc.clearMemory = false
      // Restore carousel after optimistic drop when the script fails.
      root.reloadLocalWallpapersFromDisk("", "")
      root.showStatus("Wallpaper remove failed")
    }
  }

  // reset-wallpaper.sh removes the theme's user backgrounds and sets the
  // stock one through omarchy-theme-bg-set: 15 s; one path of output.
  Run {
    id: wallpaperResetProc
    property string themeName: ""
    environment: root.omarchyEnvironment
    deadlineMs: 15000
    maxBytes: 65536
    onFinished: function(result) {
      root.restoringThemeMemory = false
      if (result.state === "ok") {
        root.acceptResetWallpaper(String(result.stdout || "").trim())
        return
      }
      wallpaperResetProc.themeName = ""
      root.showStatus("Wallpaper reset failed")
    }
  }

  // install-wallpaper.sh copies one image into the theme's backgrounds:
  // a 20 MiB file on a slow disk is seconds, so 30 s; one path of output.
  Run {
    id: wallpaperInstallProc
    environment: root.helperEnvironment
    deadlineMs: 30000
    maxBytes: 65536
    onFinished: function(result) {
      if (result.state === "ok") {
        let installed = String(result.stdout || "").trim()
        if (!installed) {
          installed = ThemeMemoryModel.installedWallpaperPath(
            root.pendingInstallSourcePath,
            root.homeDir,
            root.currentThemeName)
        }
        root.acceptInstalledWallpaper(installed)
        return
      }
      const purpose = String(root.pendingInstallPurpose || "")
      root.clearPendingInstall()
      if (purpose === "finish") {
        root.cancel()
        return
      }
      // ensure/migrate with a vanished catalog source must not keep stale memory.
      if (purpose === "ensure" || purpose === "migrate" || purpose === "migrate-restore")
        root.pruneRememberedWallpaper(root.currentThemeName)
      if (purpose) root.showStatus("Wallpaper install failed")
    }
  }

  IconBrowseController {
    id: iconBrowse
    scriptPath: root.pluginScriptPath("icons-browse.sh")
    helperEnvironment: root.helperEnvironment
    sorting: IconBrowseModel.normalizeFilters(root.iconsBrowseFilters).sorting
    onResultsReady: function(rows, append) { root.acceptIconsBrowseResults(rows, append) }
    onIconInstalled: function(themeName, themeNames) { root.onIconPackInstalled(themeName, themeNames) }
    onFocusRequested: Qt.callLater(root.focusPicker)
  }

  WallpaperBrowserController {
    id: wallhaven
    commandPath: root.pluginScriptPath("wallpaper-catalog.py")
    helperEnvironment: root.helperEnvironment
    onResultsReady: function(rows, append) { root.acceptWallhavenResults(rows, append) }
    onWallpaperReady: function(path) {
      if (root.wallhavenMode) root.finishSelection(path)
    }
    onFocusRequested: Qt.callLater(root.focusPicker)
  }

  ThemeManagerController {
    id: themeManager
    selectedPath: root.currentPath()
    pickerOpen: root.opened
    inventoryScriptPath: root.pluginScriptPath("theme-inventory.sh")
    omarchyBin: root.omarchyBin
    helperEnvironment: root.helperEnvironment
    omarchyEnvironment: root.omarchyEnvironment
    onThemeRemoved: function(name) { root.removeThemeFromRows(name) }
    onFocusRequested: Qt.callLater(root.focusPicker)
  }

  ThemeCatalogController {
    id: themeCatalog
    catalogScriptPath: root.pluginScriptPath("catalog.sh")
    installScriptPath: root.pluginScriptPath("install-theme.py")
    helperEnvironment: root.helperEnvironment
    omarchyEnvironment: root.omarchyEnvironment
    pickerOpen: root.opened
    installedThemes: themeManager.installedThemes
    stockThemes: themeManager.stockThemes
    installedRepositories: themeManager.installedRepositories
    selectedEntry: root.catalogMode ? root.currentItem() : null
    onCatalogLoaded: function(rows) { root.enterCatalog(rows) }
    onThemeInstalled: root.cancel()
    onSourceRequested: function(repositoryUrl) {
      sourceOpener.command = ["/usr/bin/xdg-open", repositoryUrl]
      sourceOpener.start()
    }
    onFocusRequested: Qt.callLater(root.focusPicker)
  }

  ThemeCollectionsController {
    id: themeCollections
    pluginId: root.pluginId
    statePath: root.themeCollectionsStatePath
    pickerOpen: root.opened
    active: root.themeCollectionsActive
    images: root.imageArray
    textMatchingIndices: root.textMatchingIndices
    filterText: root.filterText
    stockThemes: themeManager.stockThemes
    inventoryReady: themeManager.inventoryReady
    currentThemeName: root.currentThemeName
    selectedThemeName: themeManager.selectedThemeName
    selectedIndex: root.selectedIndex
    gridWidth: Math.min(carousel.width, card.width)
    gridHeight: carousel.height
    poolSize: root.carouselPoolSize
    onSelectionRequested: function(imageIndex) { root.select(imageIndex, true) }
    onStatusMessage: function(message) { root.showStatus(message) }
    onFocusRequested: Qt.callLater(root.focusPicker)
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded
      color: root.activeScrim
      Behavior on color { ColorAnimation { duration: 360; easing.type: Easing.OutCubic } }
    }

    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded && root.livePaletteReady
      opacity: 0.42
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0; color: Util.alpha(root.livePaletteSecondary, 0.28) }
        GradientStop { position: 0.48; color: "transparent" }
        GradientStop { position: 1; color: Util.alpha(root.livePaletteAccent, 0.24) }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened && root.imagesLoaded
      onClicked: root.cancel()
    }

    Item {
      id: keyHandler
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (catalogFilterSheet.opened) {
          if (catalogFilterSheet.handleKey(event)) event.accepted = true
          return
        }

        if (filterSheet.opened) {
          if (filterSheet.handleKey(event)) event.accepted = true
          return
        }

        if (collectionsSheet.opened) {
          if (collectionsSheet.handleKey(event)) event.accepted = true
          return
        }

        if (wallpaperActionsDropdown.popupOpen) {
          if (event.key === Qt.Key_Escape) {
            wallpaperActionsDropdown.close()
            event.accepted = true
          }
          return
        }

        if (iconBrowse.confirmationOpen) {
          if (iconInstallConfirm.handleKey(event)) event.accepted = true
        } else if (themeCatalog.confirmationOpen) {
          if (catalogInstallConfirm.handleKey(event)) event.accepted = true
        } else if (themeManager.confirmationOpen) {
          if (uninstallConfirm.handleKey(event)) event.accepted = true
        } else if (iconBrowseFilterSheet.opened) {
          if (iconBrowseFilterSheet.handleKey(event)) event.accepted = true
        } else if (event.key === Qt.Key_Delete
                   && !root.catalogMode
                   && !root.wallhavenMode
                   && !root.iconsMode
                   && !root.iconsBrowseMode
                   && themeManager.themePickerActive) {
          if (!themeCollections.removeSelectedFromCollection())
            themeManager.requestUninstall()
          event.accepted = true
        } else if (event.key === Qt.Key_G
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.themeCollectionsActive) {
          themeCollections.toggleGrid()
          event.accepted = true
        } else if (event.key === Qt.Key_M
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.themeCollectionsActive) {
          root.openThemeMemberships()
          event.accepted = true
        } else if (event.key === Qt.Key_N
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && (event.modifiers & Qt.ShiftModifier) !== 0
                   && root.themeCollectionsActive) {
          root.openThemeCollectionCreate()
          event.accepted = true
        } else if (event.key === Qt.Key_R
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.themeCollectionsActive) {
          root.openThemeCollectionRename()
          event.accepted = true
        } else if (event.key === Qt.Key_D
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && (event.modifiers & Qt.ShiftModifier) !== 0
                   && root.themeCollectionsActive) {
          themeCollections.toggleFavoritesOnly()
          event.accepted = true
        } else if (event.key === Qt.Key_D
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.themeCollectionsActive) {
          themeCollections.toggleFavorite()
          event.accepted = true
        } else if (event.key === Qt.Key_I
            && (event.modifiers & Qt.ControlModifier) !== 0
            && root.canOpenIconsMode) {
          root.openIcons()
          event.accepted = true
        } else if (event.key === Qt.Key_T
                   && root.canUseLetterShortcut(event)
                   && (root.localWallpaperMode || root.wallhavenMode || root.iconsMode || root.iconsBrowseMode)) {
          // Ctrl+T always; bare T only when filter typing is inactive.
          if (root.iconsBrowseMode) root.leaveIconsBrowse(false)
          if (root.iconsMode) root.leaveIcons(false)
          if (root.wallhavenMode) root.leaveWallhaven(false)
          root.openThemesSwitcher()
          event.accepted = true
        } else if (event.key === Qt.Key_W
                   && root.canUseLetterShortcut(event)) {
          if (root.wallhavenMode) {
            root.leaveWallhaven(true)
            event.accepted = true
          } else if (root.catalogMode) {
            root.leaveCatalog(false)
            root.openWallpapersSwitcher()
            event.accepted = true
          } else if (themeManager.themePickerActive && !root.wallpaperPickerActive && !root.iconsMode) {
            root.openWallpapersSwitcher()
            event.accepted = true
          }
        } else if (event.key === Qt.Key_B
                   && root.canUseLetterShortcut(event)
                   && root.browseForCurrentMode()) {
          event.accepted = true
        } else if (event.key === Qt.Key_M
                   && root.canUseLetterShortcut(event)
                   && root.localWallpaperMode) {
          wallpaperActionsDropdown.toggle()
          event.accepted = true
        } else if (event.key === Qt.Key_N
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.wallhavenMode) {
          wallhaven.loadMore()
          event.accepted = true
        } else if (event.key === Qt.Key_N
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.iconsBrowseMode) {
          iconBrowse.loadMore()
          event.accepted = true
        } else if (event.key === Qt.Key_F
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.wallhavenMode) {
          root.openWallhavenFilters()
          event.accepted = true
        } else if (event.key === Qt.Key_F
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.iconsBrowseMode) {
          root.openIconsBrowseFilters()
          event.accepted = true
        } else if (event.key === Qt.Key_F
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.catalogMode) {
          root.openCatalogFilters()
          event.accepted = true
        } else if (event.key === Qt.Key_D
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && (event.modifiers & Qt.ShiftModifier) !== 0
                   && root.localWallpaperMode) {
          root.toggleFavoritesOnly()
          event.accepted = true
        } else if (event.key === Qt.Key_D
                   && (event.modifiers & Qt.ControlModifier) !== 0
                   && root.localWallpaperMode) {
          root.toggleCurrentFavorite()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (root.filterText) {
            root.updateFilter("")
          } else if (root.wallhavenMode) {
            root.leaveWallhaven(true)
          } else if (root.iconsBrowseMode) {
            root.leaveIconsBrowse(true)
          } else if (root.iconsMode) {
            root.leaveIcons(true)
          } else if (root.catalogMode) {
            root.leaveCatalog(true)
          } else {
            root.cancel()
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.applySelected()
          event.accepted = true
        } else if ((root.wallhavenMode || root.iconsBrowseMode || root.iconsMode || root.catalogMode || root.filterable) && Util.editsFilter(event, root.filterText)) {
          root.updateFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (root.themeGridActive
                   && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
          themeCollections.moveGrid(0, event.key === Qt.Key_Down ? 1 : -1)
          event.accepted = true
        } else if (root.themeGridActive
                   && (event.key === Qt.Key_Left
                       || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)
                       || event.key === Qt.Key_Backtab)) {
          themeCollections.moveGrid(-1, 0)
          event.accepted = true
        } else if (root.themeGridActive
                   && (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)) {
          themeCollections.moveGrid(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
          root.selectAdjacent(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
          root.selectAdjacent(1)
          event.accepted = true
        } else if ((root.wallhavenMode || root.iconsBrowseMode || root.iconsMode || root.catalogMode || root.filterable)
                   && event.text
                   && event.text.length === 1
                   && event.text.charCodeAt(0) >= 32
                   && event.text.charCodeAt(0) !== 127
                   && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.updateFilter(root.filterText + event.text)
          event.accepted = true
        }
      }
    }

    Item {
      id: card
      visible: root.opened && root.imagesLoaded && root.layoutSettled && root.imageArray.length > 0
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      Rectangle {
        visible: root.livePaletteReady
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: -root.expandedWidth * 0.2
        width: root.expandedWidth * 0.82
        height: root.expandedHeight * 0.82
        radius: width / 2
        color: Util.alpha(root.livePaletteAccent, 0.28)
        opacity: 0.74
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1
          blurMax: 96
          autoPaddingEnabled: true
        }
      }

      Rectangle {
        visible: root.livePaletteReady
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.expandedWidth * 0.24
        anchors.verticalCenterOffset: root.expandedHeight * 0.12
        width: root.expandedWidth * 0.7
        height: root.expandedHeight * 0.7
        radius: width / 2
        color: Util.alpha(root.livePaletteSecondary, 0.24)
        opacity: 0.68
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1
          blurMax: 96
          autoPaddingEnabled: true
        }
      }

      Item {
        id: carousel
        anchors.top: parent.top
        anchors.topMargin: Style.space(30)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomChromeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        clip: root.themeGridActive

        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2
        // This Item is wider than the card so carousel slices can run off both
        // edges, which puts its origin left of the card whenever the card
        // clamps to a narrower screen. The grid is centred on the card, so it
        // starts from the middle of that overhang, and it sits in the middle
        // vertically whenever it is shorter than the viewport.
        // The grid scrolls past the viewport, so it takes the wheel; the
        // carousel is a ring and does not.
        WheelHandler {
          enabled: root.themeGridActive
          onWheel: function(event) { themeCollections.scrollGrid(event.angleDelta.y) }
        }

        readonly property real gridOriginX: (width - themeCollections.gridWidth) / 2
        readonly property real gridOriginY: Math.max(
          0,
          (themeCollections.geometry.viewportHeight - themeCollections.gridModel.height) / 2)

        // Section titles for the rows the grid window shows (at most four).
        Repeater {
          model: root.themeGridActive ? themeCollections.gridHeaders : []

          delegate: Item {
            required property var modelData
            x: carousel.gridOriginX + themeCollections.geometry.offsetX
            y: carousel.gridOriginY + modelData.y
            width: themeCollections.geometry.contentWidth
            height: themeCollections.geometry.headerHeight

            Text {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              text: String(modelData.text || "")
              color: modelData.sectionId === themeCollections.selectedCollectionId
                ? root.livePaletteAccent
                : root.foreground
              style: Text.Outline
              styleColor: root.chromeOutline
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              textFormat: Text.PlainText
            }

            Text {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              text: String(modelData.count || 0)
              color: root.foreground
              opacity: 0.7
              style: Text.Outline
              styleColor: root.chromeOutline
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }
          }
        }

        Repeater {
          id: carouselRepeater

          // Keep GPU-heavy masked delegates strictly bounded. Each slot tracks a
          // stable virtual carousel position, so navigation recycles only the
          // item crossing the far edge instead of instantiating every result.
          model: root.carouselPoolSize

          delegate: Item {
            id: item
            required property int index

            readonly property var relativeValue: ImagePickerModel.carouselRelativeForSlot(
              index,
              root.carouselCursor,
              root.matchingIndices.length,
              root.carouselPoolSize)
            readonly property int relativeIndex: relativeValue === null ? 0 : relativeValue
            readonly property int matchPosition: ImagePickerModel.carouselPositionForSlot(
              index,
              root.carouselCursor,
              root.matchingIndices.length,
              root.carouselPoolSize)
            // Grid mode reuses this pool: each slot shows one visible grid cell.
            readonly property var gridCell: root.themeGridActive ? themeCollections.gridCell(index) : null
            readonly property int imageIndex: root.themeGridActive
              ? (gridCell ? gridCell.imageIndex : -1)
              : (matchPosition >= 0 && matchPosition < root.matchingIndices.length
                  ? root.matchingIndices[matchPosition]
                  : -1)
            readonly property var imageData: root.imageModelEpoch >= 0
              && imageIndex >= 0
              && imageIndex < root.imageArray.length
              ? root.imageArray[imageIndex]
              : null
            readonly property string filePath: imageData ? imageData.filePath : ""
            readonly property string fileName: imageData ? imageData.fileName : ""
            readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""

            readonly property bool matched: imageIndex >= 0
            readonly property bool selected: root.themeGridActive
              ? (gridCell !== null && gridCell.position === themeCollections.gridCursor)
              : (matched && imageIndex === root.selectedIndex)
            // Keep one recycled slot hidden beyond each edge so its source/x
            // jump can never sweep across the visible carousel.
            readonly property bool nearby: root.themeGridActive
              ? matched
              : (matched && Math.abs(relativeIndex) <= 7)
            property bool sourceActivated: nearby
            onNearbyChanged: if (nearby) sourceActivated = true
            onFilePathChanged: {
              // Drop sticky activation when this index now points at a new file
              // so Image.source rebinds instead of keeping a deleted pixmap.
              sourceActivated = false
              if (nearby) sourceActivated = true
            }

            visible: nearby
            x: root.themeGridActive
              ? (gridCell ? carousel.gridOriginX + gridCell.x : 0)
              : (selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep))
            width: root.themeGridActive
              ? (gridCell ? gridCell.width : 0)
              : (selected ? root.expandedWidth : root.sliceWidth)
            height: root.themeGridActive
              ? (gridCell ? gridCell.height : 0)
              : (selected ? root.expandedHeight : root.sliceHeight)
            y: root.themeGridActive
              ? (gridCell ? carousel.gridOriginY + gridCell.y : 0)
              : (selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2)
            z: root.themeGridActive
              ? (selected ? 100 : 50)
              : (selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40))

            Behavior on x {
              enabled: root.opened && root.layoutSettled && !root.themeGridActive
              NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
            Behavior on y {
              enabled: root.opened && root.layoutSettled && !root.themeGridActive
              NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on width {
              enabled: root.opened && root.layoutSettled && !root.themeGridActive
              NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
            Behavior on height {
              enabled: root.opened && root.layoutSettled && !root.themeGridActive
              NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }

            readonly property real skAbs: root.themeGridActive ? 0 : Math.abs(root.skewOffset)
            readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
            readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
            readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
            readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(root.dimColor, 0.88)
              }

              Image {
                id: image
                anchors.fill: parent
                // The plugin owns local wallpaper thumbnails. Theme catalog and
                // Pling preview URLs have already passed model allowlists.
                visible: !root.iconsMode || root.iconsBrowseMode
                source: item.sourceActivated && item.thumbnailPath && (!root.iconsMode || root.iconsBrowseMode)
                  ? (root.catalogMode || root.iconsBrowseMode
                      ? item.thumbnailPath
                      : Util.fileUrl(item.thumbnailPath))
                  : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: root.wallhavenMode || root.catalogMode || root.iconsBrowseMode
                cache: root.wallhavenMode || root.catalogMode || root.iconsBrowseMode
                smooth: true
              }

              Item {
                id: iconPreviewPanel
                anchors.fill: parent
                visible: root.iconsMode && !root.iconsBrowseMode

                Rectangle {
                  anchors.fill: parent
                  color: root.readableBackdrop(root.livePaletteBase, item.selected ? 0.82 : 0.9)
                }

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(item.selected ? 18 : 10)
                  width: parent.width - Style.space(item.selected ? 48 : 20)

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(item.selected ? 18 : 8)

                    Repeater {
                      model: [
                        item.imageData && item.imageData.previewFolder,
                        item.imageData && item.imageData.previewApp,
                        item.imageData && item.imageData.previewMime
                      ].filter(function(path) { return !!path })

                      Image {
                        required property var modelData
                        width: item.selected ? 72 : 28
                        height: width
                        source: item.sourceActivated && modelData ? Util.fileUrl(modelData) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                      }
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    visible: item.selected
                    text: String((item.imageData && item.imageData.displayName) || item.fileName || "")
                    color: root.foreground
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: Style.font.title
                    font.weight: Font.DemiBold
                    textFormat: Text.PlainText
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: item.selected
                      && item.imageData
                      && (item.imageData.current || item.imageData.iconTheme === root.currentIconTheme)
                    text: "ACTIVE"
                    color: root.livePaletteAccent
                    font.pixelSize: Style.font.caption
                    font.weight: Font.Bold
                    textFormat: Text.PlainText
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: item.selected
                  && (root.wallhavenMode || root.catalogMode)
                  && (!item.thumbnailPath || image.status === Image.Error)
                text: "Preview unavailable"
                color: root.foreground
                font.pixelSize: Style.font.title
                textFormat: Text.PlainText
              }

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(root.dimColor, item.selected ? 0 : (root.themeGridActive ? 0.18 : 0.42))
              }

              Text {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(12)
                visible: (root.localWallpaperMode
                  && WallpaperCommandModel.isFavorite(
                    root.favoriteIds,
                    item.filePath,
                    root.wallpaperFavoriteContext()))
                  || (root.themeCollectionsActive && themeCollections.isFavoriteImage(item.imageData))
                text: "★"
                color: root.livePaletteAccent
                style: Text.Outline
                styleColor: root.chromeOutline
                font.pixelSize: item.selected ? Style.font.display : Style.font.title
                font.weight: Font.Bold
                opacity: item.selected ? 1.0 : 0.86
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
              }

              Rectangle {
                visible: root.themeGridActive
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: gridCaption.implicitHeight + Style.space(10)
                color: root.chromeFill

                Text {
                  id: gridCaption
                  anchors.centerIn: parent
                  width: parent.width - Style.space(16)
                  text: root.labelForPath(item.filePath)
                  color: root.foreground
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  font.pixelSize: Style.font.body
                  font.weight: item.selected ? Font.DemiBold : Font.Normal
                  textFormat: Text.PlainText
                }
              }

              // The applied theme, as distinct from the highlighted card.
              Rectangle {
                visible: root.themeCollectionsActive && themeCollections.isCurrentImage(item.imageData)
                x: Style.space(item.selected && !root.themeGridActive ? 14 : 8)
                y: root.themeGridActive
                  ? Style.space(8)
                  : parent.height - height - Style.space(item.selected ? 14 : 12)
                width: activeBadge.implicitWidth + Style.space(12)
                height: activeBadge.implicitHeight + Style.space(6)
                radius: height / 2
                color: root.readableBackdrop(root.livePaletteBase)
                border.width: 1
                border.color: Util.alpha(root.livePaletteAccent, 0.85)

                Text {
                  id: activeBadge
                  anchors.centerIn: parent
                  text: "ACTIVE"
                  color: root.livePaletteAccent
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  textFormat: Text.PlainText
                }
              }

              Rectangle {
                visible: item.selected && root.livePaletteReady
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(14)
                width: paletteBadgeRow.implicitWidth + Style.space(18)
                height: paletteBadgeRow.implicitHeight + Style.space(12)
                radius: height / 2
                color: root.readableBackdrop(root.livePaletteBase)
                border.width: 1
                border.color: Util.alpha(root.livePaletteAccent, 0.8)

                Row {
                  id: paletteBadgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Repeater {
                    model: [root.livePaletteAccent, root.livePaletteSecondary, root.livePaletteBase]
                    Rectangle {
                      required property color modelData
                      width: Style.space(9)
                      height: width
                      radius: width / 2
                      color: modelData
                      border.width: 1
                      border.color: Util.alpha(root.foreground, 0.42)
                    }
                  }

                  Text {
                    text: "LIVE PALETTE"
                    color: root.foreground
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                    textFormat: Text.PlainText
                  }
                }
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? root.activeSelectedBorder : root.unselectedBorder
                strokeWidth: item.selected ? 3 : 1
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (item.selected) root.applySelected()
                else if (root.themeGridActive) {
                  if (item.gridCell) themeCollections.selectGridPosition(item.gridCell.position)
                } else {
                  root.select(item.imageIndex, false, root.carouselCursor + item.relativeIndex)
                  root.focusPicker()
                }
              }
            }
          }
        }
      }

      Item {
        id: footer
        visible: root.showLabels || root.wallpaperPickerActive || root.iconsMode || root.iconsBrowseMode
        anchors.top: carousel.bottom
        anchors.topMargin: Style.space(16)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        height: Math.max(
          selectedLabel.implicitHeight,
          wallpaperActionsDropdown.implicitHeight,
          defaultsControls.implicitHeight,
          wallhavenBrowseButton.implicitHeight,
          wallhavenBackButton.implicitHeight,
          iconsBrowseButton.implicitHeight,
          iconsBackButton.implicitHeight,
          iconsBrowseOcsButton.implicitHeight,
          iconsBrowseBackButton.implicitHeight,
          iconsBrowseInstallButton.implicitHeight,
          iconsBrowseLoadMoreButton.implicitHeight,
          loadMoreButton.implicitHeight,
          themeBrowseButton.implicitHeight,
          catalogBackButton.implicitHeight,
          uninstallButton.implicitHeight,
          catalogReviewButton.implicitHeight,
          wallpapersCrossNavButton.implicitHeight,
          themesCrossNavButton.implicitHeight,
          themeGridButton.implicitHeight
        )
        readonly property real leftReserved: {
          let width = 0
          if (wallpaperActionsDropdown.visible) width += wallpaperActionsDropdown.implicitWidth
          if (themesCrossNavButton.visible) {
            if (width > 0) width += Style.space(8)
            width += themesCrossNavButton.implicitWidth
          }
          if (wallpapersCrossNavButton.visible)
            width = Math.max(width, wallpapersCrossNavButton.implicitWidth)
          if (themeGridButton.visible) {
            if (width > 0) width += Style.space(8)
            width += themeGridButton.implicitWidth
          }
          if (catalogBackButton.visible)
            width = Math.max(width, catalogBackButton.implicitWidth)
          if (wallhavenBackButton.visible)
            width = Math.max(width, wallhavenBackButton.implicitWidth)
          if (iconsBackButton.visible)
            width = Math.max(width, iconsBackButton.implicitWidth)
          if (iconsBrowseBackButton.visible)
            width = Math.max(width, iconsBrowseBackButton.implicitWidth)
          return width
        }
        readonly property real rightReserved: {
          let width = 0
          // Browse* then Icons then Uninstall — right-aligned cluster.
          if (themeBrowseButton.visible) width += themeBrowseButton.implicitWidth
          if (wallhavenBrowseButton.visible) {
            if (width > 0) width += Style.space(8)
            width += wallhavenBrowseButton.implicitWidth
          }
          if (iconsBrowseButton.visible) {
            if (width > 0) width += Style.space(8)
            width += iconsBrowseButton.implicitWidth
          }
          if (uninstallButton.visible) {
            if (width > 0) width += Style.space(8)
            width += uninstallButton.implicitWidth
          }
          // Icons mode: Icon defaults then Browse icons (Browse on the far right).
          if (defaultsControls.visible) {
            if (width > 0) width += Style.space(8)
            width += defaultsControls.implicitWidth
          }
          if (iconsBrowseOcsButton.visible) {
            if (width > 0) width += Style.space(8)
            width += iconsBrowseOcsButton.implicitWidth
          }
          if (loadMoreButton.visible)
            width = Math.max(width, loadMoreButton.implicitWidth)
          if (iconsBrowseLoadMoreButton.visible)
            width = Math.max(width, iconsBrowseLoadMoreButton.implicitWidth)
          if (iconsBrowseInstallButton.visible) {
            if (width > 0) width += Style.space(8)
            width += iconsBrowseInstallButton.implicitWidth
          }
          if (catalogReviewButton.visible)
            width = Math.max(width, catalogReviewButton.implicitWidth)
          return width
        }

        // Compact Actions menu: hamburger + chevron trigger, custom popup
        // (system Dropdown clipped bottom padding / double-bordered against trigger).
        Item {
          id: wallpaperActionsDropdown
          visible: root.localWallpaperMode
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: Style.space(52)
          implicitHeight: Style.spacing.controlHeight
          width: implicitWidth
          height: implicitHeight

          readonly property bool popupOpen: actionsPopup.opened
          readonly property color menuForeground: root.foreground
          readonly property color menuAccent: root.livePaletteAccent
          readonly property color menuBackground: root.readableBackdrop(root.dimColor, 0.96)
          readonly property var menuBorderSpec: Border.localOrSurfaceSpec(
            "popups", "border", Util.alpha(root.foreground, 0.28), Color.popups.border, Style.normalBorderWidth)

          function open() { actionsPopup.open() }
          function close() { actionsPopup.close() }
          function toggle() { popupOpen ? close() : open() }

          BorderSurface {
            id: actionsTrigger
            anchors.fill: parent
            radius: Style.cornerRadius
            readonly property bool _focused: activeFocus
            readonly property bool _hot: actionsTriggerHover.hovered || actionsPopup.opened
            readonly property var _borderSpec: Border.controlSpec(
              _focused ? "focus" : (_hot ? "hover-cursor" : "normal"),
              wallpaperActionsDropdown.menuForeground,
              wallpaperActionsDropdown.menuAccent)
            // At rest Style.controlFill is a 4%-alpha wash, which over a bright
            // window reads as a hole rather than a control.
            color: _focused || _hot
              ? Style.controlFill(_focused, _hot, wallpaperActionsDropdown.menuForeground, wallpaperActionsDropdown.menuAccent)
              : root.chromeFill
            borderSpec: _borderSpec
            activeFocusOnTab: true

            HoverHandler { id: actionsTriggerHover }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                  || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
                wallpaperActionsDropdown.toggle()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape && actionsPopup.opened) {
                wallpaperActionsDropdown.close()
                event.accepted = true
              }
            }

            Row {
              anchors.centerIn: parent
              spacing: Style.spacing.xs

              Text {
                text: "☰"
                color: wallpaperActionsDropdown.menuForeground
                font.family: Style.font.family
                // Slightly larger than body so the hamburger reads as the primary glyph.
                font.pixelSize: Style.font.icon
                textFormat: Text.PlainText
              }

              Text {
                text: "󰅀"
                color: Qt.darker(wallpaperActionsDropdown.menuForeground, 1.2)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                textFormat: Text.PlainText
                transformOrigin: Item.Center
                rotation: wallpaperActionsDropdown.popupOpen ? 180 : 0
                Behavior on rotation {
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                actionsTrigger.forceActiveFocus()
                wallpaperActionsDropdown.toggle()
              }
            }

            PanelToolTip {
              visible: actionsTriggerHover.hovered && !actionsPopup.opened
              text: "Actions (M)"
              delay: 500
            }
          }

          Popup {
            id: actionsPopup
            // Clear gap under the trigger so borders do not double-stack.
            x: 0
            y: actionsTrigger.height + Style.spacing.sm
            width: Math.max(wallpaperActionsDropdown.width, Style.space(188))
            padding: 0
            leftPadding: Border.left(wallpaperActionsDropdown.menuBorderSpec) + Style.spacing.sm
            rightPadding: Border.right(wallpaperActionsDropdown.menuBorderSpec) + Style.spacing.sm
            topPadding: Border.top(wallpaperActionsDropdown.menuBorderSpec) + Style.spacing.sm
            bottomPadding: Border.bottom(wallpaperActionsDropdown.menuBorderSpec) + Style.spacing.sm
            focus: true
            closePolicy: Popup.CloseOnEscape

            background: BorderSurface {
              color: wallpaperActionsDropdown.menuBackground
              borderSpec: wallpaperActionsDropdown.menuBorderSpec
              radius: Style.cornerRadius
            }

            onOpened: {
              actionsList.currentIndex = 0
              actionsList.forceActiveFocus()
            }

            // Size the popup from row count so padding is never clipped.
            implicitHeight: {
              var n = root.wallpaperActionOptions.length
              var rows = Math.max(1, n) * Style.spacing.popupRowHeight
              var gaps = Math.max(0, n - 1) * Style.spacing.xs
              return rows + gaps + topPadding + bottomPadding
            }

            contentItem: ListView {
              id: actionsList
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              spacing: Style.spacing.xs
              width: actionsPopup.availableWidth
              implicitHeight: contentHeight
              model: root.wallpaperActionOptions
              currentIndex: 0
              keyNavigationWraps: false
              highlightFollowsCurrentItem: false

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  wallpaperActionsDropdown.close()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down || event.text === "j") {
                  currentIndex = Math.min(count - 1, currentIndex + 1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || event.text === "k") {
                  currentIndex = Math.max(0, currentIndex - 1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  selectCurrent()
                  event.accepted = true
                }
              }

              function selectCurrent() {
                if (currentIndex < 0 || currentIndex >= root.wallpaperActionOptions.length) return
                var item = root.wallpaperActionOptions[currentIndex]
                var value = item && typeof item === "object" ? String(item.value || "") : String(item || "")
                wallpaperActionsDropdown.close()
                root.runWallpaperAction(value)
              }

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: actionsList.width
                height: Style.spacing.popupRowHeight
                radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
                color: index === actionsList.currentIndex
                  ? Style.hoverFillFor(wallpaperActionsDropdown.menuForeground, wallpaperActionsDropdown.menuAccent)
                  : "transparent"

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  verticalAlignment: Text.AlignVCenter
                  text: modelData && typeof modelData === "object"
                    ? String(modelData.label || "")
                    : String(modelData || "")
                  color: index === actionsList.currentIndex
                    ? Style.hoverStateColor(wallpaperActionsDropdown.menuForeground, wallpaperActionsDropdown.menuAccent)
                    : wallpaperActionsDropdown.menuForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: actionsList.currentIndex = parent.index
                  onClicked: {
                    actionsList.currentIndex = parent.index
                    actionsList.selectCurrent()
                  }
                }
              }
            }
          }
        }

        Row {
          id: defaultsControls
          visible: root.localIconsMode && !!root.currentThemeName
          // Sit left of Browse icons so Browse keeps the far-right slot
          // (same chrome pattern as Themes / Wallpapers Browse buttons).
          anchors.right: iconsBrowseOcsButton.visible ? iconsBrowseOcsButton.left : parent.right
          anchors.rightMargin: iconsBrowseOcsButton.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            anchors.verticalCenter: parent.verticalCenter
            enabled: root.hasIconsMemory || !!root.currentIconTheme
            text: "Icon defaults"
            tooltipText: "Clear remembered icons and restore this theme package default"
            foreground: root.foreground
            accent: root.livePaletteAccent
            bordered: true
            background: root.chromeFill
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(7)
            onClicked: root.resetIconDefaults()
          }
        }

        Text {
          id: selectedLabel
          visible: root.showLabels || root.wallhavenMode || root.wallpaperPickerActive || root.iconsMode || root.iconsBrowseMode
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: footer.leftReserved > 0 ? footer.leftReserved + Style.space(16) : 0
          anchors.rightMargin: footer.rightReserved > 0 ? footer.rightReserved + Style.space(16) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.currentLabel()
          color: root.foreground
          style: Text.Outline
          styleColor: root.chromeOutline
          font.pixelSize: (root.wallhavenMode || root.iconsBrowseMode) ? Style.font.title : Style.font.display
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
        }

        Button {
          id: wallhavenBrowseButton
          visible: root.wallpaperPickerActive && !root.wallhavenMode && !root.iconsMode && !root.iconsBrowseMode
          anchors.verticalCenter: parent.verticalCenter
          x: {
            let offset = 0
            if (iconsBrowseButton.visible) offset += iconsBrowseButton.width + Style.space(8)
            if (uninstallButton.visible) offset += uninstallButton.width + Style.space(8)
            return parent.width - width - offset
          }
          text: "Browse wallpapers"
          tooltipText: "Browse free, openly licensed wallpapers (B / Ctrl+B)"
          foreground: root.foreground
          accent: root.livePaletteAccent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.openWallhaven()
        }

        Rectangle {
          id: iconsBrowseButton
          visible: root.canOpenIconsMode
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: uninstallButton.visible ? uninstallButton.left : parent.right
          anchors.rightMargin: uninstallButton.visible ? Style.space(8) : 0
          implicitWidth: iconsBrowseContent.implicitWidth + Style.space(14)
          implicitHeight: Math.max(Style.space(34), iconsBrowseContent.implicitHeight + Style.space(12))
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
          color: root.readableBackdrop(root.livePaletteBase, iconsBrowseMouse.containsMouse ? 0.9 : 0.94)
          border.width: 1
          border.color: iconsBrowseMouse.containsMouse
            ? Util.alpha(root.livePaletteAccent, 0.9)
            : Util.alpha(root.foreground, 0.38)

          Row {
            id: iconsBrowseContent
            anchors.centerIn: parent
            spacing: Style.space(8)

            // Live folder/app/mime previews only — theme name lives in the tooltip.
            Row {
              visible: root.footerIconHasPreviews
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Repeater {
                model: [root.footerIconFolder, root.footerIconApp, root.footerIconMime].filter(function(path) {
                  return !!path
                })

                Image {
                  required property var modelData
                  width: Style.space(18)
                  height: width
                  source: modelData ? Util.fileUrl(modelData) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: true
                  smooth: true
                }
              }
            }

            Text {
              // Fallback label only when inventory previews are not ready yet.
              visible: !root.footerIconHasPreviews
              anchors.verticalCenter: parent.verticalCenter
              text: "Icons"
              color: root.foreground
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              maximumLineCount: 1
              textFormat: Text.PlainText
            }
          }

          MouseArea {
            id: iconsBrowseMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openIcons()
          }

          PanelToolTip {
            visible: iconsBrowseMouse.containsMouse
            text: (root.footerIconLabel || "Icons") + " (Ctrl+I)"
            delay: 400
          }
        }

        Button {
          id: iconsBrowseOcsButton
          // Far-right Browse control in Icons mode — mirrors Browse themes /
          // Browse Wallhaven placement in the other section footers.
          visible: root.localIconsMode
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          z: 2
          text: iconBrowse.loading ? "Loading…" : "Browse icons"
          tooltipText: "Browse icon themes on gnome-look.org / Pling (B / Ctrl+B)"
          foreground: root.foreground
          accent: root.livePaletteAccent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.openIconsBrowse()
        }

        Button {
          id: iconsBrowseBackButton
          visible: root.iconsBrowseMode
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Back"
          tooltipText: "Return to installed icon themes (Escape)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.leaveIconsBrowse(true)
        }

        Button {
          id: iconsBrowseInstallButton
          visible: root.iconsBrowseMode
          enabled: !!root.currentItem() && !iconBrowse.downloading && !iconBrowse.loading
          anchors.right: iconsBrowseLoadMoreButton.visible ? iconsBrowseLoadMoreButton.left : parent.right
          anchors.rightMargin: iconsBrowseLoadMoreButton.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: iconBrowse.downloading ? "Installing…" : "Install"
          tooltipText: "Download and install this icon pack (Enter)"
          foreground: Color.accent
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.applySelected()
        }

        Button {
          id: iconsBrowseLoadMoreButton
          visible: root.iconsBrowseMode
          enabled: iconBrowse.hasMore && !iconBrowse.loading
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: iconBrowse.loading
            ? "Loading…"
            : (iconBrowse.hasMore ? "Load more" : "All loaded")
          tooltipText: iconBrowse.hasMore
            ? "Load more Pling icon themes (Ctrl+N)"
            : "All available results are loaded"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: {
            iconBrowse.loadMore()
            Qt.callLater(root.focusPicker)
          }
        }

        Button {
          id: iconsBackButton
          visible: root.localIconsMode
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Back"
          tooltipText: "Return from icon themes (Escape)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.leaveIcons(true)
        }

        Button {
          id: wallpapersCrossNavButton
          visible: !root.catalogMode
            && !root.wallhavenMode
            && !root.iconsMode
            && !root.iconsBrowseMode
            && !root.wallpaperPickerActive
            && themeManager.themePickerActive
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Wallpapers"
          tooltipText: "Open wallpaper picker (W / Ctrl+W)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.openWallpapersSwitcher()
        }

        Button {
          id: themeGridButton
          visible: root.themeCollectionsActive
          anchors.left: wallpapersCrossNavButton.visible ? wallpapersCrossNavButton.right : parent.left
          anchors.leftMargin: wallpapersCrossNavButton.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: themeCollections.gridMode ? "Carousel" : "Grid"
          tooltipText: themeCollections.gridMode
            ? "Back to the carousel (Ctrl+G)"
            : "Favorites and collections as a grid (Ctrl+G)  ·  Ctrl+D star  ·  Ctrl+M collections"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: themeCollections.toggleGrid()
        }

        Button {
          id: themesCrossNavButton
          visible: root.localWallpaperMode
          anchors.left: wallpaperActionsDropdown.visible ? wallpaperActionsDropdown.right : parent.left
          anchors.leftMargin: wallpaperActionsDropdown.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: "Themes"
          tooltipText: "Open theme picker (T / Ctrl+T)"
          foreground: root.foreground
          accent: root.livePaletteAccent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.openThemesSwitcher()
        }

        Button {
          id: themeBrowseButton
          visible: !root.catalogMode
            && !root.wallhavenMode
            && !root.iconsMode
            && !root.iconsBrowseMode
            && !root.wallpaperPickerActive
            && themeManager.themePickerActive
          enabled: themeManager.inventoryReady
            && !themeCatalog.loading
            && !themeManager.busy
          anchors.verticalCenter: parent.verticalCenter
          x: {
            let offset = 0
            if (uninstallButton.visible) offset += uninstallButton.width + Style.space(8)
            if (iconsBrowseButton.visible) offset += iconsBrowseButton.width + Style.space(8)
            return parent.width - width - offset
          }
          text: !themeManager.inventoryReady
            ? "Indexing…"
            : (themeCatalog.loading ? "Loading…" : "Browse themes")
          tooltipText: "Browse community themes from verified catalog metadata (B / Ctrl+B)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.openCatalog()
        }

        Button {
          id: catalogBackButton
          visible: root.catalogMode
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Back"
          tooltipText: "Return to installed themes (Escape)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.leaveCatalog(true)
        }

        Button {
          id: wallhavenBackButton
          visible: root.wallhavenMode
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Back"
          tooltipText: "Return to local wallpapers (Escape / W)"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.leaveWallhaven(true)
        }

        Button {
          id: loadMoreButton
          visible: root.wallhavenMode
          enabled: wallhaven.hasMore && !wallhaven.loading
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: wallhaven.loading
            ? "Loading…"
            : (wallhaven.hasMore ? "Load more" : "All loaded")
          tooltipText: wallhaven.hasMore
            ? "Load two more wallpaper pages (Ctrl+N)"
            : "All available results are loaded"
          foreground: root.foreground
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: {
            wallhaven.loadMore()
            Qt.callLater(root.focusPicker)
          }
        }

        Button {
          id: uninstallButton
          visible: !root.catalogMode
            && !root.wallhavenMode
            && !root.iconsMode
            && !root.iconsBrowseMode
            && themeManager.themePickerActive
            && themeManager.inventoryReady
            && themeManager.selectedThemeInstalled
          enabled: themeManager.canUninstallSelectedTheme
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: themeManager.selectedThemeIsCurrent
            ? "In use"
            : (themeManager.busy ? "Uninstalling…" : "Uninstall")
          tooltipText: themeManager.selectedThemeIsCurrent
            ? "Switch to another theme before uninstalling this one"
            : "Uninstall this user-installed theme (Delete)"
          foreground: themeManager.selectedThemeIsCurrent ? Color.muted : Color.urgent
          accent: Color.urgent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: themeManager.requestUninstall()
        }

        Button {
          id: catalogReviewButton
          visible: root.catalogMode
          enabled: themeCatalog.canActivateSelected
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: themeCatalog.selectedStatus
          tooltipText: {
            const item = themeCatalog.selectedEntry
            if (!item) return ""
            if (themeCatalog.canOpenSelectedSource)
              return "Open the repository; Install returns immediately afterward"
            if (item.installed) return "This theme is already installed"
            if (item.stockConflict) return "A built-in theme already uses this name"
            return "Install a sanitized exact snapshot (Enter)"
          }
          foreground: themeCatalog.canActivateSelected ? Color.accent : Color.muted
          accent: Color.accent
          bordered: true
          background: root.chromeFill
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: themeCatalog.requestPrimaryAction()
        }
      }

      Text {
        id: statusToastLabel
        visible: root.statusToast !== ""
        anchors.top: footer.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        text: root.statusToast
        color: root.livePaletteAccent
        style: Text.Outline
        styleColor: root.chromeOutline
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        textFormat: Text.PlainText
      }

      WallhavenFilterBar {
        id: wallhavenFilters
        visible: root.wallhavenMode
        anchors.top: footer.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        height: implicitHeight
        summary: root.wallhavenFilterSummary
        filtersActive: root.wallhavenFiltersActive
        activeCount: root.wallhavenFilterActiveCount
        foreground: root.foreground
        accent: Color.accent
        onOpenRequested: root.openWallhavenFilters()
      }

      Text {
        visible: root.wallhavenMode
        anchors.top: wallhavenFilters.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: {
          if (wallhaven.downloading) return "Downloading full wallpaper…"
          if (wallhaven.errorMessage) return wallhaven.errorMessage
          if (wallhaven.loading && root.imageArray.length > 0)
            return "Loading more wallpapers…  " + root.imageArray.length + " loaded"
          if (wallhaven.loading) return "Searching open wallpapers…"
          if (wallhaven.staleResults) return root.imageArray.length + " cached results  ·  Catalog is offline"
          if (root.filterText)
            return "Search: " + root.filterText + "  ·  " + root.imageArray.length + " loaded"
          return wallhaven.totalResults > 0
            ? root.imageArray.length + " of " + wallhaven.totalResults + " loaded  ·  Type to search"
            : "Type to search open wallpapers"
        }
        color: wallhaven.errorMessage ? Color.urgent : root.foreground
        opacity: 0.9
        style: Text.Outline
        styleColor: root.chromeOutline
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      IconBrowseFilterBar {
        id: iconsBrowseFiltersBar
        visible: root.iconsBrowseMode
        anchors.top: footer.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        height: implicitHeight
        summary: root.iconsBrowseFilterSummary
        filtersActive: root.iconsBrowseFiltersActive
        foreground: root.foreground
        accent: Color.accent
        onOpenRequested: root.openIconsBrowseFilters()
      }

      Text {
        visible: root.iconsBrowseMode
        anchors.top: iconsBrowseFiltersBar.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: {
          if (iconBrowse.downloading) return "Downloading icon pack from Pling…"
          if (iconBrowse.errorMessage) return iconBrowse.errorMessage
          if (iconBrowse.loading && root.imageArray.length > 0)
            return "Loading more…  " + root.imageArray.length + " loaded"
          if (iconBrowse.loading) return "Searching gnome-look.org icon themes…"
          if (root.filterText)
            return "Search: " + root.filterText + "  ·  " + root.imageArray.length + " loaded"
          return iconBrowse.totalResults > 0
            ? root.imageArray.length + " of " + iconBrowse.totalResults + " loaded  ·  Type to search"
            : "Type to search Pling icon themes"
        }
        color: iconBrowse.errorMessage ? Color.urgent : root.foreground
        opacity: 0.9
        style: Text.Outline
        styleColor: root.chromeOutline
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      ThemeCatalogFilterBar {
        id: catalogFiltersBar
        visible: root.catalogMode
        anchors.top: footer.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        height: implicitHeight
        summary: root.catalogFilterSummary
        filtersActive: root.catalogFiltersActive
        activeCount: root.catalogFilterActiveCount
        foreground: root.foreground
        accent: Color.accent
        onOpenRequested: root.openCatalogFilters()
      }

      Column {
        id: themeStatusColumn
        anchors.top: root.catalogMode ? catalogFiltersBar.bottom : footer.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        spacing: Style.space(4)

        Text {
          visible: !root.wallhavenMode && root.catalogMode
          width: parent.width
          text: root.currentCatalogMeta()
          color: root.foreground
          opacity: 0.75
          style: Text.Outline
          styleColor: root.chromeOutline
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          visible: root.themeCollectionsActive && !root.filterText && themeCollections.hint !== ""
          width: parent.width
          text: themeCollections.hint
          color: root.foreground
          opacity: 0.8
          style: Text.Outline
          styleColor: root.chromeOutline
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          visible: !root.wallhavenMode && root.filterable && root.filterText
          width: parent.width
          text: root.catalogMode
            ? ("Search: " + root.filterText + "  ·  " + root.imageArray.length + " shown"
                + (root.catalogFiltersActive ? "  ·  " + root.catalogFilterSummary : ""))
            : root.filterText
          color: root.catalogMode && root.catalogFiltersActive ? Color.accent : root.foreground
          opacity: 0.9
          style: Text.Outline
          styleColor: root.chromeOutline
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          visible: !root.wallhavenMode
            && (themeManager.errorMessage !== "" || themeCatalog.errorMessage !== "")
          width: parent.width
          text: themeCatalog.errorMessage || themeManager.errorMessage
          color: Color.urgent
          style: Text.Outline
          styleColor: root.chromeOutline
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      ConfirmDialog {
        id: catalogInstallConfirm
        anchors.fill: parent
        opened: themeCatalog.confirmationOpen
        z: 1000
        message: themeCatalog.confirmationMessage
        confirmText: "Install"
        background: root.dimColor
        foreground: root.foreground
        scrim: root.activeScrim
        selectedText: Color.accent
        onCanceled: themeCatalog.cancelInstall()
        onConfirmed: themeCatalog.confirmInstall()
      }

      ConfirmDialog {
        id: uninstallConfirm
        anchors.fill: parent
        opened: themeManager.confirmationOpen
        z: 1000
        message: "Uninstall " + ThemeManagerModel.labelForThemeName(themeManager.pendingTheme) + "?"
        confirmText: "Uninstall"
        background: root.dimColor
        foreground: root.foreground
        scrim: root.activeScrim
        selectedText: Color.accent
        onCanceled: themeManager.cancelUninstall()
        onConfirmed: themeManager.confirmUninstall()
      }

      ConfirmDialog {
        id: iconInstallConfirm
        anchors.fill: parent
        opened: iconBrowse.confirmationOpen
        z: 1000
        message: iconBrowse.confirmationMessage
        confirmText: "Install"
        background: root.dimColor
        foreground: root.foreground
        scrim: root.activeScrim
        selectedText: Color.accent
        onCanceled: iconBrowse.cancelInstall()
        onConfirmed: iconBrowse.confirmInstall()
      }
    }

    Item {
      visible: root.opened
        && root.imagesLoaded
        && root.layoutSettled
        && root.iconsBrowseMode
        && root.imageArray.length === 0
      width: root.expandedWidth
      height: 300
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      Text {
        id: iconsBrowseEmptyTitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        text: {
          if (iconBrowse.errorMessage) return iconBrowse.errorMessage
          if (iconBrowse.loading) return "Searching gnome-look.org icon themes…"
          return root.filterText
            ? "No icon themes found for “" + root.filterText + "”"
            : "No icon themes found"
        }
        color: iconBrowse.errorMessage ? Color.urgent : root.foreground
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
      }

      Text {
        anchors.top: iconsBrowseEmptyTitle.bottom
        anchors.topMargin: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Type to search  ·  Escape to return to installed icons"
        color: root.foreground
        opacity: 0.75
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }

    Item {
      visible: root.opened
        && root.imagesLoaded
        && root.layoutSettled
      && root.wallhavenMode
      && root.imageArray.length === 0
      width: root.expandedWidth
      height: 300
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      Text {
        id: emptyStateTitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        text: {
          if (wallhaven.errorMessage) return wallhaven.errorMessage
          if (wallhaven.loading) return "Searching open wallpapers…"
          return root.filterText
            ? "No open wallpapers found for “" + root.filterText + "”"
            : "No open wallpapers found"
        }
        color: wallhaven.errorMessage ? Color.urgent : root.foreground
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
      }

      Text {
        id: emptyStateHint
        anchors.top: emptyStateTitle.bottom
        anchors.topMargin: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.wallhavenFiltersActive
          ? ("Active filters may hide matches  ·  " + root.wallhavenFilterSummary)
          : "Type to search  ·  Escape to return to local wallpapers"
        color: root.wallhavenFiltersActive ? Color.accent : root.foreground
        opacity: 0.85
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      WallhavenFilterBar {
        id: emptyStateFilters
        anchors.top: emptyStateHint.bottom
        anchors.topMargin: Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        height: implicitHeight
        summary: root.wallhavenFilterSummary
        filtersActive: root.wallhavenFiltersActive
        activeCount: root.wallhavenFilterActiveCount
        foreground: root.foreground
        accent: Color.accent
        onOpenRequested: root.openWallhavenFilters()
      }

      Button {
        visible: !!wallhaven.errorMessage && !wallhaven.loading
        anchors.top: emptyStateFilters.bottom
        anchors.topMargin: Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Retry"
        foreground: root.foreground
        accent: Color.accent
        bordered: true
        background: root.chromeFill
        horizontalPadding: Style.space(12)
        verticalPadding: Style.space(7)
        onClicked: root.searchWallhaven()
      }
    }

    WallhavenFilterSheet {
      id: filterSheet

      anchors.fill: parent
      background: root.dimColor
      foreground: root.foreground
      scrim: root.readableBackdrop(root.dimColor, 0.92)
      accent: Color.accent
      onCanceled: Qt.callLater(root.focusPicker)
      onApplied: function(filters) { root.applyWallhavenFilters(filters) }
    }

    ThemeCatalogFilterSheet {
      id: catalogFilterSheet

      anchors.fill: parent
      background: root.dimColor
      foreground: root.foreground
      scrim: root.readableBackdrop(root.dimColor, 0.92)
      accent: Color.accent
      onCanceled: Qt.callLater(root.focusPicker)
      onApplied: function(filters) { root.applyThemeCatalogFilters(filters) }
    }

    IconBrowseFilterSheet {
      id: iconBrowseFilterSheet

      anchors.fill: parent
      background: root.dimColor
      foreground: root.foreground
      scrim: root.readableBackdrop(root.dimColor, 0.92)
      accent: Color.accent
      onCanceled: Qt.callLater(root.focusPicker)
      onApplied: function(filters) { root.applyIconsBrowseFilters(filters) }
    }

    ThemeCollectionsSheet {
      id: collectionsSheet

      anchors.fill: parent
      background: root.dimColor
      foreground: root.foreground
      scrim: root.readableBackdrop(root.dimColor, 0.92)
      accent: Color.accent
      collectionsState: themeCollections.collectionsState
      onCanceled: Qt.callLater(root.focusPicker)
      onMembershipsApplied: function(themeId, rows) {
        themeCollections.applyMemberships(themeId, rows)
      }
      onCreated: function(name) {
        const error = themeCollections.createCollection(name)
        if (error) root.showStatus(error)
      }
      onRenamed: function(name) {
        const error = themeCollections.renameSelectedCollection(name)
        if (error) root.showStatus(error)
      }
      onDeleteConfirmed: themeCollections.deleteSelectedCollection()
    }
  }
}
