const test = require("node:test")
const assert = require("node:assert/strict")
const { readFile } = require("node:fs/promises")
const { dirname, join } = require("node:path")
const process = require("node:process")

const read = (path) => readFile(join(process.cwd(), path), "utf8")

test("keeps the published Theme Manager identity as the sole picker clone", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  assert.equal(manifest.id, "io.github.mtolhuys.theme-manager")
  assert.equal(manifest.version, "0.8.0")
  assert.deepEqual(manifest.kinds, ["overlay"])
  assert.match(manifest.entryPoints.overlay, /^v[0-9]{4}\/ImagePicker\.qml$/)
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.image-picker")
  assert.equal(manifest.keepLoaded, true)
})

test("releases image-selector clients independently of QML loader teardown", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)

  // The done mark is written from this process, synchronously, so a rescan
  // that destroys the object right after close() cannot lose it; no child
  // process is involved (Run ends its group on destruction).
  assert.match(picker, /function finishDoneFile\(path\) \{[\s\S]*?writeSmallFile\(path, ""\)/)
  assert.match(picker, /id: smallFileWriter\n\s*blockWrites: true/)
  assert.doesNotMatch(picker, /execDetached|doneFilesToRelease|releaseNextDoneFile|id: releaseProc/)
})

test("versions the complete QML and JavaScript runtime graph", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(manifest.entryPoints.overlay)

  assert.match(
    picker,
    new RegExp('readonly property string buildIdentity: "' + manifest.version + '"')
  )
  assert.match(picker, /function runtimeIdentity\(\)/)

  for (const file of [
    "ImagePickerModel.js",
    "ThemeManagerController.qml",
    "ThemeManagerModel.js",
    "ThemeCatalogController.qml",
    "ThemeCatalogModel.js",
    "WallpaperBrowserController.qml",
    "WallpaperBrowserModel.js",
    "WallpaperCommandModel.js",
    "WallpaperPalette.qml",
    "WallpaperPaletteModel.js",
    "PluginState.qml",
    "WallhavenFilterBar.qml",
    "WallhavenFilterSheet.qml",
    "ThemeCatalogFilterBar.qml",
    "ThemeCatalogFilterSheet.qml",
    "ThemeMemoryModel.js",
    "IconThemeModel.js",
    "IconBrowseController.qml",
    "IconBrowseModel.js",
    "IconBrowseFilterBar.qml",
    "IconBrowseFilterSheet.qml",
    "ThemeCollectionsController.qml",
    "ThemeCollectionsModel.js",
    "ThemeCollectionsSheet.qml"
  ]) {
    assert.ok((await read(join(runtimeDir, file))).length > 0, file)
  }
})

test("bounds carousel rendering and defers wallpaper palette work while navigating", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const palette = await read(join(runtimeDir, "WallpaperPalette.qml"))

  assert.match(picker, /readonly property int carouselPoolSize: 17/)
  assert.match(picker, /model: root\.carouselPoolSize/)
  assert.doesNotMatch(picker, /model: root\.imageArray\.length/)
  assert.match(picker, /ImagePickerModel\.positionsForIndices/)
  assert.match(picker, /Math\.abs\(relativeIndex\) <= 7/)
  assert.match(palette, /readonly property int paletteCacheLimit: 24/)
  assert.match(palette, /root\.queueSample\(\)/)
  assert.doesNotMatch(palette, /Qt\.callLater\(root\.startSample\)/)
})

test("releases image-selector clients independently of QML loader teardown", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)

  // The done mark is written from this process, synchronously, so a rescan
  // that destroys the object right after close() cannot lose it; no child
  // process is involved (Run ends its group on destruction).
  assert.match(picker, /function finishDoneFile\(path\) \{[\s\S]*?writeSmallFile\(path, ""\)/)
  assert.match(picker, /id: smallFileWriter\n\s*blockWrites: true/)
  assert.doesNotMatch(picker, /execDetached|doneFilesToRelease|releaseNextDoneFile|id: releaseProc/)
})

