const maxQueryLength = 120
const maxWallpapersPerResponse = 96
const maxSearchResponseLength = 4 * 1024 * 1024
const maxDownloadResponseLength = 8 * 1024
const wallpaperIdPattern = /^(?:omarchy|ocs|commons)-[0-9]{1,20}$/
const imagePathPattern = /\.(?:jpe?g|png|webp)$/i

const collectionOptions = [
  { value: "omarchy", label: "Omarchy" },
  { value: "community-abstract", label: "Abstract" },
  { value: "community-minimal", label: "Minimal" },
  { value: "community-dark", label: "Dark" },
  { value: "community-space", label: "Space" },
  { value: "community-neon", label: "Neon" },
  { value: "photography", label: "Photos" }
]
const sortingOptions = [
  { value: "featured", label: "Featured" },
  { value: "popular", label: "Popular" },
  { value: "newest", label: "Newest" }
]
const licenseOptions = [
  { value: "any", label: "Any open license" },
  { value: "public-domain", label: "Public domain / CC0" },
  { value: "attribution", label: "Attribution" },
  { value: "share-alike", label: "ShareAlike" }
]

const stringValue = (value) => String(value || "")
const integerValue = (value, fallback = 0) => {
  const number = Number(value)
  return Number.isSafeInteger(number) && number >= 0 ? number : fallback
}
const optionForValue = (options, value) =>
  options.find((option) => option.value === stringValue(value))
const optionOrDefault = (options, value, fallback) =>
  optionForValue(options, value) ? value : fallback
const cloneOptions = (options) =>
  options.map((option) => ({ value: option.value, label: option.label }))

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

const normalizeFilters = (filters) => {
  const input = filters && typeof filters === "object" ? filters : {}
  const collection = optionOrDefault(collectionOptions, stringValue(input.collection), "omarchy")
  if (collection === "omarchy") {
    return { collection, sorting: "featured", license: "any" }
  }
  return {
    collection,
    sorting: optionOrDefault(sortingOptions, stringValue(input.sorting), "featured"),
    license: optionOrDefault(licenseOptions, stringValue(input.license), "any")
  }
}

const filterKey = (filters) => {
  const normalized = normalizeFilters(filters)
  return [normalized.collection, normalized.sorting, normalized.license].join("|")
}

const nextOptionValue = (options, value) => {
  const index = options.findIndex((option) => option.value === stringValue(value))
  return options[(index + 1 + options.length) % options.length].value
}
const optionLabel = (options, value, fallbackIndex = 0) =>
  (optionForValue(options, value) || options[fallbackIndex]).label
const nextSorting = (sorting) => nextOptionValue(sortingOptions, sorting)
const collectionLabel = (collection) => optionLabel(collectionOptions, collection)
const sortingLabel = (sorting) => optionLabel(sortingOptions, sorting)
const licenseLabel = (license) => optionLabel(licenseOptions, license)

const filterSummary = (filters) => {
  const normalized = normalizeFilters(filters)
  if (normalized.collection === "omarchy") return "Bundled Omarchy collection"
  return [
    normalized.collection === "photography"
      ? collectionLabel(normalized.collection)
      : `Community: ${collectionLabel(normalized.collection)}`,
    sortingLabel(normalized.sorting),
    licenseLabel(normalized.license)
  ].join("  ·  ")
}

const defaultFilters = () => normalizeFilters({})
const filtersActive = (filters) => filterKey(filters) !== filterKey(defaultFilters())
const filterActiveCount = (filters) => {
  const normalized = normalizeFilters(filters)
  const defaults = defaultFilters()
  return ["collection", "sorting", "license"].reduce(
    (count, key) => count + (normalized[key] !== defaults[key] ? 1 : 0),
    0
  )
}

const serializeFilters = (filters, query = "") => {
  const serialized = normalizeFilters(filters)
  serialized.query = normalizeQuery(query)
  return JSON.stringify(serialized, null, 2) + "\n"
}

const parseFilters = (raw) => {
  try {
    const parsed = JSON.parse(stringValue(raw) || "{}")
    return { filters: normalizeFilters(parsed), query: normalizeQuery(parsed && parsed.query) }
  } catch (_error) {
    return { filters: defaultFilters(), query: "" }
  }
}

