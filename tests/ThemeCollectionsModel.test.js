const test = require("node:test")
const assert = require("node:assert/strict")

const ThemeCollectionsModel = require("../v0200/ThemeCollectionsModel.js")
const ImagePickerModel = require("../v0200/ImagePickerModel.js")

const previews = "/home/user/.cache/omarchy/theme-selector/previews/"
const image = (name) => ({
  filePath: previews + name + ".png",
  fileName: name + ".png",
  thumbnailPath: previews + name + ".png"
})
const images = ["tokyo-night", "catppuccin", "nord", "manga", "ember-n-ash"].map(image)
const allIndices = images.map((_, index) => index)
const inventory = {
  inventoryReady: true,
  stockThemes: { "tokyo-night": true, catppuccin: true, nord: true }
}

test("parses versioned collections and drops unsafe or duplicate entries", () => {
  const state = ThemeCollectionsModel.parseState(
    JSON.stringify({
      version: 1,
      favorites: ["nord", "../evil", "nord", "", "manga"],
      collections: [
        { id: "c1", name: "  Work   desk ", themes: ["nord", "nord", "bad/name"] },
        { id: "favorites", name: "Reserved", themes: [] },
        { id: "c1", name: "Duplicate id", themes: [] },
        { id: "c2", name: "", themes: ["manga"] },
        "not an object"
      ]
    })
  )

  assert.deepEqual(state, {
    version: 1,
    view: "carousel",
    favorites: ["nord", "manga"],
    collections: [{ id: "c1", name: "Work desk", themes: ["nord"] }]
  })
})

test("remembers the carousel or grid layout and refuses anything else", () => {
  assert.equal(ThemeCollectionsModel.emptyState().view, "carousel")
  assert.equal(ThemeCollectionsModel.isGridView(ThemeCollectionsModel.emptyState()), false)

  const grid = ThemeCollectionsModel.setView(ThemeCollectionsModel.emptyState(), "grid")
  assert.equal(grid.view, "grid")
  assert.equal(ThemeCollectionsModel.isGridView(grid), true)
  assert.equal(
    ThemeCollectionsModel.isGridView(ThemeCollectionsModel.setView(grid, "carousel")),
    false
  )

  // Round-trips through the file, so the layout survives a shell restart.
  assert.equal(
    ThemeCollectionsModel.parseState(ThemeCollectionsModel.serializeState(grid)).view,
    "grid"
  )

  // A file written before 0.8.0 has no view and opens in the carousel.
  assert.equal(
    ThemeCollectionsModel.parseState('{"version":1,"favorites":["nord"]}').view,
    "carousel"
  )
  assert.equal(ThemeCollectionsModel.safeView("GRID"), "grid")
  assert.equal(ThemeCollectionsModel.safeView("  grid  "), "grid")
  for (const value of ["list", "", null, undefined, 7, {}]) {
    assert.equal(
      ThemeCollectionsModel.safeView(value),
      "carousel",
      JSON.stringify(value) || "undefined"
    )
  }
  assert.equal(ThemeCollectionsModel.setView(grid, "nonsense").view, "carousel")
  assert.equal(ThemeCollectionsModel.parseState('{"view":"grid"}').view, "grid")
})

test("treats a blank file as empty and a corrupt file as empty with a backup", () => {
  assert.deepEqual(ThemeCollectionsModel.parseStateResult(""), {
    state: ThemeCollectionsModel.emptyState(),
    corrupt: false
  })
  assert.equal(ThemeCollectionsModel.emptyState().view, "carousel")
  assert.deepEqual(ThemeCollectionsModel.parseStateResult("  \n"), {
    state: ThemeCollectionsModel.emptyState(),
    corrupt: false
  })
  assert.deepEqual(ThemeCollectionsModel.parseStateResult("{ not json"), {
    state: ThemeCollectionsModel.emptyState(),
    corrupt: true
  })
  assert.deepEqual(ThemeCollectionsModel.parseStateResult("[1, 2]"), {
    state: ThemeCollectionsModel.emptyState(),
    corrupt: true
  })
  assert.equal(
    ThemeCollectionsModel.backupPath("/home/user/.config/omarchy/theme-collections.json"),
    "/home/user/.config/omarchy/theme-collections.json.bak"
  )
  assert.equal(ThemeCollectionsModel.backupPath(""), "")
})

