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
  return "Review source"
}

const catalogRows = (payload, inventory = {}) => {
  const data = objectValue(payload)
  const installedThemes = objectValue(inventory.installedThemes)
  const stockThemes = objectValue(inventory.stockThemes)
  const installedRepositories = repositoryKeyMap(inventory.installedRepositories)
  const officialRepositories = repositoryKeyMap(data.officialRepositories)
  const rowsByRepository = {}

  for (const entry of arrayValue(data.themes)) {
    const repositoryUrl = normalizeRepositoryUrl(entry.repositoryUrl || entry.github_url)
    const installSlug = installSlugForRepositoryUrl(repositoryUrl)
    if (!repositoryUrl || !isSafeThemeSlug(installSlug)) continue

    const installed =
      installedThemes[installSlug] === true || installedRepositories[repositoryUrl] === true
    const stockConflict = stockThemes[installSlug] === true
    const official = officialRepositories[repositoryUrl] === true
    const warnings = parsedArray(entry.securityWarnings || entry.security_warnings)
      .map((warning) => plainTextValue(warning, 180))
      .filter(Boolean)
    const apps = parsedArray(entry.apps || entry.apps_json)
      .map((app) => plainTextValue(app, 80))
      .filter(Boolean)
    const stars = Number(entry.stars) || 0
    const existing = rowsByRepository[repositoryUrl]

    if (existing) {
      existing.official = existing.official || official
      existing.stars = Math.max(existing.stars, stars)
      continue
    }

    const name = plainTextValue(entry.name || installSlug, 120)
    const owner = plainTextValue(entry.owner || entry.github_owner, 80)
    const description = plainTextValue(entry.description, 500)
    const previewUrl = safePreviewUrl(entry.previewUrl || entry.preview_url)

    const reviewable = !installed && !stockConflict

    rowsByRepository[repositoryUrl] = {
      filePath: repositoryUrl,
      fileName: `${installSlug}.webp`,
      thumbnailPath: previewUrl,
      displayName: name,
      installSlug,
      repositoryUrl,
      owner,
      description,
      stars,
      apps,
      warnings,
      official,
      installed,
      stockConflict,
      reviewable,
      status: displayStatus({ installed, stockConflict }),
      searchText: [name, owner, description, installSlug, repositoryUrl, apps.join(" ")]
        .join(" ")
        .toLowerCase()
    }
  }

  return Object.keys(rowsByRepository)
    .map((key) => rowsByRepository[key])
    .sort((left, right) => {
      if (left.reviewable !== right.reviewable) return left.reviewable ? -1 : 1
      if (left.official !== right.official) return left.official ? -1 : 1
      if (left.stars !== right.stars) return right.stars - left.stars
      return left.displayName.localeCompare(right.displayName)
    })
}

const listingOptions = [
  { value: "all", label: "All" },
  { value: "official", label: "Official" },
  { value: "community", label: "Community" }
]

const availabilityOptions = [
  { value: "all", label: "All" },
  { value: "reviewable", label: "Reviewable" },
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

const itemMatchesCatalogFilters = (item, filters) => {
  const row = objectValue(item)
  const normalized = normalizeCatalogFilters(filters)

  if (normalized.listing === "official" && !row.official) return false
  if (normalized.listing === "community" && row.official) return false

  if (normalized.availability === "reviewable" && !row.reviewable) return false
  if (normalized.availability === "installed" && !row.installed) return false
  if (normalized.availability === "conflicts" && !row.stockConflict) return false

  const stars = Number(row.stars) || 0
  if (stars < normalized.minStars) return false
  return true
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

const serializeCatalogFilters = (filters) =>
  JSON.stringify(normalizeCatalogFilters(filters), null, 2) + "\n"

const parseCatalogFilters = (raw) => {
  try {
    return normalizeCatalogFilters(JSON.parse(stringValue(raw) || "{}"))
  } catch (_error) {
    return defaultCatalogFilters()
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
    catalogRows,
    defaultCatalogFilters,
    normalizeCatalogFilters,
    catalogFilterKey,
    catalogFiltersActive,
    catalogFilterSummary,
    itemMatchesCatalogFilters,
    applyCatalogFilters,
    getListingOptions,
    getAvailabilityOptions,
    getCatalogSortOptions,
    getMinStarsOptions,
    serializeCatalogFilters,
    parseCatalogFilters
  }
}
