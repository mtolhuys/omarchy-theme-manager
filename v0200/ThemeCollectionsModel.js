const stateVersion = 1
const maxCollections = 100
const maxNameLength = 64
const maxThemesPerList = 1000
const builtinSectionIds = { favorites: true, defaults: true, installed: true, all: true }
const viewValues = { carousel: true, grid: true }
const defaultView = "carousel"

const stringValue = (value) => String(value || "")
const arrayValue = (value) => (Array.isArray(value) ? value : [])
const isPlainObject = (value) =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value)

// Theme ids are installed theme directory names; same rule as ThemeManagerModel.
const safeThemeId = (value) => {
  const id = stringValue(value).trim()
  if (!id || id.length > 255 || id === "." || id === "..") return ""
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id) ? id : ""
}

const safeCollectionId = (value) => {
  const id = stringValue(value).trim()
  if (!id || id.length > 64 || builtinSectionIds[id]) return ""
  return /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(id) ? id : ""
}

// The remembered layout; anything unrecognised falls back to the carousel.
const safeView = (value) => {
  const view = stringValue(value).trim().toLowerCase()
  return viewValues[view] ? view : defaultView
}

const normalizeName = (value) =>
  stringValue(value).replace(/\s+/g, " ").trim().slice(0, maxNameLength)

const uniqueThemeIds = (values) => {
  const seen = {}
  const ids = []
  for (const value of arrayValue(values)) {
    const id = safeThemeId(value)
    if (!id || seen[id] || ids.length >= maxThemesPerList) continue
    seen[id] = true
    ids.push(id)
  }
  return ids
}

const emptyState = () => ({
  version: stateVersion,
  view: defaultView,
  favorites: [],
  collections: []
})

const normalizeCollection = (entry, seenIds) => {
  if (!isPlainObject(entry)) return null
  const id = safeCollectionId(entry.id)
  const name = normalizeName(entry.name)
  if (!id || !name || seenIds[id]) return null
  seenIds[id] = true
  return { id, name, themes: uniqueThemeIds(entry.themes) }
}

const normalizeCollections = (values) => {
  const seenIds = {}
  const collections = []
  for (const entry of arrayValue(values)) {
    if (collections.length >= maxCollections) break
    const collection = normalizeCollection(entry, seenIds)
    if (collection) collections.push(collection)
  }
  return collections
}

const normalizeState = (parsed) => {
  if (!isPlainObject(parsed)) return emptyState()
  return {
    version: stateVersion,
    view: safeView(parsed.view),
    favorites: uniqueThemeIds(parsed.favorites),
    collections: normalizeCollections(parsed.collections)
  }
}

// A blank file is empty state; anything else that fails to parse is corrupt.
const parseStateResult = (raw) => {
  const text = stringValue(raw).trim()
  if (!text) return { state: emptyState(), corrupt: false }
  try {
    const parsed = JSON.parse(text)
    if (!isPlainObject(parsed)) return { state: emptyState(), corrupt: true }
    return { state: normalizeState(parsed), corrupt: false }
  } catch (_error) {
    return { state: emptyState(), corrupt: true }
  }
}

const parseState = (raw) => parseStateResult(raw).state

const serializeState = (state) => JSON.stringify(normalizeState(state), null, 2) + "\n"

const cloneState = (state) => normalizeState(JSON.parse(serializeState(state || emptyState())))

const isGridView = (state) => safeView(state && state.view) === "grid"

const setView = (state, view) => {
  const next = cloneState(state)
  next.view = safeView(view)
  return next
}

const backupPath = (path) => (stringValue(path) ? stringValue(path) + ".bak" : "")

const isFavorite = (state, themeId) => {
  const id = safeThemeId(themeId)
  return !!id && arrayValue(state && state.favorites).indexOf(id) >= 0
}

const favoriteCount = (state) => uniqueThemeIds(state && state.favorites).length

const toggleFavorite = (state, themeId) => {
  const id = safeThemeId(themeId)
  const next = cloneState(state)
  if (!id) return next
  const index = next.favorites.indexOf(id)
  if (index >= 0) next.favorites.splice(index, 1)
  else if (next.favorites.length < maxThemesPerList) next.favorites.push(id)
  return next
}

const collectionById = (state, collectionId) => {
  const id = safeCollectionId(collectionId)
  if (!id) return null
  return arrayValue(state && state.collections).find((entry) => entry.id === id) || null
}

const collectionByName = (state, name, excludeId) => {
  const wanted = normalizeName(name).toLowerCase()
  if (!wanted) return null
  return (
    arrayValue(state && state.collections).find(
      (entry) => entry.id !== excludeId && entry.name.toLowerCase() === wanted
    ) || null
  )
}

