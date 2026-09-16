const stringValue = (value) => String(value || "")
const imageValues = (images) => (Array.isArray(images) ? images : [])

const nameForPath = (path) =>
  stringValue(path)
    .split("/")
    .pop()
    .replace(/\.[^/.]+$/, "")

const labelForPath = (path) =>
  nameForPath(path)
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (match) => match.toUpperCase())

const normalizeSearchText = (value) =>
  stringValue(value)
    .toLowerCase()
    .replace(/[-_./]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()

const compactSearchText = (value) => normalizeSearchText(value).replace(/\s+/g, "")

const searchIndex = (value) => {
  const normalized = normalizeSearchText(value)
  return {
    normalized,
    compact: normalized.replace(/\s+/g, ""),
    words: normalized.split(" ").filter(Boolean)
  }
}

const isSubsequence = (needle, haystack) => {
  const token = stringValue(needle)
  const text = stringValue(haystack)
  if (!token) return true
  if (!text) return false

  let index = 0
  for (const character of text) {
    if (character === token[index]) index += 1
    if (index >= token.length) return true
  }

  return false
}

// One row of the edit-distance table; returns the smallest value in it.
const levenshteinRow = (aChar, b, previous, current) => {
  let rowMin = current[0]
  for (let column = 1; column <= b.length; column++) {
    const cost = aChar === b[column - 1] ? 0 : 1
    current[column] = Math.min(
      previous[column] + 1,
      current[column - 1] + 1,
      previous[column - 1] + cost
    )
    if (current[column] < rowMin) rowMin = current[column]
  }
  return rowMin
}

const levenshteinWithin = (a, b, limit) => {
  const previous = new Array(b.length + 1)
  const current = new Array(b.length + 1)
  for (let index = 0; index <= b.length; index++) previous[index] = index
  for (let row = 1; row <= a.length; row++) {
    current[0] = row
    if (levenshteinRow(a[row - 1], b, previous, current) > limit) return false
    for (let column = 0; column <= b.length; column++) previous[column] = current[column]
  }
  return previous[b.length] <= limit
}

const levenshteinAtMost = (left, right, maxDistance) => {
  const a = stringValue(left)
  const b = stringValue(right)
  const limit = Math.max(0, Number(maxDistance) || 0)
  if (a === b) return true
  if (Math.abs(a.length - b.length) > limit) return false
  return levenshteinWithin(a, b, limit)
}

const fuzzyDistanceForToken = (token) => {
  const length = stringValue(token).length
  if (length >= 8) return 2
  if (length >= 4) return 1
  return 0
}

// Prefer prefix/containment of meaningful word fragments inside the token.
const wordFragmentMatches = (needle, word) =>
  word.length >= 3 && needle.includes(word) && needle.length <= word.length + 2

// Per-token fuzzy: subsequence or bounded edit distance on a single word.
const wordFuzzyMatches = (needle, word, maxDistance) => {
  if (needle.length >= 3 && isSubsequence(needle, word)) return true
  return maxDistance > 0 && word.length >= 4 && levenshteinAtMost(needle, word, maxDistance)
}

const wordMatchesToken = (needle, word, maxDistance) =>
  word.includes(needle) ||
  wordFragmentMatches(needle, word) ||
  wordFuzzyMatches(needle, word, maxDistance)

const tokenMatchesHaystack = (token, hayNormalized, hayCompact, hayWords) => {
  const needle = stringValue(token)
  if (!needle) return true

  const compactNeedle = needle.replace(/\s+/g, "")
  if (hayNormalized.includes(needle)) return true
  if (compactNeedle && hayCompact.includes(compactNeedle)) return true

  const words = Array.isArray(hayWords) ? hayWords : hayNormalized.split(" ").filter(Boolean)
  const maxDistance = fuzzyDistanceForToken(needle)
  return words.some((word) => wordMatchesToken(needle, word, maxDistance))
}

// Soft fallback: require all but one token when the query is long enough.
// Avoids false negatives on multi-word names with a single typo token.
const allButOneTokenMatches = (tokens, hay) => {
  if (tokens.length < 3) return false
  let misses = 0
  for (const token of tokens) {
    if (!tokenMatchesHaystack(token, hay.normalized, hay.compact, hay.words)) misses += 1
    if (misses > 1) return false
  }
  return true
}

const haystackFields = (haystackIndex) => {
  const hay = haystackIndex || searchIndex("")
  return {
    normalized: stringValue(hay.normalized),
    compact: stringValue(hay.compact),
    words: Array.isArray(hay.words) ? hay.words : undefined
  }
}

const everyTokenMatches = (tokens, hay) =>
  tokens.every((token) => tokenMatchesHaystack(token, hay.normalized, hay.compact, hay.words))

// Whole-phrase / compact hits before token AND (multi-word & hyphen-insensitive).
const phraseMatches = (query, hay) =>
  hay.normalized.includes(query.normalized) ||
  Boolean(query.compact && hay.compact.includes(query.compact))

const searchIndexesMatch = (haystackIndex, queryIndex) => {
  const query = queryIndex || searchIndex("")
  if (!query.normalized) return true
  const hay = haystackFields(haystackIndex)
  if (phraseMatches(query, hay)) return true
  const tokens = query.normalized.split(" ").filter(Boolean)
  if (tokens.length === 0) return true
  return everyTokenMatches(tokens, hay) || allButOneTokenMatches(tokens, hay)
}

const textMatchesIndex = (haystackIndex, filterText) =>
  searchIndexesMatch(haystackIndex, searchIndex(filterText))

const textMatches = (haystack, filterText) => textMatchesIndex(searchIndex(haystack), filterText)

const loadRows = (rows) => {
  const seenFileNames = {}

  return stringValue(rows)
    .split("\n")
    .reduce((images, row) => {
      if (!row) return images

      const [filePath, thumbnailPath = filePath] = row.split("\t")
      if (!filePath) return images

      const fileName = filePath.split("/").pop()
      if (!fileName || seenFileNames[fileName]) return images

      seenFileNames[fileName] = true
      images.push({ filePath, fileName, thumbnailPath })
      return images
    }, [])
}

const itemSearchHaystack = (image) => {
  const item = image || {}
  const filePath = stringValue(item.filePath)
  return [
    nameForPath(filePath),
    labelForPath(filePath),
    item.displayName,
    item.searchText,
    item.installSlug,
    item.owner
  ]
    .map((value) => stringValue(value))
    .join(" ")
}

const itemSearchIndex = (image) => {
  const item = image || {}
  if (
    typeof item.searchNormalized === "string" &&
    typeof item.searchCompact === "string" &&
    Array.isArray(item.searchWords)
  ) {
    return {
      normalized: item.searchNormalized,
      compact: item.searchCompact,
      words: item.searchWords
    }
  }
  return searchIndex(itemSearchHaystack(item))
}

const itemMatches = (images, index, filterText) => {
  const values = imageValues(images)
  if (index < 0 || index >= values.length) return false
  if (!normalizeSearchText(filterText)) return true
  return textMatchesIndex(itemSearchIndex(values[index]), filterText)
}

const matchingIndices = (images, filterText) => {
  const values = imageValues(images)
  const query = searchIndex(filterText)
  if (!query.normalized) return values.map((_, index) => index)

  const indices = []
  for (let index = 0; index < values.length; index++) {
    if (searchIndexesMatch(itemSearchIndex(values[index]), query)) indices.push(index)
  }
  return indices
}

const positionsForIndices = (indices, imageCount) => {
  const count = Math.max(0, Number(imageCount) || 0)
  const positions = new Array(count).fill(-1)
  for (let position = 0; position < indices.length; position++) {
    const index = Number(indices[position])
    if (Number.isInteger(index) && index >= 0 && index < count) positions[index] = position
  }
  return positions
}

const wrappedIndex = (value, count) => {
  const length = Math.max(0, Number(count) || 0)
  if (length === 0) return -1
  return ((Number(value) % length) + length) % length
}

const nearestWrappedCursor = (cursor, position, count) => {
  const length = Math.max(0, Number(count) || 0)
  const target = wrappedIndex(position, length)
  if (target < 0) return 0
  const current = Number(cursor) || 0
  return target + Math.round((current - target) / length) * length
}

// The signed distance from the selected slot to a slot, taking the shorter way round a ring.
const ringRelative = (slot, selected, ringSize) => {
  const relative = slot - selected
  const half = Math.floor(ringSize / 2)
  if (relative > half) return relative - ringSize
  if (relative < -half) return relative + ringSize
  return relative
}

const carouselShape = (slot, count, poolSize) => ({
  length: Math.max(0, Number(count) || 0),
  size: Math.max(1, Math.floor(Number(poolSize) || 1)),
  poolSlot: Math.floor(Number(slot) || 0)
})

const carouselRelativeForSlot = (slot, cursor, count, poolSize) => {
  const { length, size, poolSlot } = carouselShape(slot, count, poolSize)
  if (poolSlot < 0 || poolSlot >= size || length === 0) return null
  // A carousel that fits inside the pool maps slots onto positions directly.
  if (length > size) return ringRelative(poolSlot, wrappedIndex(cursor, size), size)
  if (poolSlot >= length) return null
  return ringRelative(poolSlot, wrappedIndex(cursor, length), length)
}

const carouselPositionForSlot = (slot, cursor, count, poolSize) => {
  const relative = carouselRelativeForSlot(slot, cursor, count, poolSize)
  return relative === null ? -1 : wrappedIndex((Number(cursor) || 0) + relative, count)
}

const firstMatchingIndex = (images, filterText) =>
  imageValues(images).findIndex((_, index) => itemMatches(images, index, filterText))

const filteredPosition = (images, index, filterText) => {
  if (!filterText) return index

  return imageValues(images)
    .slice(0, Math.max(0, index))
    .filter((_, candidateIndex) => itemMatches(images, candidateIndex, filterText)).length
}

const selectedFilteredPosition = (images, selectedIndex, filterText) => {
  if (!filterText) return selectedIndex
  return itemMatches(images, selectedIndex, filterText)
    ? filteredPosition(images, selectedIndex, filterText)
    : 0
}

const indexForSelectedImage = (images, selectedImage) => {
  const selectedIndex = imageValues(images).findIndex((image) => image.filePath === selectedImage)
  return selectedIndex >= 0 ? selectedIndex : 0
}

const nextSelectedIndexForFilter = (images, selectedIndex, filterText) =>
  itemMatches(images, selectedIndex, filterText)
    ? selectedIndex
    : firstMatchingIndex(images, filterText)

if (typeof module !== "undefined") {
  module.exports = {
    nameForPath,
    labelForPath,
    normalizeSearchText,
    compactSearchText,
    searchIndex,
    isSubsequence,
    levenshteinAtMost,
    fuzzyDistanceForToken,
    textMatches,
    textMatchesIndex,
    searchIndexesMatch,
    itemSearchHaystack,
    itemSearchIndex,
    loadRows,
    itemMatches,
    matchingIndices,
    positionsForIndices,
    wrappedIndex,
    nearestWrappedCursor,
    carouselRelativeForSlot,
    carouselPositionForSlot,
    firstMatchingIndex,
    filteredPosition,
    selectedFilteredPosition,
    indexForSelectedImage,
    nextSelectedIndexForFilter
  }
}
