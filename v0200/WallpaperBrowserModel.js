const maxQueryLength = 120
const maxWallpapersPerResponse = 96
const maxSearchResponseLength = 4 * 1024 * 1024
const maxDownloadResponseLength = 8 * 1024
const wallpaperIdPattern = /^[A-Za-z0-9]{1,32}$/
const imagePathPattern = /\.(?:jpe?g|png|webp)$/i
const categoryPattern = /^[01]{3}$/
const wallpaperCategories = ["general", "anime", "people"]
const sortingOptions = [
  { value: "date_added", label: "Latest" },
  { value: "relevance", label: "Relevant" },
  { value: "views", label: "Popular" },
  { value: "favorites", label: "Favorites" },
  { value: "toplist", label: "Top list" }
]
const resolutionOptions = [
  { value: "", label: "Any resolution" },
  { value: "1920x1080", label: "1080p+" },
  { value: "2560x1440", label: "1440p+" },
  { value: "3840x2160", label: "4K+" }
]
const orderOptions = [
  { value: "desc", label: "Descending" },
  { value: "asc", label: "Ascending" }
]
const colorOptions = [
  { value: "", label: "Any" },
  { value: "660000", label: "Red" },
  { value: "cc6633", label: "Orange" },
  { value: "ffcc33", label: "Yellow" },
  { value: "336600", label: "Green" },
  { value: "0066cc", label: "Blue" },
  { value: "663399", label: "Purple" },
  { value: "000000", label: "Black" },
  { value: "cccccc", label: "Gray" },
  { value: "ffffff", label: "White" }
]

const stringValue = (value) => String(value || "")
const integerValue = (value, fallback = 0) => {
  const number = Number(value)
  return Number.isSafeInteger(number) && number >= 0 ? number : fallback
}

const normalizeQuery = (query) =>
  stringValue(query)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxQueryLength)

const isWallpaperPickerDirs = (imageDirs) =>
  stringValue(imageDirs)
    .split("\n")
    .map((path) => path.replace(/\/+$/, ""))
    .some(
      (path) =>
        /\/omarchy\/current\/theme\/backgrounds$/.test(path) ||
        /\/\.config\/omarchy\/backgrounds\/[^/]+$/.test(path)
    )

const isWallpaperPickerRows = (rows) =>
  stringValue(rows)
    .split("\n")
    .map((row) => row.split("\t", 1)[0])
    .some(
      (path) =>
        /\/\.local\/state\/omarchy\/current\/theme\/backgrounds\/[^/]+$/.test(path) ||
        /\/\.config\/omarchy\/backgrounds\/[^/]+\/[^/]+$/.test(path)
    )

const isWallpaperPickerRequest = (imageDirs, rows) => {
  const rowText = stringValue(rows)
  return rowText ? isWallpaperPickerRows(rowText) : isWallpaperPickerDirs(imageDirs)
}

const optionForValue = (options, value) =>
  options.find((option) => option.value === stringValue(value))

const normalizeFilters = (filters) => {
  const input = filters && typeof filters === "object" ? filters : {}
  const categories = stringValue(input.categories)
  const sorting = stringValue(input.sorting)
  const order = stringValue(input.order)
  const atLeast = Object.prototype.hasOwnProperty.call(input, "atLeast")
    ? stringValue(input.atLeast)
    : "1920x1080"
  const colors = stringValue(input.colors).toLowerCase()

  return {
    categories: categoryPattern.test(categories) && categories !== "000" ? categories : "111",
    sorting: optionForValue(sortingOptions, sorting) ? sorting : "date_added",
    order: optionForValue(orderOptions, order) ? order : "desc",
    atLeast: optionForValue(resolutionOptions, atLeast) ? atLeast : "1920x1080",
    colors: optionForValue(colorOptions, colors) ? colors : ""
  }
}

const filterKey = (filters) => {
  const normalized = normalizeFilters(filters)
  return [
    normalized.categories,
    normalized.sorting,
    normalized.order,
    normalized.atLeast,
    normalized.colors
  ].join("|")
}

const toggleCategory = (categories, index) => {
  const current = normalizeFilters({ categories }).categories.split("")
  const normalizedIndex = integerValue(index, 3)
  if (normalizedIndex > 2) return current.join("")

  current[normalizedIndex] = current[normalizedIndex] === "1" ? "0" : "1"
  return current.every((value) => value === "0")
    ? normalizeFilters({ categories }).categories
    : current.join("")
}

const nextOptionValue = (options, value) => {
  const index = options.findIndex((option) => option.value === stringValue(value))
  return options[(index + 1 + options.length) % options.length].value
}

const nextSorting = (sorting) => nextOptionValue(sortingOptions, sorting)
const nextResolution = (atLeast) => nextOptionValue(resolutionOptions, atLeast)
const sortingLabel = (sorting) =>
  (optionForValue(sortingOptions, sorting) || sortingOptions[0]).label