test("serializes the fixed schema and round-trips", () => {
  let state = ThemeCollectionsModel.emptyState()
  state = ThemeCollectionsModel.toggleFavorite(state, "nord")
  state = ThemeCollectionsModel.createCollection(state, "Work", ["nord"]).state
  const text = ThemeCollectionsModel.serializeState(state)
  assert.equal(
    text,
    JSON.stringify(
      {
        version: 1,
        view: "carousel",
        favorites: ["nord"],
        collections: [{ id: "c1", name: "Work", themes: ["nord"] }]
      },
      null,
      2
    ) + "\n"
  )
  assert.deepEqual(ThemeCollectionsModel.parseState(text), state)
})

test("stars and unstars themes without touching other state", () => {
  let state = ThemeCollectionsModel.emptyState()
  assert.equal(ThemeCollectionsModel.isFavorite(state, "nord"), false)

  state = ThemeCollectionsModel.toggleFavorite(state, "nord")
  state = ThemeCollectionsModel.toggleFavorite(state, "manga")
  assert.equal(ThemeCollectionsModel.isFavorite(state, "nord"), true)
  assert.equal(ThemeCollectionsModel.favoriteCount(state), 2)

  state = ThemeCollectionsModel.toggleFavorite(state, "nord")
  assert.deepEqual(state.favorites, ["manga"])

  const unchanged = ThemeCollectionsModel.toggleFavorite(state, "../evil")
  assert.deepEqual(unchanged, state)
})

test("creates, renames, deletes collections and validates names", () => {
  let state = ThemeCollectionsModel.emptyState()
  const created = ThemeCollectionsModel.createCollection(state, "  Work  ", ["nord", "nord"])
  assert.equal(created.error, "")
  assert.equal(created.id, "c1")
  state = created.state
  assert.deepEqual(state.collections, [{ id: "c1", name: "Work", themes: ["nord"] }])

  assert.equal(
    ThemeCollectionsModel.validateCollectionName(state, "   "),
    "Give the collection a name"
  )
  assert.equal(
    ThemeCollectionsModel.validateCollectionName(state, "work"),
    "A collection already has that name"
  )
  assert.equal(ThemeCollectionsModel.validateCollectionName(state, "Work", "c1"), "")
  assert.match(ThemeCollectionsModel.validateCollectionName(state, "x".repeat(65)), /within 64/)
  assert.equal(
    ThemeCollectionsModel.createCollection(state, "work").error,
    "A collection already has that name"
  )

  const renamed = ThemeCollectionsModel.renameCollection(state, "c1", "Play")
  assert.equal(renamed.error, "")
  assert.equal(ThemeCollectionsModel.collectionById(renamed.state, "c1").name, "Play")
  assert.equal(
    ThemeCollectionsModel.renameCollection(state, "missing", "Play").error,
    "That collection no longer exists"
  )

  const second = ThemeCollectionsModel.createCollection(renamed.state, "Second", [])
  assert.equal(second.id, "c2")
  const deleted = ThemeCollectionsModel.deleteCollection(second.state, "c1")
  assert.deepEqual(
    deleted.collections.map((entry) => entry.id),
    ["c2"]
  )
  assert.equal(ThemeCollectionsModel.nextCollectionId(deleted), "c1")
  assert.deepEqual(ThemeCollectionsModel.deleteCollection(deleted, "favorites"), deleted)
})

test("caps collections at the documented limit", () => {
  let state = ThemeCollectionsModel.emptyState()
  for (let index = 0; index < ThemeCollectionsModel.maxCollections; index++) {
    state = ThemeCollectionsModel.createCollection(state, "Collection " + index, []).state
  }
  assert.equal(state.collections.length, ThemeCollectionsModel.maxCollections)
  assert.match(ThemeCollectionsModel.createCollection(state, "One more").error, /Up to 100/)
})

test("edits memberships through the sheet rows", () => {
  let state = ThemeCollectionsModel.createCollection(
    ThemeCollectionsModel.emptyState(),
    "Work",
    []
  ).state
  state = ThemeCollectionsModel.createCollection(state, "Play", ["nord"]).state

  assert.deepEqual(ThemeCollectionsModel.membershipRows(state, "nord"), [
    { id: "favorites", name: "Favorites", member: false },
    { id: "c1", name: "Work", member: false },
    { id: "c2", name: "Play", member: true }
  ])

  state = ThemeCollectionsModel.applyMemberships(state, "nord", [
    { id: "favorites", name: "Favorites", member: true },
    { id: "c1", name: "Work", member: true },
    { id: "c2", name: "Play", member: false },
    { id: "missing", name: "Gone", member: true }
  ])
  assert.deepEqual(state.favorites, ["nord"])
  assert.equal(ThemeCollectionsModel.isMember(state, "c1", "nord"), true)
  assert.equal(ThemeCollectionsModel.isMember(state, "c2", "nord"), false)

  state = ThemeCollectionsModel.setMembership(state, "c1", "nord", false)
  assert.deepEqual(ThemeCollectionsModel.collectionById(state, "c1").themes, [])
})