const getCollectionOptions = () => cloneOptions(collectionOptions)
const getSortingOptions = () => cloneOptions(sortingOptions)
const getLicenseOptions = () => cloneOptions(licenseOptions)
const boundedPages = (pages) => String(Math.max(1, Math.min(4, integerValue(pages, 2))))
const boundedPage = (page) => String(Math.max(1, integerValue(page, 1)))

const searchArguments = (query, page = 1, pages = 2, filters = {}) => {
  const normalized = normalizeFilters(filters)
  const args = [
    "wallpaper-catalog",
    "--wallpaper-thumbs",
    "--json",
    "--pages",
    boundedPages(pages),
    "--collection",
    normalized.collection,
    "--sorting",
    normalized.sorting,
    "--license",
    normalized.license,
    "--page",
    boundedPage(page)
  ]
  const normalizedQuery = normalizeQuery(query)
  if (normalizedQuery) args.push(normalizedQuery)
  return args
}

const downloadArguments = (id) =>
  wallpaperIdPattern.test(stringValue(id))
    ? ["wallpaper-catalog", "--wallpaper-download", stringValue(id), "--json"]
    : []

const safeThumbnailPath = (path, cacheHome) => {
  const value = stringValue(path)
  const cacheRoot = stringValue(cacheHome).replace(/\/+$/, "")
  const expectedPrefix = cacheRoot + "/omarchy-theme-manager/wallpaper-thumbs/"
  const fileName = value.slice(expectedPrefix.length)
  return cacheRoot.startsWith("/") &&
    value.startsWith(expectedPrefix) &&
    !fileName.includes("/") &&
    !value.includes("\u0000") &&
    imagePathPattern.test(value)
    ? value
    : ""
}

const boundedText = (value, length) =>
  stringValue(value).replace(/\s+/g, " ").trim().slice(0, length)
const wallpaperFacts = (wallpaper) => ({
  id: stringValue(wallpaper.id),
  title: boundedText(wallpaper.title, 180),
  resolution: boundedText(wallpaper.resolution, 32),
  collection: boundedText(wallpaper.collection, 24),
  source: boundedText(wallpaper.source, 80),
  license: boundedText(wallpaper.license, 80),
  author: boundedText(wallpaper.author, 160),
  sourceURL: boundedText(wallpaper.url, 500)
})

const isListableWallpaper = (facts) =>
  wallpaperIdPattern.test(facts.id) &&
  !!optionForValue(collectionOptions, facts.collection) &&
  !!facts.license

const wallpaperRow = (wallpaper, cacheHome) => {
  if (!wallpaper || typeof wallpaper !== "object") return null
  const facts = wallpaperFacts(wallpaper)
  if (!isListableWallpaper(facts)) return null
  return {
    id: facts.id,
    filePath: "wallpaper:" + facts.id,
    fileName: facts.id,
    thumbnailPath: safeThumbnailPath(wallpaper.thumbnailPath, cacheHome),
    displayName: facts.title || "Open wallpaper " + facts.id,
    resolution: facts.resolution,
    category: collectionLabel(facts.collection),
    collection: facts.collection,
    license: facts.license,
    author: facts.author,
    source: facts.source,
    sourceURL: facts.sourceURL,
    searchText: [
      facts.title,
      facts.resolution,
      facts.collection,
      facts.license,
      facts.author,
      facts.source
    ]
      .filter(Boolean)
      .join(" ")
  }
}

const searchFailure = (error) => ({ error, rows: [], meta: {} })
const parsedJson = (text) => {
  try {
    return { payload: JSON.parse(text) }
  } catch (_error) {
    return { payload: null, invalid: true }
  }
}

const searchPayloadError = (responseText, parsed) => {
  if (responseText.length > maxSearchResponseLength)
    return "The wallpaper catalog returned an oversized response"
  if (parsed.invalid) return "The wallpaper catalog returned an invalid response"
  const payload = parsed.payload
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.wallpapers))
    return "The wallpaper catalog returned an incomplete response"
  if (payload.wallpapers.length > maxWallpapersPerResponse)
    return "The wallpaper catalog returned too many records"
  return ""
}