const resolutionLabel = (atLeast) =>
  (optionForValue(resolutionOptions, atLeast) || resolutionOptions[1]).label
const colorLabel = (colors) =>
  (optionForValue(colorOptions, stringValue(colors).toLowerCase()) || colorOptions[0]).label
const categorySummary = (categories) => {
  const value = normalizeFilters({ categories }).categories
  if (value === "111") return "All categories"

  return ["General", "Anime", "People"]
    .filter((_label, index) => value.charAt(index) === "1")
    .join(" + ")
}
const filterSummary = (filters) => {
  const normalized = normalizeFilters(filters)
  const summary = [
    categorySummary(normalized.categories),
    sortingLabel(normalized.sorting) + (normalized.order === "desc" ? " ↓" : " ↑"),
    resolutionLabel(normalized.atLeast)
  ]
  if (normalized.colors) summary.push(colorLabel(normalized.colors) + " palette")
  return summary.join("  ·  ")
}

const defaultFilters = () => normalizeFilters({})

const filtersActive = (filters) => filterKey(filters) !== filterKey(defaultFilters())

const filterActiveCount = (filters) => {
  const normalized = normalizeFilters(filters)
  const defaults = defaultFilters()
  let count = 0
  if (normalized.categories !== defaults.categories) count += 1
  if (normalized.sorting !== defaults.sorting) count += 1
  if (normalized.order !== defaults.order) count += 1
  if (normalized.atLeast !== defaults.atLeast) count += 1
  if (normalized.colors !== defaults.colors) count += 1
  return count
}

// When typing a Wallhaven query, Latest (date_added) ranks poorly vs Relevant.
// Keep the user's stored sorting; only rewrite the outbound Aether request.
const effectiveSearchFilters = (query, filters) => {
  const normalized = normalizeFilters(filters)
  if (normalizeQuery(query) && normalized.sorting === "date_added") {
    normalized.sorting = "relevance"
  }
  return normalized
}

const serializeFilters = (filters, query = "") => {
  const serialized = normalizeFilters(filters)
  serialized.query = normalizeQuery(query)
  return JSON.stringify(serialized, null, 2) + "\n"
}

const parseFilters = (raw) => {
  try {
    const parsed = JSON.parse(stringValue(raw) || "{}")
    return {
      filters: normalizeFilters(parsed),
      query: normalizeQuery(parsed && parsed.query)
    }
  } catch (_error) {
    return { filters: defaultFilters(), query: "" }
  }
}
const cloneOptions = (options) =>
  options.map((option) => ({ value: option.value, label: option.label }))
const getSortingOptions = () => cloneOptions(sortingOptions)
const getResolutionOptions = () => cloneOptions(resolutionOptions)
const getColorOptions = () => cloneOptions(colorOptions)

const searchArguments = (query, page = 1, pages = 2, filters = {}) => {
  const normalizedFilters = effectiveSearchFilters(query, filters)
  const args = [
    "aether",
    "--wallhaven-thumbs",
    "--json",
    "--pages",
    String(Math.max(1, Math.min(4, integerValue(pages, 2)))),
    "--categories",
    normalizedFilters.categories,
    "--purity",
    "100",
    "--sorting",
    normalizedFilters.sorting,
    "--order",
    normalizedFilters.order,
    "--page",
    String(Math.max(1, integerValue(page, 1)))
  ]
  if (normalizedFilters.atLeast) args.push("--at-least", normalizedFilters.atLeast)
  if (normalizedFilters.colors) args.push("--colors", normalizedFilters.colors)
  const normalizedQuery = normalizeQuery(query)
  if (normalizedQuery) args.push(normalizedQuery)
  return args
}

const downloadArguments = (id) =>
  wallpaperIdPattern.test(stringValue(id))
    ? ["aether", "--wallhaven-download", stringValue(id), "--json"]
    : []

const safeThumbnailPath = (path, cacheHome) => {
  const value = stringValue(path)
  const cacheRoot = stringValue(cacheHome).replace(/\/+$/, "")
  const expectedPrefix = cacheRoot + "/aether/wallhaven-thumbs/"
  const fileName = value.slice(expectedPrefix.length)
  return cacheRoot.startsWith("/") &&
    value.startsWith(expectedPrefix) &&
    !fileName.includes("/") &&
    !value.includes("\u0000") &&
    imagePathPattern.test(value)
    ? value
    : ""
}

