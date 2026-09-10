const test = require("node:test")
const assert = require("node:assert/strict")

const model = require("../v0200/ThemeCatalogModel.js")

test("normalizes supported GitHub repository URL variants", () => {
  const expected = "https://github.com/example/omarchy-night-theme"

  assert.equal(
    model.normalizeRepositoryUrl("https://GitHub.com/Example/Omarchy-Night-Theme.git/"),
    expected
  )
  assert.equal(
    model.normalizeRepositoryUrl("git@github.com:Example/Omarchy-Night-Theme.git"),
    expected
  )
  assert.equal(
    model.normalizeRepositoryUrl("git://github.com/Example/Omarchy-Night-Theme"),
    expected
  )
  assert.equal(model.normalizeRepositoryUrl("https://gitlab.com/example/theme"), "")
  assert.equal(model.normalizeRepositoryUrl("https://github.com/example/repo/tree/main"), "")
})

test("derives the same destination slug as the Omarchy installer", () => {
  assert.equal(
    model.installSlugForRepositoryUrl("https://github.com/example/omarchy-amberbyte-theme.git"),
    "amberbyte"
  )
  assert.equal(model.installSlugForRepositoryUrl("https://github.com/example/aetheria"), "aetheria")
  assert.equal(model.isSafeThemeSlug("theme.v2"), true)
  assert.equal(model.isSafeThemeSlug("../outside"), false)
})

test("deduplicates by canonical repository instead of display name", () => {
  const rows = model.catalogRows({
    officialRepositories: ["https://github.com/example/omarchy-night-theme"],
    themes: [
      {
        name: "Night",
        repositoryUrl: "https://github.com/Example/Omarchy-Night-Theme.git",
        stars: 4
      },
      {
        name: "Night Theme",
        repositoryUrl: "git@github.com:example/omarchy-night-theme.git",
        stars: 9
      },
      {
        name: "Night",
        repositoryUrl: "https://github.com/another/night-theme"
      }
    ]
  })

  assert.equal(rows.length, 2)
  assert.equal(rows[0].official, true)
  assert.equal(rows[0].stars, 9)
  assert.equal(rows[1].repositoryUrl, "https://github.com/another/night-theme")
})

test("blocks installed repositories and stock-slug collisions", () => {
  const payload = {
    themes: [
      {
        name: "Installed elsewhere",
        repositoryUrl: "https://github.com/example/omarchy-installed-theme"
      },
      {
        name: "Miasma fork",
        repositoryUrl: "https://github.com/example/omarchy-miasma-theme"
      },
      {
        name: "Fresh",
        repositoryUrl: "https://github.com/example/omarchy-fresh-theme"
      }
    ]
  }

  const rows = model.catalogRows(payload, {
    installedThemes: {},
    installedRepositories: ["git@github.com:example/omarchy-installed-theme.git"],
    stockThemes: { miasma: true }
  })

  const bySlug = Object.fromEntries(rows.map((row) => [row.installSlug, row]))
  assert.equal(bySlug.installed.installed, true)
  assert.equal(bySlug.installed.reviewable, false)
  assert.equal(bySlug.miasma.stockConflict, true)
  assert.equal(bySlug.miasma.reviewable, false)
  assert.equal(bySlug.fresh.reviewable, true)
})

test("sanitizes remote display values and allowlists GitHub preview hosts", () => {
  assert.equal(model.plainTextValue("<b>Night</b>\nTheme"), "b Night /b Theme")
  assert.deepEqual(model.parsedArray("not-json"), [])
  assert.equal(
    model.safePreviewUrl("https://raw.githubusercontent.com/example/theme/main/preview.png"),
    "https://raw.githubusercontent.com/example/theme/main/preview.png"
  )
  assert.equal(
    model.safePreviewUrl(
      "https://github.com/user-attachments/assets/f0b6952e-c436-4c03-b496-0ecc6679210a"
    ),
    "https://github.com/user-attachments/assets/f0b6952e-c436-4c03-b496-0ecc6679210a"
  )
  assert.equal(model.safePreviewUrl("https://example.com/preview.png"), "")
  assert.equal(model.safePreviewUrl("https://raw.githubusercontent.com.evil/preview.png"), "")
  assert.equal(model.safePreviewUrl("https://github.com/example/theme/blob/main/preview.png"), "")
  assert.equal(model.safePreviewUrl("file:///etc/passwd"), "")
  assert.equal(
    model.safePreviewUrl("https://raw.githubusercontent.com/example/theme/main/a b.png"),
    ""
  )
})