const uniqueWallpaperRows = (wallpapers, cacheHome) => {
  const seen = {}
  return wallpapers.reduce((result, wallpaper) => {
    const row = wallpaperRow(wallpaper, cacheHome)
    if (!row || seen[row.id]) return result
    seen[row.id] = true
    result.push(row)
    return result
  }, [])
}

const searchMeta = (payload) => {
  const meta = payload.meta && typeof payload.meta === "object" ? payload.meta : {}
  return {
    currentPage: integerValue(meta.current_page),
    lastPage: integerValue(meta.last_page),
    total: integerValue(meta.total),
    stale: meta.stale === true
  }
}

const parseSearchResponse = (text, cacheHome) => {
  const responseText = stringValue(text)
  const parsed =
    responseText.length > maxSearchResponseLength ? { payload: null } : parsedJson(responseText)
  const error = searchPayloadError(responseText, parsed)
  if (error) return searchFailure(error)
  return {
    error: "",
    rows: uniqueWallpaperRows(parsed.payload.wallpapers, cacheHome),
    meta: searchMeta(parsed.payload)
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

const isDownloadedWallpaperPath = (path, home, dataRoot) => {
  const expectedPrefix = dataRoot + "/omarchy-theme-manager/wallpapers/"
  return (
    home.startsWith("/") &&
    dataRoot.startsWith("/") &&
    path.startsWith(expectedPrefix) &&
    !path.slice(expectedPrefix.length).includes("/") &&
    !path.includes("\u0000") &&
    imagePathPattern.test(path)
  )
}

const parseDownloadResponse = (text, homeDir, dataHome) => {
  const responseText = stringValue(text)
  if (responseText.length > maxDownloadResponseLength)
    return { error: "The wallpaper catalog returned an oversized download response", path: "" }
  const parsed = parsedJson(responseText)
  if (parsed.invalid)
    return { error: "The wallpaper catalog returned an invalid download response", path: "" }
  const home = stringValue(homeDir).replace(/\/+$/, "")
  const dataRoot = (stringValue(dataHome) || home + "/.local/share").replace(/\/+$/, "")
  const path = stringValue(parsed.payload && parsed.payload.path)
  if (!isDownloadedWallpaperPath(path, home, dataRoot))
    return { error: "The wallpaper catalog returned an unexpected path", path: "" }
  return { error: "", path }
}

const boundedErrorText = (value) =>
  stringValue(value)
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 240)

const friendlyCatalogError = (message) => {
  const normalized = boundedErrorText(message)
  const httpMatch = normalized.match(/(?:provider returned HTTP|returned HTTP) (\d{3})\b/i)
  if (httpMatch) {
    const status = Number(httpMatch[1])
    if (status === 429) return "The wallpaper catalog is rate limiting requests. Try again shortly."
    if (status >= 500)
      return (
        "The wallpaper catalog is temporarily unavailable (HTTP " +
        status +
        "). Cached results will be used when available."
      )
    return "The wallpaper catalog request failed (HTTP " + status + ")."
  }
  if (
    /resolve remote host|temporary failure in name resolution|network is unreachable/i.test(
      normalized
    )
  )
    return "The wallpaper catalog could not be reached. Check your connection and retry."
  return normalized
}

const processError = (stdout, stderr, fallback) => {
  const parsed = parsedJson(stringValue(stdout))
  const jsonError =
    !parsed.invalid && parsed.payload && typeof parsed.payload === "object"
      ? stringValue(parsed.payload.error)
      : ""
  const stderrLine = stringValue(stderr)
    .split("\n")
    .map((line) => line.trim())
    .find(Boolean)
  return (
    friendlyCatalogError(jsonError) ||
    friendlyCatalogError(stderrLine) ||
    boundedErrorText(fallback) ||
    "The wallpaper catalog could not complete the request"
  )
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
    nextSorting,
    collectionLabel,
    sortingLabel,
    licenseLabel,
    filterSummary,
    defaultFilters,
    filtersActive,
    filterActiveCount,
    serializeFilters,
    parseFilters,
    getCollectionOptions,
    getSortingOptions,
    getLicenseOptions,
    searchArguments,
    downloadArguments,
    wallpaperRow,
    parseSearchResponse,
    appendUniqueRows,
    parseDownloadResponse,
    processError
  }
}
