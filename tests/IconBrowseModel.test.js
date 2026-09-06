const test = require("node:test")
const assert = require("node:assert/strict")

const model = require("../v0200/IconBrowseModel.js")

test("normalizes icon browse filters and query", () => {
  assert.deepEqual(model.normalizeFilters({ sorting: "down" }), { sorting: "down" })
  assert.deepEqual(model.normalizeFilters({ sorting: "nope" }), { sorting: "new" })
  assert.equal(model.filterSummary({ sorting: "high" }), "Score")
  assert.equal(model.normalizeQuery("  papirus\u0000icons  ").trim(), "papirus icons")
})

test("builds helper search and install arguments", () => {
  assert.deepEqual(
    model.searchArguments("/tmp/icons-browse.sh", "tela", 2, { sorting: "down" }, 24),
    [
      "/tmp/icons-browse.sh",
      "search",
      "--sort",
      "down",
      "--page",
      "2",
      "--pagesize",
      "24",
      "--query",
      "tela"
    ]
  )
  assert.deepEqual(model.installArguments("/tmp/icons-browse.sh", "1305251"), [
    "/tmp/icons-browse.sh",
    "install",
    "1305251"
  ])
  assert.deepEqual(model.installArguments("/tmp/icons-browse.sh", "../evil"), [])
})

test("parses OCS search rows with allowlisted previews only", () => {
  const parsed = model.parseSearchResponse(
    JSON.stringify({
      page: 0,
      pagesize: 24,
      totalitems: 100,
      items: [
        {
          id: "1305251",
          name: "Candy icons",
          summary: "Sweet icons",
          downloads: 10,
          score: 96,
          previewUrl: "https://images.pling.com/cache/770x540-4/img/candy.png",
          downloadName: "candy.tar.gz"
        },
        {
          id: "2",
          name: "Bad preview",
          previewUrl: "https://evil.example/x.png"
        }
      ]
    })
  )

  assert.equal(parsed.error, "")
  assert.equal(parsed.rows.length, 2)
  assert.equal(
    parsed.rows[0].thumbnailPath,
    "https://images.pling.com/cache/770x540-4/img/candy.png"
  )
  assert.equal(parsed.rows[1].thumbnailPath, "")
  assert.equal(parsed.meta.hasMore, true)
})

test("parses install response and builds confirmation copy", () => {
  const parsed = model.parseInstallResponse(
    JSON.stringify({
      themeName: "Candy",
      themeNames: ["Candy", "Candy-dark"],
      iconsRoot: "/home/x/.local/share/icons"
    })
  )
  assert.equal(parsed.themeName, "Candy")
  assert.deepEqual(parsed.themeNames, ["Candy", "Candy-dark"])
  assert.match(
    model.installConfirmationMessage({ displayName: "Candy", downloadName: "candy.tar.gz" }),
    /Download and install/
  )
})
