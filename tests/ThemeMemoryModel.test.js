const test = require("node:test")
const assert = require("node:assert/strict")

const ThemeMemoryModel = require("../v0200/ThemeMemoryModel.js")

test("parses versioned theme memory and rejects unsafe values", () => {
  const state = ThemeMemoryModel.parseState(
    JSON.stringify({
      version: 1,
      themes: {
        solitude: {
          wallpaper: "/walls/a.webp",
          icons: "Yaru-purple-dark",
          iconsDefault: "Yaru-sage-dark"
        },
        bad: {
          wallpaper: "relative.webp",
          icons: "../evil"
        }
      }
    })
  )

  assert.deepEqual(state, {
    version: 1,
    themes: {
      solitude: {
        wallpaper: "/walls/a.webp",
        icons: "Yaru-purple-dark",
        iconsDefault: "Yaru-sage-dark"
      }
    }
  })
  assert.deepEqual(ThemeMemoryModel.parseState("not json"), ThemeMemoryModel.emptyState())
})

test("saves and clears per-theme wallpaper overrides", () => {
  let state = ThemeMemoryModel.emptyState()
  state = ThemeMemoryModel.setWallpaper(state, "solitude", "/walls/a.webp")
  assert.equal(ThemeMemoryModel.rememberedWallpaper(state, "solitude"), "/walls/a.webp")
  assert.equal(ThemeMemoryModel.hasWallpaperOverride(state, "solitude"), true)

  state = ThemeMemoryModel.clearWallpaper(state, "solitude")
  assert.equal(ThemeMemoryModel.rememberedWallpaper(state, "solitude"), "")
  assert.equal(ThemeMemoryModel.hasWallpaperOverride(state, "solitude"), false)
})

test("stores icon overrides and preserves first iconsDefault", () => {
  let state = ThemeMemoryModel.emptyState()
  state = ThemeMemoryModel.setIcons(state, "solitude", "Yaru-purple-dark", "Yaru-sage-dark")
  assert.equal(ThemeMemoryModel.rememberedIcons(state, "solitude"), "Yaru-purple-dark")
  assert.equal(ThemeMemoryModel.rememberedIconsDefault(state, "solitude"), "Yaru-sage-dark")

  state = ThemeMemoryModel.setIcons(state, "solitude", "Yaru-blue-dark", "should-not-replace")
  assert.equal(ThemeMemoryModel.rememberedIcons(state, "solitude"), "Yaru-blue-dark")
  assert.equal(ThemeMemoryModel.rememberedIconsDefault(state, "solitude"), "Yaru-sage-dark")

  state = ThemeMemoryModel.clearIcons(state, "solitude")
  assert.equal(ThemeMemoryModel.rememberedIcons(state, "solitude"), "")
  assert.equal(ThemeMemoryModel.rememberedIconsDefault(state, "solitude"), "Yaru-sage-dark")
})

test("serializes normalized state for FileView persistence", () => {
  const state = ThemeMemoryModel.setWallpaper(
    ThemeMemoryModel.emptyState(),
    "solitude",
    "/walls/a.webp"
  )
  assert.deepEqual(JSON.parse(ThemeMemoryModel.serializeState(state)), {
    version: 1,
    themes: {
      solitude: {
        wallpaper: "/walls/a.webp"
      }
    }
  })
})

test("drops empty theme entries after clearing all overrides", () => {
  let state = ThemeMemoryModel.setWallpaper(
    ThemeMemoryModel.emptyState(),
    "solitude",
    "/walls/a.webp"
  )
  state = ThemeMemoryModel.clearWallpaper(state, "solitude")
  assert.deepEqual(state.themes, {})
})

test("detects picker vs external wallpaper paths and install targets", () => {
  const home = "/home/mtolhuijs"
  const catalog = home + "/.local/share/omarchy-theme-manager/wallpapers/ocs-21.png"
  const installed = home + "/.config/omarchy/backgrounds/vantablack/ocs-21.png"
  const themeBg = home + "/.local/state/omarchy/current/theme/backgrounds/omarchy.webp"

  assert.equal(ThemeMemoryModel.imageBasename(catalog), "ocs-21.png")
  assert.equal(
    ThemeMemoryModel.themeBackgroundsDir(home, "vantablack"),
    home + "/.config/omarchy/backgrounds/vantablack"
  )
  assert.equal(ThemeMemoryModel.needsWallpaperInstall(catalog, home, "vantablack"), true)
  assert.equal(ThemeMemoryModel.needsWallpaperInstall(installed, home, "vantablack"), false)
  assert.equal(ThemeMemoryModel.needsWallpaperInstall(themeBg, home, "vantablack"), false)
  assert.equal(ThemeMemoryModel.isCatalogWallpaperPath(catalog, home), true)
  assert.equal(ThemeMemoryModel.isPickerWallpaperPath(catalog, home, "vantablack"), false)
  assert.equal(ThemeMemoryModel.installedWallpaperPath(catalog, home, "vantablack"), installed)
  assert.equal(ThemeMemoryModel.needsWallpaperInstall(catalog, home, "../evil"), false)
  assert.equal(ThemeMemoryModel.themeBackgroundsDir(home, "bad/name"), "")
})

test("recognizes user-installed theme background files only", () => {
  const home = "/home/mtolhuijs"
  const installed = home + "/.config/omarchy/backgrounds/vantablack/wallhaven-21zz2g.png"
  const stock = home + "/.local/state/omarchy/current/theme/backgrounds/omarchy.webp"
  const catalog = home + "/.local/share/omarchy-theme-manager/wallpapers/ocs-21.png"
  assert.equal(ThemeMemoryModel.isUserInstalledWallpaper(installed, home, "vantablack"), true)
  assert.equal(ThemeMemoryModel.isUserInstalledWallpaper(stock, home, "vantablack"), false)
  assert.equal(ThemeMemoryModel.isUserInstalledWallpaper(catalog, home, "vantablack"), false)
  assert.equal(ThemeMemoryModel.isUserInstalledWallpaper(installed, home, "other"), false)
})
