const test = require("node:test")
const assert = require("node:assert/strict")

const model = require("../v0200/ImagePickerModel.js")

const images = [
  { filePath: "/cache/amber-byte.png" },
  { filePath: "/cache/catppuccin_mocha.jpg" },
  { filePath: "/cache/tokyo-night.png" },
  {
    filePath: "https://github.com/example/omarchy-van-gogh-theme",
    displayName: "Van Gogh",
    searchText: "van gogh starry night art",
    installSlug: "van-gogh"
  },
  {
    filePath: "https://github.com/example/omarchy-aether-theme",
    displayName: "Aether",
    searchText: "aether soft glow",
    installSlug: "aether"
  }
]

test("derives stable names and readable labels from image paths", () => {
  assert.equal(model.nameForPath("/cache/amber-byte.png"), "amber-byte")
  assert.equal(model.labelForPath("/cache/catppuccin_mocha.jpg"), "Catppuccin Mocha")
  assert.equal(model.nameForPath(), "")
})

test("loads tab-separated rows and keeps the first duplicate filename", () => {
  const rows = [
    "/themes/a/preview.png\t/cache/a.png",
    "/themes/b/preview.png\t/cache/b.png",
    "/themes/c/unique.jpg"
  ].join("\n")

  assert.deepEqual(model.loadRows(rows), [
    {
      filePath: "/themes/a/preview.png",
      fileName: "preview.png",
      thumbnailPath: "/cache/a.png"
    },
    {
      filePath: "/themes/c/unique.jpg",
      fileName: "unique.jpg",
      thumbnailPath: "/themes/c/unique.jpg"
    }
  ])
})

test("filters by raw names and human-readable labels", () => {
  assert.equal(model.itemMatches(images, 0, "amber"), true)
  assert.equal(model.itemMatches(images, 1, "mocha"), true)
  assert.equal(model.itemMatches(images, 2, "cat"), false)
  assert.equal(model.itemMatches(images, -1, ""), false)
  assert.equal(model.firstMatchingIndex(images, "night"), 2)
  assert.equal(model.firstMatchingIndex(images, "missing"), -1)
})

test("filters catalog rows by display metadata", () => {
  const catalog = [
    {
      filePath: "https://github.com/example/omarchy-night-theme",
      displayName: "Midnight Harbor",
      searchText: "midnight harbor example blue terminal"
    }
  ]

  assert.equal(model.itemMatches(catalog, 0, "harbor"), true)
  assert.equal(model.itemMatches(catalog, 0, "terminal"), true)
  assert.equal(model.itemMatches(catalog, 0, "amber"), false)
})

test("normalizes hyphens/underscores and matches unordered tokens", () => {
  assert.equal(model.normalizeSearchText("Van-Gogh"), "van gogh")
  assert.equal(model.compactSearchText("van-gogh"), "vangogh")
  assert.equal(model.itemMatches(images, 3, "vangogh"), true)
  assert.equal(model.itemMatches(images, 3, "gogh van"), true)
  assert.equal(model.itemMatches(images, 3, "starry gogh"), true)
  assert.equal(model.itemMatches(images, 3, "starry amber"), false)
  assert.equal(model.itemMatches(images, 1, "catppuccin mocha"), true)
  assert.equal(model.itemMatches(images, 1, "mocha catppuccin"), true)
})

test("supports light fuzzy token matching", () => {
  assert.equal(model.isSubsequence("athr", "aether"), true)
  assert.equal(model.levenshteinAtMost("aether", "aeter", 1), true)
  assert.equal(model.levenshteinAtMost("aether", "xyz", 1), false)
  assert.equal(model.itemMatches(images, 4, "athr"), true)
  assert.equal(model.itemMatches(images, 4, "aeter"), true)
  assert.equal(model.itemMatches(images, 4, "xyz"), false)
  assert.equal(model.textMatches("Tokyo Night", ""), true)
})

test("calculates filtered carousel positions without mutating rows", () => {
  const source = images.slice()

  assert.equal(model.filteredPosition(images, 2, "a"), 2)
  assert.equal(model.selectedFilteredPosition(images, 2, "a"), 0)
  assert.equal(model.selectedFilteredPosition(images, 2, "mocha"), 0)
  assert.deepEqual(images, source)
})

test("selects the requested image and falls back predictably", () => {
  assert.equal(model.indexForSelectedImage(images, "/cache/catppuccin_mocha.jpg"), 1)
  assert.equal(model.indexForSelectedImage(images, "/cache/missing.png"), 0)
  assert.equal(model.nextSelectedIndexForFilter(images, 2, "mocha"), 1)
  assert.equal(model.nextSelectedIndexForFilter(images, 1, "mocha"), 1)
})

test("supports soft multi-word and compact fuzzy matches", () => {
  assert.equal(model.itemMatches(images, 3, "van gogh art"), true)
  assert.equal(model.itemMatches(images, 3, "vangoghstarry"), true)
  assert.equal(model.itemMatches(images, 1, "catpuccin mocha"), true)
  assert.equal(model.itemMatches(images, 4, "aether soft"), true)
  assert.equal(model.textMatches("Matte Black Theme", "matte blak"), true)
  assert.equal(model.textMatches("Tokyo Night Storm", "tokyo strom night"), true)
})
