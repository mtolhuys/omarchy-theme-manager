const maxFavorites = 512
const stateVersion = 2

const stringValue = (value) => String(value || "")

const safePath = (value) => {
  const path = stringValue(value).trim()
  if (!path.startsWith("/") || path.length > 4096 || path.includes("\0")) return ""
  return path
}

const safeText = (value, maximumLength = 255) => {
  const text = stringValue(value).trim()
  if (!text || text.length > maximumLength || /[\u0000-\u001f\u007f]/.test(text)) return ""
  return text
}

const favoriteIdForPath = (path, context = {}) => {
  const target = safePath(path)
  if (!target) return ""

  const themeRoot = safePath(context.themeRoot).replace(/\/+$/, "")
  const themeName = safeText(context.themeName)
  if (themeRoot && themeName && target.startsWith(themeRoot + "/")) {
    const relativePath = target.slice(themeRoot.length + 1)
    if (relativePath && !relativePath.includes("\0"))
      return "theme:" + encodeURIComponent(themeName) + ":" + encodeURIComponent(relativePath)
  }

  return "path:" + encodeURIComponent(target)
}

const safeFavoriteId = (value) => {
  const id = safeText(value, 8192)
  return /^(?:path|theme):/.test(id) ? id : ""
}

const normalizeFavorites = (values) => {
  const seen = new Set()
  const result = []

  for (const value of Array.isArray(values) ? values : []) {
    const id = safeFavoriteId(value)
    if (!id || seen.has(id)) continue
    seen.add(id)
    result.push(id)
    if (result.length >= maxFavorites) break
  }

  return result
}

const emptyState = () => ({ version: stateVersion, favorites: [], folder: "", showHidden: false })

const parseState = (raw, context = {}) => {
  try {
    const parsed = JSON.parse(stringValue(raw) || "{}")
    const values = Array.isArray(parsed) ? parsed : parsed.favorites
    const migrated =
      parsed && parsed.version === stateVersion
        ? values
        : (Array.isArray(values) ? values : []).map((path) => favoriteIdForPath(path, context))
    const record = Array.isArray(parsed) || !parsed || typeof parsed !== "object" ? {} : parsed
    return {
      version: stateVersion,
      favorites: normalizeFavorites(migrated),
      // Where folder browsing last stood. Absent in files written before it
      // existed, which is the same as never having browsed.
      folder: safePath(record.folder),
      showHidden: record.showHidden === true
    }
  } catch (_error) {
    return emptyState()
  }
}

const serializeState = (favorites, folder, showHidden) =>
  JSON.stringify(
    {
      version: stateVersion,
      favorites: normalizeFavorites(favorites),
      folder: safePath(folder),
      showHidden: showHidden === true
    },
    null,
    2
  ) + "\n"

const isFavorite = (favorites, path, context = {}) => {
  const target = favoriteIdForPath(path, context)
  return !!target && normalizeFavorites(favorites).includes(target)
}

const toggleFavorite = (favorites, path, context = {}) => {
  const target = favoriteIdForPath(path, context)
  const normalized = normalizeFavorites(favorites)
  if (!target) return normalized
  if (normalized.includes(target)) return normalized.filter((value) => value !== target)
  return [target].concat(normalized).slice(0, maxFavorites)
}

// Favorites form a stable front section in most-recently-favorited order;
// everything else keeps the exact order supplied by Omarchy's picker.
const prioritizeFavorites = (images, favorites, context = {}) => {
  const values = Array.isArray(images) ? images : []
  const order = new Map(normalizeFavorites(favorites).map((id, index) => [id, index]))
  const saved = []
  const rest = []

  for (const image of values) {
    const id = favoriteIdForPath(image && image.filePath, context)
    if (order.has(id)) saved.push({ image, order: order.get(id) })
    else rest.push(image)
  }

  saved.sort((left, right) => left.order - right.order)
  return saved.map((entry) => entry.image).concat(rest)
}

if (typeof module !== "undefined") {
  module.exports = {
    maxFavorites,
    stateVersion,
    safePath,
    emptyState,
    favoriteIdForPath,
    normalizeFavorites,
    parseState,
    serializeState,
    isFavorite,
    toggleFavorite,
    prioritizeFavorites
  }
}
