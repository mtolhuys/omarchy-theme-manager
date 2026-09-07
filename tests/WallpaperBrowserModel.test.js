const test = require("node:test")
const assert = require("node:assert/strict")
const { dirname, join } = require("node:path")

const manifest = require("../manifest.json")
const runtimeDir = dirname(manifest.entryPoints.overlay)
const model = require(join("..", runtimeDir, "WallpaperBrowserModel.js"))

const response = (wallpapers, meta = {}) =>
  JSON.stringify({
    wallpapers,
    meta: {
      current_page: 1,
      last_page: 4,
      total: 160,
      ...meta
    }
  })

const wallpaper = (id, overrides = {}) => ({
  id,
  resolution: "2560x1440",
  category: "general",
  purity: "sfw",
  thumbnailPath: "/tmp/aether/wallhaven-thumbs/" + id + ".jpg",
  ...overrides
})

test("recognizes only Omarchy background-picker directory requests", () => {
  assert.equal(
    model.isWallpaperPickerDirs("/home/alice/.local/state/omarchy/current/theme/backgrounds"),
    true
  )
  assert.equal(
    model.isWallpaperPickerDirs(
      [
        "/home/alice/.local/state/omarchy/current/theme/backgrounds",
        "/home/alice/.config/omarchy/backgrounds/catppuccin"
      ].join("\n")
    ),
    true
  )
  assert.equal(
    model.isWallpaperPickerDirs("/home/alice/.cache/omarchy/theme-selector/previews"),
    false
  )
  assert.equal(model.isWallpaperPickerDirs("/home/alice/Pictures"), false)
})

test("classifies row-backed picker requests without inheriting stale directories", () => {
  const backgroundRows = [
    "/home/alice/.local/state/omarchy/current/theme/backgrounds/one.webp\t/tmp/one.jpg",
    "/home/alice/.config/omarchy/backgrounds/miasma/two.png\t/tmp/two.jpg"
  ].join("\n")
  const themeRows = "/home/alice/.cache/omarchy/theme-selector/previews/miasma.png\t/tmp/miasma.jpg"

  assert.equal(model.isWallpaperPickerRows(backgroundRows), true)
  assert.equal(model.isWallpaperPickerRows(themeRows), false)
  assert.equal(
    model.isWallpaperPickerRequest(
      "/home/alice/.cache/omarchy/theme-selector/previews",
      backgroundRows
    ),
    true
  )
  assert.equal(
    model.isWallpaperPickerRequest(
      "/home/alice/.local/state/omarchy/current/theme/backgrounds",
      themeRows
    ),
    false
  )
})

test("builds Aether search arguments with the same safe defaults", () => {
  assert.deepEqual(model.searchArguments("solar punk", 3, 2), [
    "aether",
    "--wallhaven-thumbs",
    "--json",
    "--pages",
    "2",
    "--categories",
    "111",
    "--purity",
    "100",
    "--sorting",
    "relevance",
    "--order",
    "desc",
    "--page",
    "3",
    "--at-least",
    "1920x1080",
    "solar punk"
  ])
  assert.deepEqual(model.searchArguments("", 3, 2), [
    "aether",
    "--wallhaven-thumbs",
    "--json",
    "--pages",
    "2",
    "--categories",
    "111",
    "--purity",
    "100",
    "--sorting",
    "date_added",
    "--order",
    "desc",
    "--page",
    "3",
    "--at-least",
    "1920x1080"
  ])
  assert.equal(model.searchArguments("a; touch /tmp/nope").at(-1), "a; touch /tmp/nope")
  assert.equal(model.normalizeQuery("night\ncity\u0000"), "night city")
})

test("normalizes the supported Aether filters", () => {
  assert.deepEqual(model.normalizeFilters({}), {
    categories: "111",
    sorting: "date_added",
    order: "desc",
    atLeast: "1920x1080",
    colors: ""
  })
  assert.deepEqual(
    model.normalizeFilters({
      categories: "010",
      sorting: "favorites",
      order: "asc",
      atLeast: "3840x2160",
      colors: "0066cc"
    }),
    {
      categories: "010",
      sorting: "favorites",
      order: "asc",
      atLeast: "3840x2160",
      colors: "0066cc"
    }
  )
  assert.deepEqual(
    model.normalizeFilters({
      categories: "000",
      sorting: "unsupported",
      order: "sideways",
      atLeast: "640x480",
      colors: "not-a-color"
    }),
    {
      categories: "111",
      sorting: "date_added",
      order: "desc",
      atLeast: "1920x1080",
      colors: ""
    }
  )

  assert.equal(model.toggleCategory("111", 1), "101")
  assert.equal(model.toggleCategory("100", 0), "100")
  assert.equal(model.toggleCategory("111", 8), "111")
  assert.equal(model.nextSorting("date_added"), "relevance")
  assert.equal(model.nextSorting("toplist"), "date_added")
  assert.equal(model.normalizeFilters({ sorting: "random" }).sorting, "date_added")
  assert.equal(model.sortingLabel("views"), "Popular")
  assert.equal(model.nextResolution("1920x1080"), "2560x1440")
  assert.equal(model.nextResolution("3840x2160"), "")
  assert.equal(model.resolutionLabel(""), "Any resolution")
  assert.equal(model.colorLabel("0066cc"), "Blue")
  assert.equal(model.categorySummary("101"), "General + People")
  assert.equal(
    model.filterSummary({
      categories: "010",
      sorting: "favorites",
      order: "asc",
      atLeast: "3840x2160",
      colors: "0066cc"
    }),
    "Anime  ·  Favorites ↑  ·  4K+  ·  Blue palette"
  )
  assert.equal(
    model.filterKey({
      categories: "010",
      sorting: "favorites",
      order: "asc",
      atLeast: "3840x2160",
      colors: "0066cc"
    }),
    "010|favorites|asc|3840x2160|0066cc"
  )
})

