const test = require("node:test")
const assert = require("node:assert/strict")

const WallpaperCommandModel = require("../v0200/WallpaperCommandModel.js")

const context = {
  themeRoot: "/home/user/.local/state/omarchy/current/theme/backgrounds",
  themeName: "Tokyo Night"
}

test("parses bounded favorite identities and migrates legacy paths", () => {
  assert.deepEqual(
    WallpaperCommandModel.parseState(
      JSON.stringify({ favorites: ["/walls/a.jpg", "relative.jpg", "/walls/a.jpg"] }),
      context
    ),
    { version: 2, favorites: ["path:%2Fwalls%2Fa.jpg"], folder: "", showHidden: false }
  )
  assert.deepEqual(WallpaperCommandModel.parseState("not json").favorites, [])
})

test("carries the remembered browse folder beside the favorites", () => {
  const state = WallpaperCommandModel.parseState(
    JSON.stringify({
      version: 2,
      favorites: [],
      folder: "/home/user/Pictures/Walls",
      showHidden: true
    })
  )

  assert.equal(state.folder, "/home/user/Pictures/Walls")
  assert.equal(state.showHidden, true)

  // A relative folder is no folder, and a file written before browsing
  // existed simply has none.
  assert.equal(WallpaperCommandModel.parseState(JSON.stringify({ folder: "Pictures" })).folder, "")
  assert.equal(WallpaperCommandModel.parseState(JSON.stringify({ version: 2 })).folder, "")
  assert.equal(WallpaperCommandModel.parseState(JSON.stringify(["/walls/a.jpg"])).folder, "")
  assert.equal(WallpaperCommandModel.parseState("not json").showHidden, false)
})

test("toggles favorites with the newest selection first", () => {
  assert.deepEqual(
    WallpaperCommandModel.toggleFavorite(["path:%2Fwalls%2Fa.jpg"], "/walls/b.jpg"),
    ["path:%2Fwalls%2Fb.jpg", "path:%2Fwalls%2Fa.jpg"]
  )
  assert.deepEqual(
    WallpaperCommandModel.toggleFavorite(
      ["path:%2Fwalls%2Fa.jpg", "path:%2Fwalls%2Fb.jpg"],
      "/walls/a.jpg"
    ),
    ["path:%2Fwalls%2Fb.jpg"]
  )
})

test("keeps current-theme favorites bound to the theme identity", () => {
  const path = context.themeRoot + "/omarchy.webp"
  const favorite = WallpaperCommandModel.favoriteIdForPath(path, context)

  assert.equal(favorite, "theme:Tokyo%20Night:omarchy.webp")
  assert.equal(WallpaperCommandModel.isFavorite([favorite], path, context), true)
  assert.equal(
    WallpaperCommandModel.isFavorite([favorite], path, { ...context, themeName: "Nord" }),
    false
  )
})

test("moves favorites into a stable front section without losing rows", () => {
  const images = ["a", "b", "c", "d"].map((name) => ({ filePath: `/walls/${name}.jpg` }))
  const result = WallpaperCommandModel.prioritizeFavorites(images, [
    "path:%2Fwalls%2Fd.jpg",
    "path:%2Fwalls%2Fb.jpg"
  ])

  assert.deepEqual(
    result.map((image) => image.filePath),
    ["/walls/d.jpg", "/walls/b.jpg", "/walls/a.jpg", "/walls/c.jpg"]
  )
})

test("serializes normalized versioned state", () => {
  assert.deepEqual(JSON.parse(WallpaperCommandModel.serializeState(["path:%2Fwalls%2Fa.jpg"])), {
    version: 2,
    favorites: ["path:%2Fwalls%2Fa.jpg"],
    folder: "",
    showHidden: false
  })

  assert.deepEqual(
    JSON.parse(WallpaperCommandModel.serializeState([], "/home/user/Pictures", true)),
    { version: 2, favorites: [], folder: "/home/user/Pictures", showHidden: true }
  )
})