test("keeps catalog notes as bounded discovery metadata", () => {
  const [row] = model.catalogRows({
    officialRepositories: ["https://github.com/example/omarchy-safe-theme"],
    themes: [
      {
        name: "Safe",
        owner: "example",
        repositoryUrl: "https://github.com/example/omarchy-safe-theme",
        securityWarnings: '["installs an editor <extension>"]'
      }
    ]
  })

  assert.equal(row.status, "Review source")
  assert.equal(row.reviewable, true)
  assert.deepEqual(row.warnings, ["installs an editor extension"])
  assert.equal("canInstall" in row, false)
})

test("sorts reviewable themes ahead of blocked catalog entries", () => {
  const rows = model.catalogRows(
    {
      officialRepositories: [
        "https://github.com/example/omarchy-blocked-theme",
        "https://github.com/example/omarchy-fresh-theme"
      ],
      themes: [
        {
          name: "Blocked",
          repositoryUrl: "https://github.com/example/omarchy-blocked-theme",
          stars: 100
        },
        {
          name: "Fresh",
          repositoryUrl: "https://github.com/example/omarchy-fresh-theme",
          stars: 1
        }
      ]
    },
    { stockThemes: { blocked: true } }
  )

  assert.equal(rows[0].installSlug, "fresh")
  assert.equal(rows[1].installSlug, "blocked")
})

test("filters and sorts theme catalog rows locally", () => {
  const rows = [
    {
      displayName: "Zebra",
      official: true,
      installed: false,
      stockConflict: false,
      reviewable: true,
      stars: 12
    },
    {
      displayName: "Alpha",
      official: false,
      installed: true,
      stockConflict: false,
      reviewable: false,
      stars: 80
    },
    {
      displayName: "Conflict",
      official: false,
      installed: false,
      stockConflict: true,
      reviewable: false,
      stars: 5
    }
  ]

  assert.equal(model.itemMatchesCatalogFilters(rows[0], { listing: "official" }), true)
  assert.equal(model.itemMatchesCatalogFilters(rows[1], { listing: "official" }), false)
  assert.equal(model.itemMatchesCatalogFilters(rows[1], { availability: "installed" }), true)
  assert.equal(model.itemMatchesCatalogFilters(rows[2], { availability: "conflicts" }), true)
  assert.equal(model.itemMatchesCatalogFilters(rows[2], { minStars: 10 }), false)

  const officialReviewable = model.applyCatalogFilters(rows, {
    listing: "official",
    availability: "reviewable",
    sort: "best",
    minStars: 0
  })
  assert.deepEqual(
    officialReviewable.map((row) => row.displayName),
    ["Zebra"]
  )

  const byStars = model.applyCatalogFilters(rows, { sort: "stars", minStars: 10 })
  assert.deepEqual(
    byStars.map((row) => row.displayName),
    ["Alpha", "Zebra"]
  )

  const byName = model.applyCatalogFilters(rows, { sort: "name" })
  assert.deepEqual(
    byName.map((row) => row.displayName),
    ["Alpha", "Conflict", "Zebra"]
  )

  assert.equal(
    model.catalogFilterSummary({
      listing: "official",
      availability: "reviewable",
      sort: "stars",
      minStars: 10
    }),
    "Official  ·  Reviewable  ·  Stars ↓  ·  10+"
  )
  assert.equal(model.catalogFiltersActive({}), false)
  assert.equal(model.catalogFiltersActive({ listing: "community" }), true)
  assert.deepEqual(
    model.parseCatalogFilters(
      model.serializeCatalogFilters({ listing: "community", minStars: 50 })
    ),
    {
      listing: "community",
      availability: "all",
      sort: "best",
      minStars: 50
    }
  )
})