const validateCollectionName = (state, name, excludeId) => {
  const normalized = normalizeName(name)
  if (!normalized) return "Give the collection a name"
  if (stringValue(name).replace(/\s+/g, " ").trim().length > maxNameLength)
    return "Keep the name within " + maxNameLength + " characters"
  if (collectionByName(state, normalized, excludeId)) return "A collection already has that name"
  if (!excludeId && arrayValue(state && state.collections).length >= maxCollections)
    return "Up to " + maxCollections + " collections are supported"
  return ""
}

// Deterministic ids: the smallest unused c<N>, so tests and files stay readable.
const nextCollectionId = (state) => {
  const taken = {}
  for (const entry of arrayValue(state && state.collections)) taken[entry.id] = true
  let number = 1
  while (taken["c" + number]) number += 1
  return "c" + number
}

const createCollection = (state, name, themeIds) => {
  const error = validateCollectionName(state, name, "")
  if (error) return { state: cloneState(state), id: "", error }
  const next = cloneState(state)
  const id = nextCollectionId(next)
  next.collections.push({ id, name: normalizeName(name), themes: uniqueThemeIds(themeIds) })
  return { state: next, id, error: "" }
}

const renameCollection = (state, collectionId, name) => {
  const collection = collectionById(state, collectionId)
  if (!collection) return { state: cloneState(state), error: "That collection no longer exists" }
  const error = validateCollectionName(state, name, collection.id)
  if (error) return { state: cloneState(state), error }
  const next = cloneState(state)
  collectionById(next, collection.id).name = normalizeName(name)
  return { state: next, error: "" }
}

const deleteCollection = (state, collectionId) => {
  const next = cloneState(state)
  const id = safeCollectionId(collectionId)
  next.collections = next.collections.filter((entry) => entry.id !== id)
  return next
}

const isMember = (state, collectionId, themeId) => {
  const collection = collectionById(state, collectionId)
  const id = safeThemeId(themeId)
  return !!collection && !!id && collection.themes.indexOf(id) >= 0
}

const withMember = (themes, id, member) => {
  const present = themes.indexOf(id) >= 0
  if (member && !present && themes.length < maxThemesPerList) return themes.concat([id])
  if (!member && present) return themes.filter((theme) => theme !== id)
  return themes
}

const setMembership = (state, collectionId, themeId, member) => {
  const next = cloneState(state)
  const collection = collectionById(next, collectionId)
  const id = safeThemeId(themeId)
  if (collection && id) collection.themes = withMember(collection.themes, id, member === true)
  return next
}

// Rows for the memberships sheet: Favorites first, then every collection.
const membershipRows = (state, themeId) => {
  const rows = [{ id: "favorites", name: "Favorites", member: isFavorite(state, themeId) }]
  for (const entry of arrayValue(state && state.collections)) {
    rows.push({ id: entry.id, name: entry.name, member: isMember(state, entry.id, themeId) })
  }
  return rows
}

const applyMemberships = (state, themeId, rows) => {
  let next = cloneState(state)
  for (const row of arrayValue(rows)) {
    if (!isPlainObject(row)) continue
    const member = row.member === true
    if (row.id === "favorites") {
      if (member !== isFavorite(next, themeId)) next = toggleFavorite(next, themeId)
    } else {
      next = setMembership(next, row.id, themeId, member)
    }
  }
  return next
}

const themeIdForImage = (image) =>
  safeThemeId(
    stringValue(image && image.filePath)
      .split("/")
      .pop()
      .replace(/\.[^/.]+$/, "")
  )

// Collections whose name matches the query; matcher is ImagePickerModel.textMatches.
const matchingCollectionIds = (state, filterText, matcher) => {
  const ids = {}
  if (!stringValue(filterText).trim() || typeof matcher !== "function") return ids
  for (const entry of arrayValue(state && state.collections)) {
    if (matcher(entry.name, filterText)) ids[entry.id] = true
  }
  return ids
}

const themesInCollections = (state, collectionIds) => {
  const themes = {}
  for (const entry of arrayValue(state && state.collections)) {
    if (!collectionIds[entry.id]) continue
    for (const id of entry.themes) themes[id] = true
  }
  return themes
}

