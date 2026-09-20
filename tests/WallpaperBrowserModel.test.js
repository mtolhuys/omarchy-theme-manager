const test = require("node:test")
const assert = require("node:assert/strict")
const { dirname, join } = require("node:path")

const manifest = require("../manifest.json")
const runtimeDir = dirname(manifest.entryPoints.overlay)
const model = require(join("..", runtimeDir, "WallpaperBrowserModel.js"))

const response = (wallpapers, meta = {}) =>
  JSON.stringify({
    wallpapers,
    meta: { current_page: 1, last_page: 4, total: 160, ...meta }
  })

const wallpaper = (id, overrides = {}) => ({
  id: "ocs-" + id,
  title: "Aurora Abstract 4K",
  resolution: "3840x2160",
  collection: "community-abstract",
  source: "OpenDesktop community",
  license: "CC BY",
  author: "Example artist",
  url: "https://www.opendesktop.org/p/" + id,
  thumbnailPath: "/tmp/aether/wallpaper-thumbs/ocs-" + id + ".jpg",
  ...overrides
})

test("recognizes only Omarchy background-picker requests", () => {
  assert.equal(
    model.isWallpaperPickerDirs("/home/alice/.local/state/omarchy/current/theme/backgrounds"),
    true
  )
  assert.equal(model.isWallpaperPickerDirs("/home/alice/Pictures"), false)
  assert.equal(
    model.isWallpaperPickerRows(
      "/home/alice/.config/omarchy/backgrounds/miasma/two.png\t/tmp/two.jpg"
    ),
    true
  )
  assert.equal(
    model.isWallpaperPickerRequest(
      "/home/alice/.local/state/omarchy/current/theme/backgrounds",
      "/home/alice/.cache/omarchy/theme-selector/previews/miasma.png\t/tmp/miasma.jpg"
    ),
    false
  )
})

test("builds bounded Aether open-wallpaper arguments", () => {
  assert.deepEqual(
    model.searchArguments("solar punk", 3, 2, {
      collection: "community-dark",
      sorting: "newest",
      license: "public-domain"
    }),
    [
      "aether",
      "--wallpaper-thumbs",
      "--json",
      "--pages",
      "2",
      "--collection",
      "community-dark",
      "--sorting",
      "newest",
      "--license",
      "public-domain",
      "--page",
      "3",
      "solar punk"
    ]
  )
  assert.equal(model.searchArguments("a; touch /tmp/nope").at(-1), "a; touch /tmp/nope")
  assert.equal(model.normalizeQuery("night\ncity\u0000"), "night city")
})

test("normalizes only filters that the open catalog supports", () => {
  assert.deepEqual(model.normalizeFilters({}), {
    collection: "omarchy",
    sorting: "featured",
    license: "any"
  })
  assert.deepEqual(
    model.normalizeFilters({
      collection: "community-space",
      sorting: "popular",
      license: "share-alike"
    }),
    { collection: "community-space", sorting: "popular", license: "share-alike" }
  )
  assert.deepEqual(model.normalizeFilters({ collection: "anime", sorting: "popular" }), {
    collection: "omarchy",
    sorting: "featured",
    license: "any"
  })
  assert.equal(model.collectionLabel("community-neon"), "Neon")
  assert.equal(model.filterSummary({ collection: "omarchy" }), "Bundled Omarchy collection")
  assert.equal(model.nextSorting("newest"), "featured")
  assert.equal(model.licenseLabel("public-domain"), "Public domain / CC0")
  assert.equal(
    model.filterSummary({
      collection: "community-minimal",
      sorting: "newest",
      license: "attribution"
    }),
    "Community: Minimal  ·  Newest  ·  Attribution"
  )
})

test("exposes defensive copies of all filter choices", () => {
  assert.deepEqual(
    model.getCollectionOptions().map((option) => option.value),
    [
      "omarchy",
      "community-abstract",
      "community-minimal",
      "community-dark",
      "community-space",
      "community-neon",
      "photography"
    ]
  )
  assert.deepEqual(
    model.getSortingOptions().map((option) => option.value),
    ["featured", "popular", "newest"]
  )
  assert.deepEqual(
    model.getLicenseOptions().map((option) => option.value),
    ["any", "public-domain", "attribution", "share-alike"]
  )
  const collections = model.getCollectionOptions()
  collections[0].label = "Changed"
  assert.equal(model.getCollectionOptions()[0].label, "Omarchy")
})

test("parses open catalog metadata into safe carousel rows", () => {
  const parsed = model.parseSearchResponse(
    response([
      wallpaper("123"),
      wallpaper("123"),
      wallpaper("bad-id"),
      wallpaper("456", { thumbnailPath: "https://example.test/thumb.jpg" })
    ]),
    "/tmp"
  )
  assert.equal(parsed.error, "")
  assert.equal(parsed.rows.length, 2)
  assert.deepEqual(parsed.rows[0], {
    id: "ocs-123",
    filePath: "wallpaper:ocs-123",
    fileName: "ocs-123",
    thumbnailPath: "/tmp/aether/wallpaper-thumbs/ocs-123.jpg",
    displayName: "Aurora Abstract 4K",
    resolution: "3840x2160",
    category: "Abstract",
    collection: "community-abstract",
    license: "CC BY",
    author: "Example artist",
    source: "OpenDesktop community",
    sourceURL: "https://www.opendesktop.org/p/123",
    searchText:
      "Aurora Abstract 4K 3840x2160 community-abstract CC BY Example artist OpenDesktop community"
  })
  assert.equal(parsed.rows[1].thumbnailPath, "")
  assert.deepEqual(parsed.meta, { currentPage: 1, lastPage: 4, total: 160, stale: false })
})