test("resolves bundled helpers without private host manifest fields", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)

  assert.match(picker, /Qt\.resolvedUrl\("\.\.\/"\)/)
  assert.match(picker, /decodeURIComponent\(value\)/)
  assert.doesNotMatch(picker, /manifest\.__sourceDir/)

  for (const helper of [
    "catalog.sh",
    "icons-browse.sh",
    "icons-inventory.sh",
    "wallpaper-catalog.py",
    "install-theme.py",
    "install-wallpaper.sh",
    // The helpers that replaced the bash -c strings Run refuses.
    "install-hook.sh",
    "verify-wallpaper.sh",
    "apply-icons.sh",
    "reset-icons.sh",
    "probe-theme-lock.sh",
    "remove-wallpaper.sh",
    "reset-wallpaper.sh",
    "theme-inventory.sh",
    "hooks/theme-set.d/50-theme-manager-memory"
  ]) {
    const escaped = helper.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    assert.match(picker, new RegExp('pluginScriptPath\\("' + escaped + '"\\)'))
  }
})

test("routes theme and wallpaper features by request context", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const themeModel = await read(join(runtimeDir, "ThemeManagerModel.js"))
  const wallpaperModel = await read(join(runtimeDir, "WallpaperBrowserModel.js"))

  assert.match(themeModel, /themeNameForPath/)
  assert.match(wallpaperModel, /isWallpaperPickerRequest/)
  assert.match(picker, /wallpaperPickerRequest = WallpaperBrowserModel\.isWallpaperPickerRequest/)
  assert.match(picker, /themeManager\.themePickerActive/)
  assert.match(picker, /root\.openCatalog\(\)/)
  assert.match(picker, /root\.openCatalogFilters\(\)/)
  assert.match(picker, /ThemeCatalogFilterBar/)
  assert.match(picker, /root\.openWallhaven\(\)/)
  assert.match(picker, /if \(catalogMode\).*themeCatalog\.requestPrimaryAction/s)
  assert.match(picker, /if \(wallhavenMode\).*wallhaven\.download/s)

  const catalogController = await read(join(runtimeDir, "ThemeCatalogController.qml"))
  const catalogModel = await read(join(runtimeDir, "ThemeCatalogModel.js"))
  const catalogRuntime = [picker, catalogController, catalogModel].join("\n")
  assert.match(
    catalogController,
    /installProc\.command = \[installScriptPath, entry\.repositoryUrl\]/
  )
  assert.match(catalogController, /requestInstall/)
  assert.match(catalogController, /requestPrimaryAction/)
  assert.match(catalogController, /confirmInstall/)
  assert.match(catalogController, /temporaryFailureExitCode: 75/)
  assert.match(catalogController, /resourceLimitExitCode: 65/)
  assert.match(catalogController, /sourceFallbackRepository/)
  assert.match(catalogController, /GitHub rate limit reached/)
  assert.match(catalogController, /exceeds Theme Manager's safety limits/)
  assert.match(picker, /catalogAction: themeCatalog\.selectedStatus/)
  assert.match(picker, /catalogCanOpenSource: themeCatalog\.canOpenSelectedSource/)
  assert.match(picker, /pluginScriptPath\("install-theme\.py"\)/)
  assert.match(picker, /sourceOpener\.command = \["\/usr\/bin\/xdg-open", repositoryUrl\]/)
  assert.doesNotMatch(catalogRuntime, /execDetached\(\["xdg-open"|execArgv/)

  assert.match(picker, /ThemeMemoryModel/)
  assert.match(picker, /root\.openIcons\(\)/)
  assert.match(picker, /function openIcons\(\)/)
  assert.match(picker, /theme-manager-memory\.json/)
  assert.match(picker, /theme-catalog-filters\.json/)
  assert.match(picker, /wallpaper-browser-filters\.json/)
  assert.match(picker, /persistWallhavenFilters/)
  assert.match(picker, /catalogStickyQuery/)
  assert.match(picker, /refreshCatalogRows/)
  assert.doesNotMatch(picker, /io\.github\.mtolhuys\.wallpaper-manager/)
})

test("organises installed themes locally through the existing state writer", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const controller = await read(join(runtimeDir, "ThemeCollectionsController.qml"))
  const model = await read(join(runtimeDir, "ThemeCollectionsModel.js"))
  const sheet = await read(join(runtimeDir, "ThemeCollectionsSheet.qml"))

  // Same private state file as the sticky memory; no network, and the only
  // process is the one Store starts.
  assert.match(picker, /theme-collections\.json/)
  assert.match(
    controller,
    /PluginState \{\s+id: stateFile\s+pluginId: root\.pluginId\s+name: "theme-collections\.json"\s+legacyPath: root\.statePath/
  )
  assert.match(
    controller,
    /PluginState \{\s+id: backupFile[\s\S]*?name: ThemeCollectionsModel\.backupFileName/
  )
  assert.match(controller, /backupFile\.save\(ThemeCollectionsModel\.serializeBackup\(/)
  assert.doesNotMatch(controller, /Process \{|FileView|execDetached|execArgv|Quickshell\.env/)
  assert.doesNotMatch(model + sheet, /XMLHttpRequest|http/)

  // Grid view rides on the bounded carousel pool instead of a second Repeater.
  assert.match(picker, /themeCollections\.gridCell\(index\)/)
  assert.match(picker, /poolSize: root\.carouselPoolSize/)
  assert.equal((picker.match(/model: root\.carouselPoolSize/g) || []).length, 1)
  assert.match(picker, /model: root\.themeGridActive \? themeCollections\.gridHeaders : \[\]/)
  assert.match(model, /slots\[cell\.position % size\]/)

  // The grid is drawn inside the carousel, which is wider than the card and
  // starts left of it once the card clamps to a narrow screen. Cells and
  // section titles must both be placed from the card's centre, not that origin.
  assert.match(picker, /gridWidth: Math\.min\(carousel\.width, card\.width\)/)
  assert.match(
    picker,
    /readonly property real gridOriginX: \(width - themeCollections\.gridWidth\) \/ 2/
  )
  assert.match(picker, /readonly property real gridOriginY:/)
  assert.match(picker, /x: carousel\.gridOriginX \+ themeCollections\.geometry\.offsetX/)
  assert.match(picker, /width: themeCollections\.geometry\.contentWidth/)
  assert.match(picker, /gridCell \? carousel\.gridOriginX \+ gridCell\.x : 0/)
  assert.match(picker, /gridCell \? carousel\.gridOriginY \+ gridCell\.y : 0/)
  assert.doesNotMatch(picker, /width: carousel\.width - 2 \* themeCollections/)

  // A grid taller than the viewport has to take the wheel, and the wheel makes
  // scrollTop free, which is what the pool bound in the model has to survive.
  assert.match(picker, /WheelHandler \{\s+enabled: root\.themeGridActive/)
  assert.match(picker, /themeCollections\.scrollGrid\(event\.angleDelta\.y\)/)
  assert.match(controller, /ThemeCollectionsModel\.scrollBy\(/)
  assert.match(model, /const gridMinCellWidth = 254/)
  assert.match(model, /if \(filled >= size\) break/)

  // Search extends the existing installed-theme match to collection names.
  assert.match(controller, /ImagePickerModel\.textMatches/)
  assert.match(
    picker,
    /themeCollectionsActive \? themeCollections\.matchingIndices : textMatchingIndices/
  )

  // Bindings: Delete edits a collection only when one is selected.
  assert.match(
    picker,
    /if \(!themeCollections\.removeSelectedFromCollection\(\)\)\s+themeManager\.requestUninstall\(\)/
  )
  for (const key of ["Key_G", "Key_M", "Key_R"]) {
    assert.match(
      picker,
      new RegExp(
        "event\\.key === Qt\\." +
          key +
          "\\s+&& \\(event\\.modifiers & Qt\\.ControlModifier\\) !== 0\\s+&& root\\.themeCollectionsActive"
      )
    )
  }
  assert.match(
    picker,
    /Key_N\s+&& \(event\.modifiers & Qt\.ControlModifier\) !== 0\s+&& \(event\.modifiers & Qt\.ShiftModifier\) !== 0\s+&& root\.themeCollectionsActive/
  )
  assert.match(
    picker,
    /Key_D\s+&& \(event\.modifiers & Qt\.ControlModifier\) !== 0\s+&& \(event\.modifiers & Qt\.ShiftModifier\) !== 0\s+&& root\.themeCollectionsActive/
  )
  assert.match(picker, /ThemeCollectionsSheet \{/)
  assert.match(picker, /id: themeGridButton/)
  assert.match(picker, /text: "ACTIVE"/)

  // The chosen layout is remembered in the same file, not just the session.
  assert.match(model, /const viewValues = \{ carousel: true, grid: true \}/)
  assert.match(controller, /ThemeCollectionsModel\.isGridView\(collectionsState\)/)
  assert.match(controller, /ThemeCollectionsModel\.setView\(/)
})

test("keeps every picker backdrop above a readable contrast floor", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))

  // A theme's own image-picker.scrim-alpha may be as low as 0.5, which is
  // unreadable over a bright window. Nothing may paint text on the raw value.
  assert.match(picker, /readonly property real minBackdropAlpha: 0\.9/)
  assert.match(picker, /Math\.max\(surface\.a, floor\)/)
  assert.match(picker, /activeScrim: livePaletteReady\s+\? readableBackdrop\(/)
  assert.doesNotMatch(picker, /scrim: root\.scrim\b/)
  assert.doesNotMatch(picker, /styleColor: Util\.alpha\(root\.dimColor/)

  // Controls carry their own fill: Style.controlFill at rest is 4% alpha.
  assert.ok(
    (picker.match(/background: root\.chromeFill/g) || []).length >= 15,
    "every footer button needs an at-rest fill"
  )
  assert.equal(
    (picker.match(/bordered: true/g) || []).length,
    (picker.match(/background: root\.chromeFill/g) || []).length
  )
})

test("documents the release in the changelog, readme and submission notes", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const changelog = await read("CHANGELOG.md")
  const readme = await read("README.md")
  const verify = await read("MARKETPLACE-VERIFY.md")

  const heading = new RegExp("^## " + manifest.version.replace(/\./g, "\\.") + " - ", "m")
  assert.match(changelog, heading, "the changelog needs an entry for this version")
  assert.match(readme, /theme-collections\.json/)
  assert.match(readme, /`Ctrl\+G`/)
  // The submission body is written per release; a stale one is a stale review.
  assert.match(
    verify,
    new RegExp("(^|\\s)" + manifest.version.replace(/\./g, "\\.") + "(\\s|$)", "m"),
    "MARKETPLACE-VERIFY.md still describes an older version"
  )
})

test("keeps its own state under the private Store root, adopting 0.8.x once", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const pluginState = await read(join(runtimeDir, "PluginState.qml"))
  const collections = await read(join(runtimeDir, "ThemeCollectionsController.qml"))
  const notice = await read("omakit/NOTICE")

  // The block is vendored unmodified; a fix belongs in omakit, not the copy.
  assert.match(notice, /block store 0\.2\.0/)
  assert.match(await read("omakit/Store.qml"), /^\/\/ omakit block: store 0\.2\.0/)
  assert.match(await read("omakit/store-helper.py"), /^# omakit block: store 0\.2\.0/)

  // Every plugin-owned file goes through Store, under the plugin's own id.
  assert.match(pluginState, /property Store _store: Store \{/)
  assert.match(pluginState, /kind: "state"/)
  assert.match(picker, /readonly property string pluginId: "io\.github\.mtolhuys\.theme-manager"/)
  for (const name of [
    "theme-catalog-filters.json",
    "wallpaper-browser-filters.json",
    "wallpaper-command-center.json",
    "theme-manager-memory.json"
  ]) {
    assert.match(picker, new RegExp('name: "' + name.replace(/\./g, "\\.") + '"'))
  }
  assert.match(collections, /name: "theme-collections\.json"/)
  assert.equal((picker.match(/PluginState \{/g) || []).length, 4)
  assert.equal((collections.match(/PluginState \{/g) || []).length, 2)

  // The five 0.8.x paths are still named, because they are still read -- once,
  // when Store reports nothing of ours there yet -- and never written again.
  for (const legacy of [
    "theme-catalog-filters.json",
    "wallpaper-browser-filters.json",
    "wallpaper-command-center.json",
    "theme-manager-memory.json",
    "theme-collections.json"
  ]) {
    assert.match(
      picker,
      new RegExp("\\.config/omarchy/" + legacy.replace(/\./g, "\\.")),
      legacy + " keeps its 0.8.x path for the one-time read"
    )
  }
  assert.match(pluginState, /result\.state === "missing" && legacyPath && !_migrated/)
  assert.match(pluginState, /_migrated = true/)
  // The originals are left where they are, so a downgrade still finds them.
  assert.doesNotMatch(pluginState, /_legacy\.setText|_legacy\.remove|blockWrites/)
  assert.match(pluginState, /onLoaded: state\._adopt\(text\(\)\)/)

  // Nothing writes a plugin-owned file behind Store's back any more. The two
  // FileViews left in the picker read Omarchy's own state, and the third
  // writes the caller's selection and done files, which are not ours.
  assert.equal((picker.match(/FileView \{/g) || []).length, 3)
  assert.doesNotMatch(picker, /setText\(ThemeMemoryModel|setText\(WallpaperCommandModel/)
  for (const id of [
    "catalogFiltersFile",
    "wallhavenFiltersFile",
    "wallpaperCommandState",
    "themeMemoryStateFile"
  ]) {
    assert.doesNotMatch(picker, new RegExp(id + "\\.setText\\("))
  }

  // The hook runs where Run did not start it and reads the new root.
  const hook = await read("hooks/theme-set.d/50-theme-manager-memory")
  assert.match(hook, /XDG_STATE_HOME/)
  assert.match(hook, /io\.github\.mtolhuys\.theme-manager/)
})

test("publishes catalog cache entries through a checked directory descriptor", async () => {
  const cache = await read("catalog-cache.py")
  assert.match(cache, /os\.O_DIRECTORY \| os\.O_NOFOLLOW/)
  assert.match(cache, /info\.st_uid != os\.getuid\(\)/)
  assert.match(cache, /os\.O_EXCL \| os\.O_NOFOLLOW/)
  assert.match(cache, /os\.replace\(/)
  assert.match(cache, /src_dir_fd=cache_fd/)
  assert.match(cache, /dst_dir_fd=cache_fd/)
})

test("runs open wallpaper traffic through the bounded bundled provider", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const sources = await Promise.all(
    [
      "ImagePicker.qml",
      "WallpaperBrowserController.qml",
      "WallpaperBrowserModel.js",
      "WallhavenFilterBar.qml",
      "WallhavenFilterSheet.qml"
    ].map((file) => read(join(runtimeDir, file)))
  )
  const [picker, controller, model, filterBar, filterSheet] = sources

  const provider = await read("wallpaper-catalog.py")

  assert.match(model, /"--wallpaper-thumbs"/)
  assert.match(model, /"--wallpaper-download"/)
  assert.match(model, /"--collection"/)
  assert.match(model, /"--license"/)
  assert.match(controller, /maxSearchOutputBytes:\s*4 \* 1024 \* 1024/)
  assert.match(controller, /pagesPerRequest:\s*1/)
  assert.match(controller, /maxDownloadOutputBytes:\s*8 \* 1024/)
  assert.match(controller, /command\[0\] = root\.commandPath/)
  assert.match(picker, /commandPath: root\.pluginScriptPath\("wallpaper-catalog\.py"\)/)
  assert.match(provider, /MAX_API_BYTES = 4 \* 1024 \* 1024/)
  assert.match(provider, /MAX_THUMB_BYTES = 12 \* 1024 \* 1024/)
  assert.match(provider, /MAX_IMAGE_BYTES = 64 \* 1024 \* 1024/)
  assert.match(provider, /SEARCH_CACHE_TTL_SECONDS = 6 \* 60 \* 60/)
  assert.match(provider, /ThreadPoolExecutor\(max_workers=3\)/)
  assert.match(provider, /os\.O_DIRECTORY \| os\.O_NOFOLLOW/)
  assert.match(provider, /os\.O_EXCL \| os\.O_NOFOLLOW/)
  assert.match(provider, /def trusted_host\(host: str\)/)
  assert.doesNotMatch(provider, /wallhaven\.cc/)
  // Both provider runs go through omakit's Run block: the byte caps are the
  // block's, counted while reading, and every run has a deadline. The
  // hand-rolled StdioCollector/onDataChanged/signal(9) bound is gone, and
  // with it the separate stderr cap -- Run bounds each stream at maxBytes.
  assert.equal((controller.match(/^  Run \{/gm) || []).length, 2)
  assert.doesNotMatch(controller, /Process \{|StdioCollector|onDataChanged|\.signal\(9\)/)
  assert.match(controller, /maxBytes: root\.maxSearchOutputBytes/)
  assert.match(controller, /keepBytes: root\.maxSearchOutputBytes/)
  assert.match(controller, /maxBytes: root\.maxDownloadOutputBytes/)
  assert.equal((controller.match(/deadlineMs: \d+/g) || []).length, 2)
  assert.match(controller, /environment: root\.helperEnvironment/)
  assert.match(picker, /helperEnvironment: root\.helperEnvironment/)
  // The provider's own JSON error still outranks stderr, as it did on Process.
  assert.equal(
    (
      controller.match(
        /WallpaperBrowserModel\.processError\(\s*result\.stdout,\s*result\.stderr,/g
      ) || []
    ).length,
    2
  )
  assert.match(filterBar, /Filters/)
  assert.match(filterSheet, /Bundled Omarchy wallpapers/)
  assert.match(filterSheet, /getCollectionOptions/)
  assert.match(filterSheet, /getLicenseOptions/)
  assert.match(picker, /filterSheet\.openWith/)
  assert.doesNotMatch(sources.join("\n"), /wallhaven\.cc\/api/)
  assert.doesNotMatch(sources.join("\n"), /--colors|--purity/)
  assert.doesNotMatch(sources.join("\n"), /\bcurl\b/)
})

test("ships theme-set memory hook, Icons showcase chip, and Actions dropdown", async () => {
  const { access } = require("node:fs/promises")
  const { constants } = require("node:fs")
  const hook = "hooks/theme-set.d/50-theme-manager-memory"
  await access(join(process.cwd(), hook), constants.X_OK)
  const hookText = await read(hook)
  assert.match(hookText, /theme-manager-memory\.json/)
  assert.match(hookText, /omarchy-theme-bg-set/)
  assert.match(hookText, /icons\.theme/)

  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)
  assert.match(picker, /ensureThemeSetMemoryHook/)
  assert.match(picker, /probe-theme-lock\.sh/)
  assert.match(await read("probe-theme-lock.sh"), /omarchy-theme-set\.lock/)
  assert.match(picker, /footerIconLabel/)
  assert.match(picker, /Wallpaper saved for/)
  assert.match(picker, /id: iconsBrowseButton/)
  assert.match(picker, /model: \[root\.footerIconFolder/)
  assert.match(picker, /PanelToolTip/)
  assert.match(picker, /visible: !root\.footerIconHasPreviews/)
  assert.match(picker, /id: wallpaperActionsDropdown/)
  assert.match(picker, /wallpaperActionOptions/)
  assert.match(picker, /text: "☰"/)
  assert.match(picker, /font\.pixelSize: Style\.font\.icon/)
  assert.match(picker, /rotation: wallpaperActionsDropdown\.popupOpen \? 180 : 0/)
  assert.match(picker, /Behavior on rotation/)
  assert.match(picker, /id: actionsPopup/)
  assert.match(picker, /reloadLocalWallpapersFromDisk/)
  assert.match(picker, /refreshInPlace/)
  assert.match(picker, /function openIcons\(\)/)
  assert.doesNotMatch(picker, /value: "Actions"/)
  assert.doesNotMatch(picker, /id: iconsDropdown/)
  assert.doesNotMatch(picker, /SearchableDropdown/)
  assert.doesNotMatch(picker, /iconThemeOptions/)
  assert.match(picker, /footerPreviewIconTheme/)
  assert.match(picker, /function ensureFooterIconsReady/)
  assert.match(picker, /function ensureCurrentIconTheme/)
  assert.match(picker, /onManifestChanged/)
  assert.match(picker, /iconThemeProbeProc/)
  assert.match(picker, /id: wallpapersCrossNavButton/)
  assert.match(picker, /id: themesCrossNavButton/)
  assert.match(picker, /function openWallpapersSwitcher/)
  assert.match(picker, /function openThemesSwitcher/)
  assert.match(picker, /function browseForCurrentMode/)
  assert.match(picker, /packageIcons/)
  assert.match(picker, /function openIconsBrowse/)
  assert.match(picker, /icons-browse\.sh/)
  assert.match(picker, /IconBrowseController/)
  assert.match(picker, /id: iconsBrowseOcsButton/)
  assert.match(picker, /readonly property bool localIconsMode: iconsMode && !iconsBrowseMode\n/)
  assert.match(
    picker,
    /canOpenIconsMode:[\s\S]*?&& \(wallpaperPickerActive \|\| themeManager\.themePickerActive\)/
  )
  assert.match(picker, /text: iconBrowse\.loading \? "Loading…" : "Browse icons"/)
  assert.match(
    picker,
    /visible: root\.showLabels \|\| root\.wallpaperPickerActive \|\| root\.iconsMode \|\| root\.iconsBrowseMode/
  )
  assert.match(
    picker,
    /anchors\.right: iconsBrowseOcsButton\.visible \? iconsBrowseOcsButton\.left : parent\.right/
  )
  assert.match(picker, /id: iconsBrowseBackButton/)
  assert.match(picker, /id: iconsBrowseLoadMoreButton/)
})

test("delegates Pling icon browsing to the bounded icons-browse helper", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const model = await read(join(runtimeDir, "IconBrowseModel.js"))
  const controller = await read(join(runtimeDir, "IconBrowseController.qml"))
  const helper = await read("icons-browse.sh")

  assert.match(model, /images\\\.pling\\\.com/)
  assert.match(model, /safePreviewUrl/)
  assert.match(controller, /maxSearchOutputBytes/)
  assert.match(controller, /icons-browse|scriptPath/)
  assert.match(helper, /api\.gnome-look\.org/)
  assert.match(helper, /OMARCHY_ICONS_OCS_CATEGORY:-132/)
  assert.match(helper, /categories=\$\{category_id\}/)
  assert.match(helper, /content\/download/)
  assert.match(helper, /XDG_DATA_HOME:.*\.local\/share\}\/icons|icons_root=/)
  assert.match(helper, /index\.theme/)
  assert.match(picker, /iconBrowse\.requestInstall/)
  assert.match(picker, /iconInstallConfirm/)
  assert.doesNotMatch(picker, /api\.gnome-look\.org/)
})

test("installs external wallpapers into theme backgrounds for the local picker", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const runtimeDir = dirname(manifest.entryPoints.overlay)
  const picker = await read(join(runtimeDir, "ImagePicker.qml"))
  const memoryModel = await read(join(runtimeDir, "ThemeMemoryModel.js"))
  const installer = await read("install-wallpaper.sh")

  assert.match(memoryModel, /needsWallpaperInstall/)
  assert.match(memoryModel, /installedWallpaperPath/)
  assert.match(picker, /install-wallpaper\.sh/)
  assert.match(picker, /beginWallpaperInstall/)
  assert.match(picker, /ensureRememberedWallpaperInPicker/)
  assert.match(picker, /pruneRememberedWallpaper/)
  assert.match(picker, /localWallpaperScanDirs/)
  assert.match(picker, /list\.sh is the source of/)
  assert.doesNotMatch(picker, /injectWallpaperIntoCarousel\(remembered\)/)
  assert.match(picker, /acceptInstalledWallpaper/)
  assert.match(
    picker,
    /id: wallpaperInstallProc[\s\S]*?onFinished: function\(result\)[\s\S]*?result\.stdout/
  )
  assert.match(picker, /pendingInstallSourcePath/)
  assert.match(picker, /syncInstalledWallpaperIntoLocalSnapshot/)
  assert.match(picker, /installedWallpaperPath\(/)
  assert.match(picker, /root\.acceptInstalledWallpaper\(installed\)/)
  assert.doesNotMatch(picker, /onStreamFinished: root\.acceptInstalledWallpaper/)
  assert.match(picker, /canRemoveInstalledWallpaper/)
  assert.match(picker, /canResetWallpaper/)
  assert.match(picker, /removeCurrentInstalledWallpaper/)
  assert.match(picker, /resetWallpaperDefaults/)
  assert.match(picker, /remove-wallpaper\.sh/)
  assert.match(picker, /reset-wallpaper\.sh/)
  assert.match(picker, /dropWallpaperFromCarousel/)
  assert.match(picker, /reloadLocalWallpapersFromDisk/)
  assert.match(
    picker,
    /acceptRemovedInstalledWallpaper\(String\(result\.stdout \|\| ""\)\.trim\(\)\)/
  )
  assert.match(picker, /acceptResetWallpaper\(String\(result\.stdout \|\| ""\)\.trim\(\)\)/)
  assert.match(picker, /Optimistic UI drop BEFORE Process starts/)
  assert.doesNotMatch(picker, /root\.wallpaperRemoveProc\.succeeded/)
  assert.doesNotMatch(picker, /root\.wallpaperResetProc\.succeeded/)
  assert.match(picker, /model: root\.carouselPoolSize/)
  assert.match(picker, /readonly property int carouselPoolSize: 17/)
  assert.doesNotMatch(picker, /model: root\.imageArray\.length/)
  assert.match(picker, /replaceImageArray/)
  assert.match(picker, /imageModelEpoch/)
  assert.match(picker, /Live Remove must paint immediately/)
  assert.match(picker, /leftReserved/)
  assert.match(picker, /rightReserved/)
  assert.match(memoryModel, /isUserInstalledWallpaper/)
  assert.match(installer, /\.config\/omarchy\/backgrounds/)
  assert.match(installer, /realpath -e/)
  const publisher = await read("publish-wallpaper.py")
  assert.match(publisher, /os\.O_NOFOLLOW/)
  assert.match(publisher, /info\.st_uid != os\.getuid\(\)/)
  assert.match(publisher, /os\.O_EXCL/)
  assert.match(publisher, /os\.link\(/)
  assert.doesNotMatch(installer, /cp -f/)

  const remover = await read("remove-wallpaper.sh")
  const resetter = await read("reset-wallpaper.sh")
  assert.match(remover, /omarchy-theme-bg-set/)
  assert.match(remover, /Refusing to delete non-user wallpaper/)
  assert.match(resetter, /current\/theme\/backgrounds/)
  assert.match(resetter, /omarchy-theme-bg-set/)
  assert.match(resetter, /stock_dir=\$home\/\.local\/state\/omarchy\/current\/theme\/backgrounds/)
  assert.match(resetter, /theme_dir=\$home\/\.config\/omarchy\/backgrounds\/\$theme/)
  assert.match(resetter, /-delete/)
  assert.match(await read("list.sh"), /stat -c '%s'/)
  assert.match(await read("list.sh"), /4096/)
  assert.match(await read("install-wallpaper.sh"), /too small/)
})