test("exposes copy-safe direct-choice models for the filter sheet", () => {
  const sorting = model.getSortingOptions()
  const resolutions = model.getResolutionOptions()
  const colors = model.getColorOptions()

  assert.deepEqual(
    sorting.map((option) => option.value),
    ["date_added", "relevance", "views", "favorites", "toplist"]
  )
  assert.deepEqual(
    resolutions.map((option) => option.value),
    ["", "1920x1080", "2560x1440", "3840x2160"]
  )
  assert.deepEqual(
    colors.map((option) => option.value),
    ["", "660000", "cc6633", "ffcc33", "336600", "0066cc", "663399", "000000", "cccccc", "ffffff"]
  )
  assert.deepEqual(colors[4], { value: "336600", label: "Green" })

  for (const unsupported of ["ffcc00", "006600", "336699", "660066"]) {
    assert.equal(model.normalizeFilters({ colors: unsupported }).colors, "")
  }

  sorting[0].label = "Changed"
  assert.equal(model.getSortingOptions()[0].label, "Latest")
})

test("passes selected filters to Aether without weakening SFW purity", () => {
  assert.deepEqual(
    model.searchArguments("", 1, 4, {
      categories: "010",
      sorting: "favorites",
      order: "asc",
      atLeast: "3840x2160",
      colors: "0066cc"
    }),
    [
      "aether",
      "--wallhaven-thumbs",
      "--json",
      "--pages",
      "4",
      "--categories",
      "010",
      "--purity",
      "100",
      "--sorting",
      "favorites",
      "--order",
      "asc",
      "--page",
      "1",
      "--at-least",
      "3840x2160",
      "--colors",
      "0066cc"
    ]
  )
  const anyResolutionArgs = model.searchArguments("forest", 1, 2, {
    categories: "100",
    sorting: "relevance",
    atLeast: ""
  })
  assert.deepEqual(anyResolutionArgs.slice(-2), ["1", "forest"])
  assert.equal(anyResolutionArgs.includes("--at-least"), false)

  const blackPaletteArgs = model.searchArguments("", 1, 2, {
    colors: "000000"
  })
  assert.deepEqual(blackPaletteArgs.slice(-2), ["--colors", "000000"])
})

test("parses bounded Aether results into local-thumbnail carousel rows", () => {
  const parsed = model.parseSearchResponse(
    response([
      wallpaper("abc123"),
      wallpaper("abc123"),
      wallpaper("../bad"),
      wallpaper("def456", { thumbnailPath: "https://example.test/thumb.jpg" })
    ]),
    "/tmp"
  )

  assert.equal(parsed.error, "")
  assert.equal(parsed.rows.length, 2)
  assert.deepEqual(parsed.rows[0], {
    id: "abc123",
    filePath: "wallhaven:abc123",
    fileName: "wallhaven-abc123",
    thumbnailPath: "/tmp/aether/wallhaven-thumbs/abc123.jpg",
    displayName: "Wallhaven abc123",
    resolution: "2560x1440",
    category: "general",
    purity: "sfw",
    searchText: "abc123 2560x1440 general sfw"
  })
  assert.equal(parsed.rows[1].thumbnailPath, "")
  assert.deepEqual(parsed.meta, { currentPage: 1, lastPage: 4, total: 160 })
})

test("rejects invalid and unexpectedly large Aether responses", () => {
  assert.match(model.parseSearchResponse("{", "/tmp").error, /invalid/i)
  assert.match(model.parseSearchResponse(JSON.stringify({ data: [] }), "/tmp").error, /incomplete/i)
  const tooMany = Array.from({ length: 97 }, (_, index) => wallpaper("id" + index))
  assert.match(model.parseSearchResponse(response(tooMany), "/tmp").error, /too many/i)
  assert.match(
    model.parseSearchResponse(" ".repeat(4 * 1024 * 1024 + 1), "/tmp").error,
    /oversized/i
  )
})

