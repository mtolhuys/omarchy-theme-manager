// The folder browser's pure half: the paths it is allowed to stand in, the
// breadcrumb it shows for one, and the carousel rows browse-folder.sh's TSV
// becomes. Every path that reaches the picker passes through here first, so
// the browser can never point outside the user's home directory.

const stringValue = (value) => String(value || "")

const maxPathLength = 4096
const maxRows = 1200

// One absolute path, with repeated and trailing separators collapsed and
// relative segments refused outright rather than resolved here.
const safeDir = (value) => {
  const path = stringValue(value).trim()
  if (!path.startsWith("/") || path.length > maxPathLength || path.includes("\0")) return ""
  const collapsed = path.replace(/\/{2,}/g, "/")
  const normalized = collapsed.length > 1 ? collapsed.replace(/\/+$/, "") : collapsed
  const segments = normalized.split("/").slice(1)
  if (segments.some((segment) => segment === "." || segment === "..")) return ""
  return normalized
}

const homeRoot = (home) => safeDir(home)

const isUnderHome = (dir, home) => {
  const target = safeDir(dir)
  const root = homeRoot(home)
  if (!target || !root) return false
  return target === root || target.startsWith(root + "/")
}

// The one gate: a directory the browser may open is absolute, normalized and
// inside the home directory. browse-folder.sh checks the resolved path again.
const normalizeDir = (dir, home) => (isUnderHome(dir, home) ? safeDir(dir) : "")

const defaultDir = (home) => {
  const root = homeRoot(home)
  return root ? root + "/Pictures" : ""
}

// Where the browser opens: the remembered directory when it still looks
// usable, otherwise ~/Pictures, with the home directory as the last resort.
const startDir = (remembered, home) =>
  normalizeDir(remembered, home) || defaultDir(home) || homeRoot(home)

const parentOf = (dir, home) => {
  const target = normalizeDir(dir, home)
  const root = homeRoot(home)
  if (!target || !root || target === root) return ""
  const parent = target.slice(0, target.lastIndexOf("/")) || "/"
  return normalizeDir(parent, home)
}

const basename = (path) => {
  const target = safeDir(path)
  if (!target) return ""
  return target.slice(target.lastIndexOf("/") + 1)
}

// "~", "~/Pictures/Walls" — what the user recognises, never the full path.
const displayPath = (dir, home) => {
  const target = normalizeDir(dir, home)
  const root = homeRoot(home)
  if (!target || !root) return ""
  return target === root ? "~" : "~" + target.slice(root.length)
}

// Home first, then one entry per segment below it; each carries the path that
// jumping to it opens.
const breadcrumb = (dir, home) => {
  const target = normalizeDir(dir, home)
  const root = homeRoot(home)
  if (!target || !root) return []

  const trail = [{ name: "Home", path: root }]
  if (target === root) return trail

  let walked = root
  for (const segment of target.slice(root.length + 1).split("/")) {
    if (!segment) continue
    walked += "/" + segment
    trail.push({ name: segment, path: walked })
  }
  return trail
}

const labelForName = (name) =>
  stringValue(name)
    .replace(/\.[^/.]+$/, "")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (match) => match.toUpperCase())

const countValue = (value) => {
  const count = Number(value)
  return Number.isFinite(count) && count > 0 ? Math.floor(count) : 0
}

const imageCountLabel = (count) => {
  const value = countValue(count)
  if (value === 0) return "No images"
  return value === 1 ? "1 image" : value + " images"
}

// The row a directory becomes: its own preview where it holds one, so the
// carousel shows what is inside before it is opened.
const directoryRow = (path, preview, count) => ({
  filePath: path,
  fileName: basename(path),
  thumbnailPath: safeDir(preview),
  entryKind: "folder",
  displayName: basename(path),
  searchText: labelForName(basename(path)),
  imageCount: countValue(count),
  sizeBytes: 0
})