// The existing text matches plus every theme of a collection whose name matches,
// in image order, so a collection name works as a search term without an index.
const searchIndices = (images, textIndices, filterText, state, matcher) => {
  const collectionIds = matchingCollectionIds(state, filterText, matcher)
  if (Object.keys(collectionIds).length === 0) return arrayValue(textIndices).slice()
  const themes = themesInCollections(state, collectionIds)
  const matched = {}
  for (const index of arrayValue(textIndices)) matched[index] = true
  const values = arrayValue(images)
  const indices = []
  for (let index = 0; index < values.length; index++) {
    if (matched[index] || themes[themeIdForImage(values[index])]) indices.push(index)
  }
  return indices
}

const favoriteIndices = (images, indices, state) => {
  const values = arrayValue(images)
  return arrayValue(indices).filter((index) => isFavorite(state, themeIdForImage(values[index])))
}

const indicesWhere = (images, indices, predicate) => {
  const values = arrayValue(images)
  return arrayValue(indices).filter((index) => predicate(themeIdForImage(values[index])))
}

const inventorySections = (images, indices, options) => {
  const stock = isPlainObject(options.stockThemes) ? options.stockThemes : {}
  if (options.inventoryReady !== true) {
    return [{ id: "all", name: "Themes", kind: "all", indices: arrayValue(indices).slice() }]
  }
  return [
    {
      id: "defaults",
      name: "Omarchy defaults",
      kind: "defaults",
      indices: indicesWhere(images, indices, (id) => stock[id] === true)
    },
    {
      id: "installed",
      name: "Installed",
      kind: "installed",
      indices: indicesWhere(images, indices, (id) => stock[id] !== true)
    }
  ]
}

const collectionSections = (images, indices, state) =>
  arrayValue(state && state.collections).map((entry) => ({
    id: entry.id,
    name: entry.name,
    kind: "collection",
    indices: indicesWhere(images, indices, (id) => entry.themes.indexOf(id) >= 0)
  }))

// Grid sections in fixed order; empty ones are dropped, favorites-only keeps one.
const sections = (images, indices, state, options) => {
  const settings = isPlainObject(options) ? options : {}
  const favorites = {
    id: "favorites",
    name: "Favorites",
    kind: "favorites",
    indices: favoriteIndices(images, indices, state)
  }
  const all = settings.favoritesOnly
    ? [favorites]
    : [favorites]
        .concat(inventorySections(images, indices, settings))
        .concat(collectionSections(images, indices, state))
  return all.filter((section) => section.indices.length > 0)
}

const gridGap = 12
const gridHeaderHeight = 28
const gridMaxColumns = 4
const gridMinCellWidth = 200
const gridMaxCellWidth = 260

const gridGeometry = (width, height) => {
  const available = Math.max(0, Number(width) || 0)
  const columns = Math.max(
    1,
    Math.min(gridMaxColumns, Math.floor((available + gridGap) / (gridMinCellWidth + gridGap)))
  )
  const cellWidth = Math.max(
    1,
    Math.min(gridMaxCellWidth, Math.floor((available - (columns - 1) * gridGap) / columns))
  )
  const contentWidth = columns * cellWidth + (columns - 1) * gridGap
  return {
    columns,
    cellWidth,
    cellHeight: Math.round((cellWidth * 9) / 16),
    gap: gridGap,
    headerHeight: gridHeaderHeight,
    offsetX: Math.max(0, Math.floor((available - contentWidth) / 2)),
    viewportHeight: Math.max(0, Number(height) || 0)
  }
}

const gridCell = (geometry, layout, section, imageIndex, column) => ({
  position: layout.cells.length,
  imageIndex,
  sectionId: section.id,
  row: layout.rows.length,
  column,
  x: geometry.offsetX + column * (geometry.cellWidth + geometry.gap),
  y: layout.y,
  width: geometry.cellWidth,
  height: geometry.cellHeight
})

const pushGridRow = (layout, row, height) => {
  layout.rows.push(Object.assign({ y: layout.y, height }, row))
  layout.y += height + gridGap
}

const layoutSection = (layout, section, geometry) => {
  pushGridRow(
    layout,
    { kind: "header", sectionId: section.id, name: section.name, count: section.indices.length },
    geometry.headerHeight
  )
  for (let start = 0; start < section.indices.length; start += geometry.columns) {
    const chunk = section.indices.slice(start, start + geometry.columns)
    const first = layout.cells.length
    chunk.forEach((imageIndex, column) => {
      layout.cells.push(gridCell(geometry, layout, section, imageIndex, column))
    })
    pushGridRow(
      layout,
      { kind: "cells", sectionId: section.id, first, count: chunk.length },
      geometry.cellHeight
    )
  }
}

// Rows and cells with absolute y positions; cells are numbered row-major.
const gridModel = (sectionList, geometry) => {
  const layout = { rows: [], cells: [], y: 0 }
  for (const section of arrayValue(sectionList)) layoutSection(layout, section, geometry)
  return { rows: layout.rows, cells: layout.cells, height: Math.max(0, layout.y - gridGap) }
}

