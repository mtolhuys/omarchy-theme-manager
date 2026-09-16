const stringValue = (value) => String(value || "")
const objectValue = (value) => (value && typeof value === "object" ? value : {})
const arrayValue = (value) => (Array.isArray(value) ? value : [])

const plainTextValue = (value, maximumLength = 240) =>
  stringValue(value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/[<>&]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximumLength)

const safePreviewUrl = (value) => {
  const url = stringValue(value).trim()
  const rawGitHubUrl =
    /^https:\/\/raw\.githubusercontent\.com\/[a-z0-9_.-]+\/[a-z0-9_.-]+\/[^/?#]+\/[^\s?#]+(?:\?[^\s#]*)?$/i
  const githubAttachmentUrl = /^https:\/\/github\.com\/user-attachments\/assets\/[0-9a-f-]{36}$/i
  return rawGitHubUrl.test(url) || githubAttachmentUrl.test(url) ? url : ""
}

const normalizeRepositoryUrl = (url) => {
  const normalized = stringValue(url)
    .trim()
    .replace(/^git@github\.com:/i, "https://github.com/")
    .replace(/^git:\/\/github\.com\//i, "https://github.com/")
    .replace(/^http:\/\/github\.com\//i, "https://github.com/")
    .replace(/[?#].*$/, "")
    .replace(/\/+$/, "")
    .replace(/\.git$/i, "")

  const match = normalized.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)$/i)
  return match ? `https://github.com/${match[1].toLowerCase()}/${match[2].toLowerCase()}` : ""
}

const repositoryName = (url) => {
  const normalized = normalizeRepositoryUrl(url)
  return normalized ? normalized.split("/").pop() : ""
}

const installSlugForRepositoryUrl = (url) =>
  repositoryName(url)
    .replace(/^omarchy-/i, "")
    .replace(/-theme$/i, "")
    .toLowerCase()

const isSafeThemeSlug = (slug) => /^[a-z0-9][a-z0-9._-]*$/.test(stringValue(slug))

const parsedArray = (value) => {
  if (Array.isArray(value)) return value
  if (!value) return []

  try {
    const parsed = JSON.parse(String(value))
    return Array.isArray(parsed) ? parsed : []
  } catch (_error) {
    return []
  }
}

const repositoryKeyMap = (values) =>
  arrayValue(values).reduce((repositories, url) => {
    const key = normalizeRepositoryUrl(url)
    if (key) repositories[key] = true
    return repositories
  }, {})

const displayStatus = ({ installed, stockConflict }) => {
  if (installed) return "Installed"
  if (stockConflict) return "Conflicts with stock theme"
  return "Install"
}

const installConfirmationMessage = (entry) => {
  const row = objectValue(entry)
  const name = plainTextValue(row.displayName || row.installSlug || "this theme", 120)
  return `Install “${name}” from a sanitized, exact repository snapshot? Only its palette and bounded wallpaper images are imported; scripts and application configs are ignored. Omarchy applies the theme immediately.`
}

const catalogContext = (data, inventory) => ({
  installedThemes: objectValue(inventory.installedThemes),
  stockThemes: objectValue(inventory.stockThemes),
  installedRepositories: repositoryKeyMap(inventory.installedRepositories),
  officialRepositories: repositoryKeyMap(data.officialRepositories)
})

const plainTextList = (value, maximumLength) =>
  parsedArray(value)
    .map((item) => plainTextValue(item, maximumLength))
    .filter(Boolean)

const searchFields = (row) => {
  const searchText = [
    row.displayName,
    row.owner,
    row.description,
    row.installSlug,
    row.repositoryUrl,
    row.apps.join(" ")
  ]
    .join(" ")
    .toLowerCase()
  const searchNormalized = searchText
    .replace(/[-_./]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
  return {
    searchText,
    searchNormalized,
    searchCompact: searchNormalized.replace(/\s+/g, ""),
    searchWords: searchNormalized.split(" ").filter(Boolean)
  }
}

// The sanitized display values of one catalog entry, independent of the local inventory.
const catalogEntryFields = (entry, installSlug) => ({
  thumbnailPath: safePreviewUrl(entry.previewUrl || entry.preview_url),
  displayName: plainTextValue(entry.name || installSlug, 120),
  owner: plainTextValue(entry.owner || entry.github_owner, 80),
  description: plainTextValue(entry.description, 500),
  stars: Number(entry.stars) || 0,
  apps: plainTextList(entry.apps || entry.apps_json, 80),
  warnings: plainTextList(entry.securityWarnings || entry.security_warnings, 180)
})

const catalogRow = (entry, repositoryUrl, installSlug, context) => {
  const installed =
    context.installedThemes[installSlug] === true ||
    context.installedRepositories[repositoryUrl] === true
  const stockConflict = context.stockThemes[installSlug] === true
  const row = Object.assign(
    { filePath: repositoryUrl, fileName: `${installSlug}.webp`, installSlug, repositoryUrl },
    catalogEntryFields(entry, installSlug),
    {
      official: context.officialRepositories[repositoryUrl] === true,
      installed,
      stockConflict,
      canInstall: !installed && !stockConflict,
      status: displayStatus({ installed, stockConflict })
    }
  )
  return Object.assign(row, searchFields(row))
}

// A repository listed twice keeps one row: official if either listing is, with the higher star count.
const mergeDuplicate = (existing, entry, context, repositoryUrl) => {
  existing.official = existing.official || context.officialRepositories[repositoryUrl] === true
  existing.stars = Math.max(existing.stars, Number(entry.stars) || 0)
}

const compareCatalogOrder = (left, right) => {
  if (left.canInstall !== right.canInstall) return left.canInstall ? -1 : 1
  if (left.official !== right.official) return left.official ? -1 : 1
  if (left.stars !== right.stars) return right.stars - left.stars
  return left.displayName.localeCompare(right.displayName)
}

const catalogRows = (payload, inventory = {}) => {
  const data = objectValue(payload)
  const context = catalogContext(data, inventory)
  const rowsByRepository = {}

  for (const entry of arrayValue(data.themes)) {
    const repositoryUrl = normalizeRepositoryUrl(entry.repositoryUrl || entry.github_url)
    const installSlug = installSlugForRepositoryUrl(repositoryUrl)
    if (!repositoryUrl || !isSafeThemeSlug(installSlug)) continue
    const existing = rowsByRepository[repositoryUrl]
    if (existing) mergeDuplicate(existing, entry, context, repositoryUrl)
    else rowsByRepository[repositoryUrl] = catalogRow(entry, repositoryUrl, installSlug, context)
  }

  return Object.keys(rowsByRepository)
    .map((key) => rowsByRepository[key])
    .sort(compareCatalogOrder)
}

const listingOptions = [
  { value: "all", label: "All" },
  { value: "official", label: "Official" },
  { value: "community", label: "Community" }
]

const availabilityOptions = [
  { value: "all", label: "All" },
  { value: "installable", label: "Installable" },
  { value: "installed", label: "Installed" },
  { value: "conflicts", label: "Conflicts" }
]

const sortOptions = [
  { value: "best", label: "Best match" },
  { value: "stars", label: "Stars" },
  { value: "name", label: "Name A–Z" }
]

const minStarsOptions = [
  { value: 0, label: "Any" },
  { value: 10, label: "10+" },
  { value: 50, label: "50+" },
  { value: 100, label: "100+" }
]

const optionForValue = (options, value) =>
  options.find((option) => String(option.value) === String(value))

const normalizeCatalogQuery = (value) =>
  stringValue(value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120)

const defaultCatalogFilters = () => ({
  listing: "all",
  availability: "all",
  sort: "best",
  minStars: 0
})

const normalizeCatalogFilters = (filters) => {
  const input = filters && typeof filters === "object" ? filters : {}
  const listing = stringValue(input.listing)
  const availability = stringValue(input.availability)
  const sort = stringValue(input.sort)
  const minStars = Number(input.minStars)

  return {
    listing: optionForValue(listingOptions, listing) ? listing : "all",
    availability: optionForValue(availabilityOptions, availability) ? availability : "all",
    sort: optionForValue(sortOptions, sort) ? sort : "best",
    minStars: optionForValue(minStarsOptions, minStars) ? minStars : 0
  }
}

const catalogFilterActiveCount = (filters) => {
  const normalized = normalizeCatalogFilters(filters)
  const defaults = defaultCatalogFilters()
  let count = 0
  if (normalized.listing !== defaults.listing) count += 1
  if (normalized.availability !== defaults.availability) count += 1
  if (normalized.sort !== defaults.sort) count += 1
  if (normalized.minStars !== defaults.minStars) count += 1
  return count
}

const catalogFilterKey = (filters) => {
  const normalized = normalizeCatalogFilters(filters)
  return [normalized.listing, normalized.availability, normalized.sort, normalized.minStars].join(
    "|"
  )
}

const catalogFiltersActive = (filters) =>
  catalogFilterKey(filters) !== catalogFilterKey(defaultCatalogFilters())

const catalogFilterSummary = (filters) => {
  const normalized = normalizeCatalogFilters(filters)
  const parts = []

  if (normalized.listing !== "all") {
    parts.push(optionForValue(listingOptions, normalized.listing).label)
  }
  if (normalized.availability !== "all") {
    parts.push(optionForValue(availabilityOptions, normalized.availability).label)
  }
  if (normalized.sort === "stars") parts.push("Stars ↓")
  else if (normalized.sort === "name") parts.push("Name A–Z")
  if (normalized.minStars > 0) {
    parts.push(optionForValue(minStarsOptions, normalized.minStars).label)
  }

  return parts.length > 0 ? parts.join("  ·  ") : "All themes"
}

const matchesListing = (row, listing) => {
  if (listing === "official") return Boolean(row.official)
  if (listing === "community") return !row.official
  return true
}

const matchesAvailability = (row, availability) => {
  if (availability === "installable") return Boolean(row.canInstall)
  if (availability === "installed") return Boolean(row.installed)
  if (availability === "conflicts") return Boolean(row.stockConflict)
  return true
}

const itemMatchesCatalogFilters = (item, filters) => {
  const row = objectValue(item)
  const normalized = normalizeCatalogFilters(filters)
  if (!matchesListing(row, normalized.listing)) return false
  if (!matchesAvailability(row, normalized.availability)) return false
  return (Number(row.stars) || 0) >= normalized.minStars
}

const compareCatalogRows = (left, right, sort) => {
  const mode = stringValue(sort) || "best"
  if (mode === "stars") {
    const starDelta = (Number(right.stars) || 0) - (Number(left.stars) || 0)
    if (starDelta !== 0) return starDelta
    return stringValue(left.displayName).localeCompare(stringValue(right.displayName))
  }
  if (mode === "name") {
    return stringValue(left.displayName).localeCompare(stringValue(right.displayName))
  }
  return 0
}

const applyCatalogFilters = (rows, filters) => {
  const normalized = normalizeCatalogFilters(filters)
  const matched = arrayValue(rows).filter((row) => itemMatchesCatalogFilters(row, normalized))
  if (normalized.sort === "best") return matched.slice()

  return matched
    .map((row, index) => ({ row, index }))
    .sort((left, right) => {
      const ranked = compareCatalogRows(left.row, right.row, normalized.sort)
      return ranked !== 0 ? ranked : left.index - right.index
    })
    .map((entry) => entry.row)
}

const cloneOptions = (options) =>
  options.map((option) => ({ value: option.value, label: option.label }))

const getListingOptions = () => cloneOptions(listingOptions)
const getAvailabilityOptions = () => cloneOptions(availabilityOptions)
const getCatalogSortOptions = () => cloneOptions(sortOptions)
const getMinStarsOptions = () => cloneOptions(minStarsOptions)

const serializeCatalogFilters = (filters, query = "") => {
  const serialized = normalizeCatalogFilters(filters)
  serialized.query = normalizeCatalogQuery(query)
  return JSON.stringify(serialized, null, 2) + "\n"
}

const parseCatalogFilters = (raw) => {
  try {
    const parsed = JSON.parse(stringValue(raw) || "{}")
    return normalizeCatalogFilters(parsed)
  } catch (_error) {
    return defaultCatalogFilters()
  }
}

const parseCatalogFilterState = (raw) => {
  try {
    const parsed = JSON.parse(stringValue(raw) || "{}")
    return {
      filters: normalizeCatalogFilters(parsed),
      query: normalizeCatalogQuery(parsed && parsed.query)
    }
  } catch (_error) {
    return { filters: defaultCatalogFilters(), query: "" }
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeRepositoryUrl,
    repositoryName,
    installSlugForRepositoryUrl,
    isSafeThemeSlug,
    plainTextValue,
    safePreviewUrl,
    parsedArray,
    installConfirmationMessage,
    catalogRows,
    defaultCatalogFilters,
    normalizeCatalogFilters,
    catalogFilterKey,
    catalogFiltersActive,
    catalogFilterActiveCount,
    catalogFilterSummary,
    itemMatchesCatalogFilters,
    applyCatalogFilters,
    getListingOptions,
    getAvailabilityOptions,
    getCatalogSortOptions,
    getMinStarsOptions,
    normalizeCatalogQuery,
    serializeCatalogFilters,
    parseCatalogFilters,
    parseCatalogFilterState
  }
}