const imageRow = (path, thumbnail, size) => ({
  filePath: path,
  fileName: basename(path),
  thumbnailPath: safeDir(thumbnail) || path,
  entryKind: "image",
  displayName: labelForName(basename(path)) || basename(path),
  searchText: basename(path),
  imageCount: 0,
  sizeBytes: countValue(size)
})

// The step back up, always the first card so leaving is where entering was.
const parentRow = (dir, home) => {
  const parent = parentOf(dir, home)
  if (!parent) return null
  return {
    filePath: parent,
    fileName: basename(parent),
    thumbnailPath: "",
    entryKind: "parent",
    displayName: displayPath(parent, home),
    searchText: "up back parent " + basename(parent),
    imageCount: 0,
    sizeBytes: 0
  }
}

const parseRow = (line, home) => {
  const fields = stringValue(line).split("\t")
  const kind = fields[0]
  const path = normalizeDir(fields[1], home)
  if (!path) return null
  if (kind === "D") return directoryRow(path, fields[2], fields[3])
  if (kind === "F") return imageRow(path, fields[2], fields[3])
  return null
}

// browse-folder.sh's output as carousel rows: the step up, then directories,
// then images, in the order the helper already sorted them.
const parseListing = (text, dir, home) => {
  const up = parentRow(dir, home)
  const rows = up ? [up] : []
  let truncated = false
  let folders = 0
  let images = 0

  for (const line of stringValue(text).split("\n")) {
    if (!line) continue
    if (line.startsWith("X\t")) {
      truncated = true
      continue
    }
    if (rows.length >= maxRows) {
      truncated = true
      break
    }
    const row = parseRow(line, home)
    if (!row) continue
    if (row.entryKind === "folder") folders += 1
    else images += 1
    rows.push(row)
  }

  return { rows, folders, images, truncated }
}

const countLabel = (count, singular, plural) => {
  const value = countValue(count)
  return value + " " + (value === 1 ? singular : plural)
}

// The line under the breadcrumb: what this directory holds, or why it is empty.
const listingSummary = (listing, filterText) => {
  const state = listing || { folders: 0, images: 0, truncated: false }
  const query = stringValue(filterText).trim()
  if (query) return "Search: " + query
  if (state.folders === 0 && state.images === 0) return "This folder has no images or subfolders"

  const parts = []
  if (state.folders > 0) parts.push(countLabel(state.folders, "folder", "folders"))
  if (state.images > 0) parts.push(countLabel(state.images, "image", "images"))
  if (state.truncated) parts.push("first results only")
  return parts.join("  ·  ")
}

const isFolderEntry = (row) =>
  Boolean(row) && (row.entryKind === "folder" || row.entryKind === "parent")

const isImageEntry = (row) => Boolean(row) && row.entryKind === "image"

// Arriving in a directory, the card worth landing on: the subfolder the user
// just stepped out of, else the first image, else the first subfolder. The
// step-up card is never it, so leaving is deliberate rather than the default.
const initialIndex = (rows, preferredPath) => {
  const values = Array.isArray(rows) ? rows : []
  const preferred = safeDir(preferredPath)

  if (preferred) {
    const returned = values.findIndex(
      (row) => row && row.entryKind === "folder" && row.filePath === preferred
    )
    if (returned >= 0) return returned
  }

  const image = values.findIndex(isImageEntry)
  if (image >= 0) return image

  const folder = values.findIndex((row) => row && row.entryKind === "folder")
  return folder >= 0 ? folder : 0
}

if (typeof module !== "undefined") {
  module.exports = {
    maxRows,
    safeDir,
    homeRoot,
    isUnderHome,
    normalizeDir,
    defaultDir,
    startDir,
    parentOf,
    basename,
    displayPath,
    breadcrumb,
    labelForName,
    imageCountLabel,
    parentRow,
    parseListing,
    listingSummary,
    isFolderEntry,
    isImageEntry,
    initialIndex
  }
}