test("drops records that do not preserve the SFW response contract", () => {
  const parsed = model.parseSearchResponse(
    response([
      wallpaper("safe"),
      wallpaper("unsafe", { purity: "nsfw" }),
      wallpaper("unknown", { category: "other" })
    ]),
    "/tmp"
  )

  assert.equal(parsed.error, "")
  assert.deepEqual(
    parsed.rows.map((row) => row.id),
    ["safe"]
  )
})

test("accepts previews only from Aether's thumbnail cache", () => {
  const parsePath = (thumbnailPath, cacheHome = "/home/alice/.cache") =>
    model.parseSearchResponse(response([wallpaper("abc123", { thumbnailPath })]), cacheHome).rows[0]
      .thumbnailPath

  assert.equal(
    parsePath("/home/alice/.cache/aether/wallhaven-thumbs/wallhaven-abc123.jpg"),
    "/home/alice/.cache/aether/wallhaven-thumbs/wallhaven-abc123.jpg"
  )
  assert.equal(parsePath("/home/alice/Pictures/private.jpg"), "")
  assert.equal(parsePath("/home/alice/.cache/aether/wallhaven-thumbs/../private.jpg"), "")
  assert.equal(
    parsePath("/srv/cache/aether/wallhaven-thumbs/abc123.webp", "/srv/cache"),
    "/srv/cache/aether/wallhaven-thumbs/abc123.webp"
  )
})

test("appends unique pages without mutating the inputs", () => {
  const first = [model.wallpaperRow(wallpaper("one"), "/tmp")]
  const second = [
    model.wallpaperRow(wallpaper("one"), "/tmp"),
    model.wallpaperRow(wallpaper("two"), "/tmp")
  ]

  assert.deepEqual(
    model.appendUniqueRows(first, second).map((row) => row.id),
    ["one", "two"]
  )
  assert.equal(first.length, 1)
  assert.equal(second.length, 2)
})

test("persists Wallhaven filters and upgrades Latest→Relevant for queries", () => {
  assert.equal(model.normalizeQuery("  neon   city  "), "neon city")
  assert.equal(model.filtersActive({}), false)
  assert.equal(model.filtersActive({ sorting: "views" }), true)
  assert.equal(model.filterActiveCount({ sorting: "views", colors: "0066cc" }), 2)

  const effective = model.effectiveSearchFilters("mountains", { sorting: "date_added" })
  assert.equal(effective.sorting, "relevance")
  assert.equal(model.effectiveSearchFilters("", { sorting: "date_added" }).sorting, "date_added")
  assert.equal(model.effectiveSearchFilters("mountains", { sorting: "favorites" }).sorting, "favorites")

  const args = model.searchArguments("city night", 1, 2, { sorting: "date_added" })
  assert.equal(args[args.indexOf("--sorting") + 1], "relevance")
  assert.equal(args.at(-1), "city night")

  const roundTrip = model.parseFilters(
    model.serializeFilters(
      {
        categories: "010",
        sorting: "favorites",
        order: "asc",
        atLeast: "3840x2160",
        colors: "0066cc"
      },
      " neon city "
    )
  )
  assert.deepEqual(roundTrip.filters, {
    categories: "010",
    sorting: "favorites",
    order: "asc",
    atLeast: "3840x2160",
    colors: "0066cc"
  })
  assert.equal(roundTrip.query, "neon city")
})

test("accepts downloads only from Aether's wallpaper directory", () => {
  const home = "/home/alice"
  assert.deepEqual(
    model.parseDownloadResponse(
      JSON.stringify({
        path: home + "/.local/share/aether/wallpapers/wallhaven-abc.jpg"
      }),
      home
    ),
    {
      error: "",
      path: home + "/.local/share/aether/wallpapers/wallhaven-abc.jpg"
    }
  )
  assert.match(
    model.parseDownloadResponse(JSON.stringify({ path: "/tmp/wallpaper.jpg" }), home).error,
    /unexpected/i
  )
  assert.deepEqual(
    model.parseDownloadResponse(
      JSON.stringify({ path: "/srv/data/aether/wallpapers/wallhaven-xyz.png" }),
      home,
      "/srv/data"
    ),
    { error: "", path: "/srv/data/aether/wallpapers/wallhaven-xyz.png" }
  )
  assert.deepEqual(model.downloadArguments("abc123"), [
    "aether",
    "--wallhaven-download",
    "abc123",
    "--json"
  ])
  assert.deepEqual(model.downloadArguments("../bad"), [])
  assert.deepEqual(model.downloadArguments("a".repeat(33)), [])
  assert.match(model.parseDownloadResponse(" ".repeat(8 * 1024 + 1), home).error, /oversized/i)
})
