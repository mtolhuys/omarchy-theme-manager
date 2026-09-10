const test = require("node:test")
const assert = require("node:assert/strict")
const { readFile } = require("node:fs/promises")
const { dirname, join } = require("node:path")
const process = require("node:process")

const read = (path) => readFile(join(process.cwd(), path), "utf8")

test("keeps the published Theme Manager identity as the sole picker clone", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  assert.equal(manifest.id, "io.github.mtolhuys.theme-manager")
  assert.equal(manifest.version, "0.5.13")
  assert.deepEqual(manifest.kinds, ["overlay"])
  assert.match(manifest.entryPoints.overlay, /^v[0-9]{4}\/ImagePicker\.qml$/)
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.image-picker")
  assert.equal(manifest.keepLoaded, true)
})

test("releases image-selector clients independently of QML loader teardown", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)

  assert.match(picker, /Quickshell\.execDetached\(\["touch", "--", String\(path\)\]\)/)
  assert.doesNotMatch(picker, /doneFilesToRelease|releaseNextDoneFile|id: releaseProc/)
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
    "WallhavenFilterBar.qml",
    "WallhavenFilterSheet.qml",
    "ThemeCatalogFilterBar.qml",
    "ThemeCatalogFilterSheet.qml",
    "ThemeMemoryModel.js",
    "IconThemeModel.js"
  ]) {
    assert.ok((await read(join(runtimeDir, file))).length > 0, file)
  }
})

test("resolves bundled helpers without private host manifest fields", async () => {
  const manifest = JSON.parse(await read("manifest.json"))
  const picker = await read(manifest.entryPoints.overlay)

  assert.match(picker, /Qt\.resolvedUrl\("\.\.\/"\)/)
  assert.match(picker, /decodeURIComponent\(value\)/)
  assert.doesNotMatch(picker, /manifest\.__sourceDir/)

  for (const helper of [
    "catalog.sh",
    "icons-inventory.sh",
    "install-wallpaper.sh",
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
  assert.match(picker, /if \(catalogMode\).*themeCatalog\.openSelectedRepository/s)
  assert.match(picker, /if \(wallhavenMode\).*wallhaven\.download/s)

  const catalogController = await read(join(runtimeDir, "ThemeCatalogController.qml"))
  const catalogModel = await read(join(runtimeDir, "ThemeCatalogModel.js"))
  const catalogRuntime = [picker, catalogController, catalogModel].join("\n")
  assert.match(catalogController, /openRepositoryRequested\(repositoryUrl\)/)
  assert.match(catalogController, /ThemeCatalogModel\.normalizeRepositoryUrl/)
  assert.match(picker, /Util\.execArgv\(\["xdg-open", url\]\)/)
  assert.doesNotMatch(
    catalogRuntime,
    /omarchy-theme-install|["']omarchy["']\s*,\s*["']theme["']\s*,\s*["']install["']/
  )
  assert.doesNotMatch(
    catalogRuntime,
    /installProc|requestInstall|confirmInstall|canInstall|onThemeInstalled/
  )

  assert.match(picker, /ThemeMemoryModel/)
  assert.match(picker, /root\.openIcons\(\)/)
  assert.match(picker, /function openIcons\(\)/)
  assert.match(picker, /theme-manager-memory\.json/)
  assert.doesNotMatch(picker, /io\.github\.mtolhuys\.wallpaper-manager/)
})

test("delegates SFW Wallhaven traffic exclusively to bounded Aether processes", async () => {
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

  assert.match(model, /"--wallhaven-thumbs"/)
  assert.match(model, /"--wallhaven-download"/)
  assert.match(model, /"--purity",\s*"100"/)
  assert.match(controller, /maxSearchOutputBytes:\s*4 \* 1024 \* 1024/)
  assert.match(controller, /maxDownloadOutputBytes:\s*8 \* 1024/)
  assert.match(controller, /maxErrorOutputBytes:\s*64 \* 1024/)
  assert.equal((controller.match(/onDataChanged:/g) || []).length, 4)
  assert.equal((controller.match(/\.signal\(9\)/g) || []).length, 4)
  assert.match(filterBar, /Filters/)
  assert.match(filterSheet, /selected color need not dominate/)
  assert.match(picker, /filterSheet\.openWith/)
  assert.doesNotMatch(sources.join("\n"), /wallhaven\.cc\/api/)
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
  assert.match(picker, /omarchy-theme-set\.lock/)
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
  assert.match(picker, /canRemoveInstalledWallpaper/)
  assert.match(picker, /canResetWallpaper/)
  assert.match(picker, /removeCurrentInstalledWallpaper/)
  assert.match(picker, /resetWallpaperDefaults/)
  assert.match(picker, /remove-wallpaper\.sh/)
  assert.match(picker, /reset-wallpaper\.sh/)
  assert.match(picker, /dropWallpaperFromCarousel/)
  assert.match(picker, /reloadLocalWallpapersFromDisk/)
  assert.match(picker, /wallpaperRemoveStdout/)
  assert.match(picker, /wallpaperResetStdout/)
  assert.match(picker, /acceptRemovedInstalledWallpaper\(root\.wallpaperRemoveStdout\)/)
  assert.match(picker, /acceptResetWallpaper\(root\.wallpaperResetStdout\)/)
  assert.match(picker, /Optimistic UI drop BEFORE Process starts/)
  assert.doesNotMatch(picker, /root\.wallpaperRemoveProc\.succeeded/)
  assert.doesNotMatch(picker, /root\.wallpaperResetProc\.succeeded/)
  assert.match(picker, /model: root\.imageArray\.length/)
  assert.match(picker, /replaceImageArray/)
  assert.match(picker, /imageModelEpoch/)
  assert.match(picker, /Live Remove must paint immediately/)
  assert.match(picker, /leftReserved/)
  assert.match(picker, /rightReserved/)
  assert.match(memoryModel, /isUserInstalledWallpaper/)
  assert.match(installer, /\.config\/omarchy\/backgrounds/)
  assert.match(installer, /realpath -e/)

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