test("marks cached fallback results and rejects malformed payloads", () => {
  assert.equal(model.parseSearchResponse(response([], { stale: true }), "/tmp").meta.stale, true)
  assert.match(model.parseSearchResponse("{", "/tmp").error, /invalid/i)
  assert.match(model.parseSearchResponse(JSON.stringify({ data: [] }), "/tmp").error, /incomplete/i)
  const tooMany = Array.from({ length: 97 }, (_, index) => wallpaper(String(index + 1)))
  assert.match(model.parseSearchResponse(response(tooMany), "/tmp").error, /too many/i)
  assert.match(
    model.parseSearchResponse(" ".repeat(4 * 1024 * 1024 + 1), "/tmp").error,
    /oversized/i
  )
})

test("drops records without a known collection, provider-scoped id, or license", () => {
  const parsed = model.parseSearchResponse(
    response([
      wallpaper("100"),
      wallpaper("101", { collection: "unknown" }),
      wallpaper("102", { license: "" }),
      wallpaper("103", { id: "../bad" })
    ]),
    "/tmp"
  )
  assert.deepEqual(
    parsed.rows.map((row) => row.id),
    ["ocs-100"]
  )
})

test("accepts previews only from Aether's wallpaper thumbnail cache", () => {
  const parsePath = (thumbnailPath, cacheHome = "/home/alice/.cache") =>
    model.parseSearchResponse(response([wallpaper("123", { thumbnailPath })]), cacheHome).rows[0]
      .thumbnailPath
  assert.equal(
    parsePath("/home/alice/.cache/aether/wallpaper-thumbs/ocs-123.jpg"),
    "/home/alice/.cache/aether/wallpaper-thumbs/ocs-123.jpg"
  )
  assert.equal(parsePath("/home/alice/Pictures/private.jpg"), "")
  assert.equal(parsePath("/home/alice/.cache/aether/wallpaper-thumbs/../private.jpg"), "")
})

test("persists all open-catalog filters and the sticky query", () => {
  assert.equal(model.filtersActive({}), false)
  assert.equal(
    model.filterActiveCount({
      collection: "community-neon",
      sorting: "newest",
      license: "share-alike"
    }),
    3
  )
  const roundTrip = model.parseFilters(
    model.serializeFilters(
      {
        collection: "community-neon",
        sorting: "popular",
        license: "public-domain"
      },
      " forest canopy "
    )
  )
  assert.deepEqual(roundTrip.filters, {
    collection: "community-neon",
    sorting: "popular",
    license: "public-domain"
  })
  assert.equal(roundTrip.query, "forest canopy")
})

test("maps wallpaper-provider failures without blaming Aether's version", () => {
  assert.equal(
    model.processError(
      JSON.stringify({ error: "Wallpaper search failed: wallpaper provider returned HTTP 503" }),
      "",
      "fallback"
    ),
    "The wallpaper catalog is temporarily unavailable (HTTP 503). Cached results will be used when available."
  )
  assert.equal(
    model.processError(
      JSON.stringify({ error: "Wallpaper search failed: wallpaper provider returned HTTP 429" }),
      "",
      "fallback"
    ),
    "The wallpaper catalog is rate limiting requests. Try again shortly."
  )
  assert.equal(
    model.processError(
      JSON.stringify({ error: "resolve remote host: Temporary failure in name resolution" }),
      "",
      "fallback"
    ),
    "The wallpaper catalog could not be reached. Check your connection and retry."
  )
})

test("accepts downloads only from Aether's wallpaper directory", () => {
  const home = "/home/alice"
  assert.deepEqual(
    model.parseDownloadResponse(
      JSON.stringify({ path: home + "/.local/share/aether/wallpapers/commons-123.jpg" }),
      home
    ),
    { error: "", path: home + "/.local/share/aether/wallpapers/commons-123.jpg" }
  )
  assert.match(
    model.parseDownloadResponse(JSON.stringify({ path: "/tmp/wallpaper.jpg" }), home).error,
    /unexpected/i
  )
  assert.deepEqual(model.downloadArguments("ocs-123"), [
    "aether",
    "--wallpaper-download",
    "ocs-123",
    "--json"
  ])
  assert.deepEqual(model.downloadArguments("omarchy-8342267563586712271"), [
    "aether",
    "--wallpaper-download",
    "omarchy-8342267563586712271",
    "--json"
  ])
  assert.deepEqual(model.downloadArguments("../bad"), [])
})