test("hides missing themes from sections but keeps them in the file", () => {
  let state = ThemeCollectionsModel.toggleFavorite(
    ThemeCollectionsModel.emptyState(),
    "uninstalled"
  )
  state = ThemeCollectionsModel.toggleFavorite(state, "nord")
  state = ThemeCollectionsModel.createCollection(state, "Work", ["uninstalled", "manga"]).state

  const sections = ThemeCollectionsModel.sections(images, allIndices, state, inventory)
  assert.deepEqual(
    sections.map((section) => [section.id, section.indices]),
    [
      ["favorites", [2]],
      ["defaults", [0, 1, 2]],
      ["installed", [3, 4]],
      ["c1", [3]]
    ]
  )

  const serialized = ThemeCollectionsModel.parseState(ThemeCollectionsModel.serializeState(state))
  assert.deepEqual(serialized.favorites, ["uninstalled", "nord"])
  assert.deepEqual(serialized.collections[0].themes, ["uninstalled", "manga"])
})

test("builds one section before the inventory is ready and only favorites on request", () => {
  const state = ThemeCollectionsModel.toggleFavorite(ThemeCollectionsModel.emptyState(), "manga")

  assert.deepEqual(
    ThemeCollectionsModel.sections(images, allIndices, state, { inventoryReady: false }).map(
      (section) => [section.id, section.indices.length]
    ),
    [
      ["favorites", 1],
      ["all", 5]
    ]
  )
  assert.deepEqual(
    ThemeCollectionsModel.sections(images, allIndices, state, { favoritesOnly: true }).map(
      (section) => [section.id, section.indices]
    ),
    [["favorites", [3]]]
  )
  assert.deepEqual(
    ThemeCollectionsModel.sections(images, allIndices, ThemeCollectionsModel.emptyState(), {
      favoritesOnly: true
    }),
    []
  )
})

test("extends the installed-theme search to collection names without an index", () => {
  const state = ThemeCollectionsModel.createCollection(
    ThemeCollectionsModel.emptyState(),
    "Work desk",
    ["manga", "nord"]
  ).state
  const textIndices = ImagePickerModel.matchingIndices(images, "work")
  assert.deepEqual(textIndices, [])

  assert.deepEqual(
    ThemeCollectionsModel.searchIndices(
      images,
      textIndices,
      "work",
      state,
      ImagePickerModel.textMatches
    ),
    [2, 3]
  )
  assert.deepEqual(
    ThemeCollectionsModel.searchIndices(
      images,
      ImagePickerModel.matchingIndices(images, "nord"),
      "nord",
      state,
      ImagePickerModel.textMatches
    ),
    [2]
  )
  assert.deepEqual(
    ThemeCollectionsModel.searchIndices(
      images,
      allIndices,
      "",
      state,
      ImagePickerModel.textMatches
    ),
    allIndices
  )
  assert.deepEqual(ThemeCollectionsModel.favoriteIndices(images, allIndices, state), [])
})

test("lays out a grouped grid inside a bounded delegate pool", () => {
  const state = ThemeCollectionsModel.createCollection(
    ThemeCollectionsModel.toggleFavorite(ThemeCollectionsModel.emptyState(), "manga"),
    "Work",
    ["nord", "manga"]
  ).state
  const geometry = ThemeCollectionsModel.gridGeometry(1200, 475)
  assert.equal(geometry.columns, 4)
  assert.equal(geometry.cellWidth, 260)
  assert.equal(geometry.cellHeight, 146)

  const sections = ThemeCollectionsModel.sections(images, allIndices, state, inventory)
  const model = ThemeCollectionsModel.gridModel(sections, geometry)
  assert.deepEqual(
    model.rows.map((row) => row.kind),
    ["header", "cells", "header", "cells", "header", "cells", "header", "cells"]
  )
  assert.equal(model.cells.length, 1 + 3 + 2 + 2)
  assert.deepEqual(
    model.cells.map((cell) => cell.imageIndex),
    [3, 0, 1, 2, 3, 4, 2, 3]
  )
  assert.equal(model.cells[1].x, geometry.offsetX)
  assert.equal(model.cells[2].x, geometry.offsetX + 272)

  const slots = ThemeCollectionsModel.gridSlots(model, 0, 475, 17)
  assert.equal(slots.length, 17)
  const visible = slots.filter(Boolean)
  assert.ok(visible.length <= 16, "at most 16 cells are ever visible")
  assert.equal(visible[0].position, 0)
  assert.equal(visible[0].y, geometry.headerHeight + geometry.gap)

  const headers = ThemeCollectionsModel.gridHeaders(model, 0, 475)
  assert.deepEqual(
    headers.map((header) => header.text),
    ["Favorites", "Omarchy defaults", "Installed"]
  )
})