const wallpaperRow = (wallpaper, cacheHome) => {
  if (!wallpaper || typeof wallpaper !== "object") return null

  const id = stringValue(wallpaper.id)
  if (!wallpaperIdPattern.test(id)) return null

  const resolution = stringValue(wallpaper.resolution).slice(0, 32)
  const category = stringValue(wallpaper.category).slice(0, 24)
  const purity = stringValue(wallpaper.purity).slice(0, 24)
  if (!wallpaperCategories.includes(category) || purity !== "sfw") return null
  const thumbnailPath = safeThumbnailPath(wallpaper.thumbnailPath, cacheHome)

  return {
    id,
    filePath: "wallhaven:" + id,
    fileName: "wallhaven-" + id,
    thumbnailPath,
    displayName: "Wallhaven " + id,
    resolution,
    category,
    purity,
    searchText: [id, resolution, category, purity].filter(Boolean).join(" ")
  }
}

const parseSearchResponse = (text, cacheHome) => {
  const responseText = stringValue(text)
  if (responseText.length > maxSearchResponseLength) {
    return {
      error: "Aether returned an oversized Wallhaven response",
      rows: [],
      meta: {}
    }
  }

  let payload
  try {
    payload = JSON.parse(responseText)
  } catch (_error) {
    return {
      error: "Aether returned an invalid Wallhaven response",
      rows: [],
      meta: {}
    }
  }

  if (!payload || typeof payload !== "object" || !Array.isArray(payload.wallpapers)) {
    return {
      error: "Aether returned an incomplete Wallhaven response",
      rows: [],
      meta: {}
    }
  }
  if (payload.wallpapers.length > maxWallpapersPerResponse) {
    return {
      error: "Aether returned too many Wallhaven records",
      rows: [],
      meta: {}
    }
  }

  const seen = {}
  const rows = payload.wallpapers.reduce((result, wallpaper) => {
    const row = wallpaperRow(wallpaper, cacheHome)
    if (!row || seen[row.id]) return result
    seen[row.id] = true
    result.push(row)
    return result
  }, [])
  const meta = payload.meta && typeof payload.meta === "object" ? payload.meta : {}

  return {
    error: "",
    rows,
    meta: {
      currentPage: integerValue(meta.current_page),
      lastPage: integerValue(meta.last_page),
      total: integerValue(meta.total)
    }
  }
}

const appendUniqueRows = (existingRows, incomingRows) => {
  const combined = []
  const seen = {}

  const rows = (Array.isArray(existingRows) ? existingRows : []).concat(
    Array.isArray(incomingRows) ? incomingRows : []
  )
  for (const row of rows) {
    const id = stringValue(row && row.id)
    if (!wallpaperIdPattern.test(id) || seen[id]) continue
    seen[id] = true
    combined.push(row)
  }
  return combined
}

const parseDownloadResponse = (text, homeDir, dataHome) => {
  const responseText = stringValue(text)
  if (responseText.length > maxDownloadResponseLength) {
    return {
      error: "Aether returned an oversized download response",
      path: ""
    }
  }

  let payload
  try {
    payload = JSON.parse(responseText)
  } catch (_error) {
    return { error: "Aether returned an invalid download response", path: "" }
  }

  const home = stringValue(homeDir).replace(/\/+$/, "")
  const dataRoot = (stringValue(dataHome) || home + "/.local/share").replace(/\/+$/, "")
  const path = stringValue(payload && payload.path)
  const expectedPrefix = dataRoot + "/aether/wallpapers/"
  if (
    !home.startsWith("/") ||
    !dataRoot.startsWith("/") ||
    !path.startsWith(expectedPrefix) ||
    path.slice(expectedPrefix.length).includes("/") ||
    path.includes("\u0000") ||
    !imagePathPattern.test(path)
  ) {
    return { error: "Aether returned an unexpected wallpaper path", path: "" }
  }

  return { error: "", path }
}

const errorFromStderr = (stderr, fallback) => {
  const firstLine = stringValue(stderr)
    .split("\n")
    .map((line) => line.trim())
    .find(Boolean)
  return (firstLine || fallback || "Aether could not complete the Wallhaven request").slice(0, 240)
}

if (typeof module !== "undefined") {
  module.exports = {
    maxQueryLength,
    normalizeQuery,
    isWallpaperPickerDirs,
    isWallpaperPickerRows,
    isWallpaperPickerRequest,
    normalizeFilters,
    filterKey,
    toggleCategory,
    nextSorting,
    nextResolution,
    sortingLabel,
    resolutionLabel,
    colorLabel,
    categorySummary,
    filterSummary,
    defaultFilters,
    filtersActive,
    filterActiveCount,
    effectiveSearchFilters,
    serializeFilters,
    parseFilters,
    getSortingOptions,
    getResolutionOptions,
    getColorOptions,
    searchArguments,
    downloadArguments,
    wallpaperRow,
    parseSearchResponse,
    appendUniqueRows,
    parseDownloadResponse,
    errorFromStderr
  }
}