const cellAt = (model, position) => {
  const cells = arrayValue(model && model.cells)
  return position >= 0 && position < cells.length ? cells[position] : null
}

const nonNegative = (value) => Math.max(0, Number(value) || 0)

// The vertical span that must stay visible for a cell: its own row, plus the
// section title when the cell sits in the section's first row.
const cursorSpan = (model, cell) => {
  const headerRow = model.rows[cell.row - 1]
  const hasHeader = Boolean(headerRow) && headerRow.kind === "header"
  return { topY: hasHeader ? headerRow.y : cell.y, bottomY: cell.y + cell.height }
}

const scrollTopForCursor = (model, position, viewportHeight, scrollTop) => {
  const cell = cellAt(model, position)
  if (!cell) return 0
  const viewport = nonNegative(viewportHeight)
  const span = cursorSpan(model, cell)
  let top = nonNegative(scrollTop)
  if (span.topY < top) top = span.topY
  else if (span.bottomY > top + viewport) top = span.bottomY - viewport
  return Math.min(top, nonNegative(model.height - viewport))
}

const rowIntersects = (row, scrollTop, viewportHeight) =>
  row.y < scrollTop + viewportHeight && row.y + row.height > scrollTop

// One entry per pool slot; slot = position % poolSize is injective while the
// visible cells are a contiguous run shorter than the pool.
const gridSlots = (model, scrollTop, viewportHeight, poolSize) => {
  const size = Math.max(1, Math.floor(Number(poolSize) || 1))
  const slots = new Array(size).fill(null)
  const top = Math.max(0, Number(scrollTop) || 0)
  for (const cell of arrayValue(model && model.cells)) {
    if (!rowIntersects(cell, top, viewportHeight)) continue
    slots[cell.position % size] = Object.assign({}, cell, { y: cell.y - top })
  }
  return slots
}

const gridHeaders = (model, scrollTop, viewportHeight) => {
  const top = Math.max(0, Number(scrollTop) || 0)
  return arrayValue(model && model.rows)
    .filter((row) => row.kind === "header" && rowIntersects(row, top, viewportHeight))
    .map((row) => ({ text: row.name, count: row.count, sectionId: row.sectionId, y: row.y - top }))
}

// Prefer the cell in the given section, then the first cell showing the image.
const cellPositionForImage = (model, imageIndex, preferredSectionId) => {
  const cells = arrayValue(model && model.cells)
  const preferred = cells.find(
    (cell) => cell.imageIndex === imageIndex && cell.sectionId === preferredSectionId
  )
  const any = preferred || cells.find((cell) => cell.imageIndex === imageIndex)
  return any ? any.position : -1
}

const rowCellPosition = (model, row, column) => {
  const last = row.first + row.count - 1
  return Math.min(row.first + column, last)
}

const verticalStep = (model, cell, direction) => {
  const rows = model.rows
  for (let index = cell.row + direction; index >= 0 && index < rows.length; index += direction) {
    if (rows[index].kind === "cells") return rowCellPosition(model, rows[index], cell.column)
  }
  return cell.position
}

// dx wraps through the row-major order; dy keeps the column and stops at the ends.
const moveCursor = (model, position, dx, dy) => {
  const cells = arrayValue(model && model.cells)
  if (cells.length === 0) return -1
  const cell = cellAt(model, position) || cells[0]
  if (dy) return verticalStep(model, cell, dy > 0 ? 1 : -1)
  const step = Number(dx) || 0
  return (((cell.position + step) % cells.length) + cells.length) % cells.length
}

const sectionIdForPosition = (model, position) => {
  const cell = cellAt(model, position)
  return cell ? cell.sectionId : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    stateVersion,
    maxCollections,
    maxNameLength,
    safeThemeId,
    safeCollectionId,
    normalizeName,
    emptyState,
    safeView,
    isGridView,
    setView,
    parseStateResult,
    parseState,
    serializeState,
    backupPath,
    isFavorite,
    favoriteCount,
    toggleFavorite,
    collectionById,
    validateCollectionName,
    nextCollectionId,
    createCollection,
    renameCollection,
    deleteCollection,
    isMember,
    setMembership,
    membershipRows,
    applyMemberships,
    themeIdForImage,
    searchIndices,
    favoriteIndices,
    sections,
    gridGeometry,
    gridModel,
    scrollTopForCursor,
    gridSlots,
    gridHeaders,
    cellAt,
    cellPositionForImage,
    moveCursor,
    sectionIdForPosition
  }
}