test("scrolls the grid so the cursor row and its header stay visible", () => {
  let state = ThemeCollectionsModel.emptyState()
  for (const name of ["a", "b", "c", "d"]) {
    state = ThemeCollectionsModel.createCollection(state, "Collection " + name, ["nord"]).state
  }
  const geometry = ThemeCollectionsModel.gridGeometry(1200, 475)
  const model = ThemeCollectionsModel.gridModel(
    ThemeCollectionsModel.sections(images, allIndices, state, inventory),
    geometry
  )
  assert.ok(model.height > 475)

  assert.equal(ThemeCollectionsModel.scrollTopForCursor(model, 0, 475, 0), 0)
  const last = model.cells.length - 1
  const bottom = ThemeCollectionsModel.scrollTopForCursor(model, last, 475, 0)
  assert.equal(bottom, model.height - 475)
  assert.equal(ThemeCollectionsModel.scrollTopForCursor(model, last, 475, bottom), bottom)
  const firstRowOfSecondSection = model.cells.find((cell) => cell.sectionId === "installed")
  const top = ThemeCollectionsModel.scrollTopForCursor(
    model,
    firstRowOfSecondSection.position,
    475,
    bottom
  )
  assert.equal(top, model.rows[firstRowOfSecondSection.row - 1].y)
  assert.equal(ThemeCollectionsModel.scrollTopForCursor(model, -1, 475, 200), 0)

  const slots = ThemeCollectionsModel.gridSlots(model, bottom, 475, 17).filter(Boolean)
  assert.ok(slots.length > 0)
  assert.ok(slots.every((cell) => cell.y < 475 && cell.y + cell.height > 0))
  assert.equal(new Set(slots.map((cell) => cell.position % 17)).size, slots.length)
})

test("moves the grid cursor by cell and by column", () => {
  const state = ThemeCollectionsModel.createCollection(ThemeCollectionsModel.emptyState(), "Work", [
    "nord",
    "manga"
  ]).state
  const geometry = ThemeCollectionsModel.gridGeometry(1200, 475)
  const model = ThemeCollectionsModel.gridModel(
    ThemeCollectionsModel.sections(images, allIndices, state, inventory),
    geometry
  )
  // defaults: [0,1,2]  installed: [3,4]  Work: [2,3]
  assert.deepEqual(
    model.cells.map((cell) => cell.imageIndex),
    [0, 1, 2, 3, 4, 2, 3]
  )

  assert.equal(ThemeCollectionsModel.moveCursor(model, 0, 1, 0), 1)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 0, -1, 0), 6)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 6, 1, 0), 0)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 2, 0, 1), 4)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 4, 0, 1), 6)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 6, 0, 1), 6)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 6, 0, -1), 4)
  assert.equal(ThemeCollectionsModel.moveCursor(model, 3, 0, -1), 0)
  assert.equal(ThemeCollectionsModel.moveCursor({ cells: [], rows: [] }, 0, 1, 0), -1)

  assert.equal(ThemeCollectionsModel.cellPositionForImage(model, 2, "c1"), 5)
  assert.equal(ThemeCollectionsModel.cellPositionForImage(model, 2, "favorites"), 2)
  assert.equal(ThemeCollectionsModel.cellPositionForImage(model, 9, ""), -1)
  assert.equal(ThemeCollectionsModel.sectionIdForPosition(model, 5), "c1")
  assert.equal(ThemeCollectionsModel.sectionIdForPosition(model, 99), "")
  assert.equal(ThemeCollectionsModel.themeIdForImage(images[2]), "nord")
  assert.equal(ThemeCollectionsModel.themeIdForImage({ filePath: "/x/..png" }), "")
})
