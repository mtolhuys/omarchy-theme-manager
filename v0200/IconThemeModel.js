const stringValue = (value) => String(value || "")

const skippedThemeNames = new Set(["default", "hicolor"])

const isSafeIconThemeName = (name) => {
  const value = stringValue(name).trim()
  if (!value || value.length > 255 || value.startsWith(".") || /[\/\0]/.test(value)) return false
  if (skippedThemeNames.has(value)) return false
  return /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value)
}

const safeIconPath = (value) => {
  const path = stringValue(value).trim()
  if (!path.startsWith("/") || path.length > 4096 || path.includes("\0")) return ""
  return path
}

const labelForIconTheme = (name) =>
  stringValue(name)
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (match) => match.toUpperCase())

const loadInventoryRows = (text) => {
  const seen = new Set()
  return stringValue(text)
    .split("\n")
    .reduce((themes, row) => {
      if (!row) return themes
      const [rawName, folder = "", app = "", mime = ""] = row.split("\t")
      const name = stringValue(rawName).trim()
      if (!isSafeIconThemeName(name) || seen.has(name)) return themes
      seen.add(name)
      themes.push({
        name,
        folder: safeIconPath(folder),
        app: safeIconPath(app),
        mime: safeIconPath(mime)
      })
      return themes
    }, [])
}

const iconPreviewPaths = (theme) => {
  const folder = safeIconPath(theme && theme.folder)
  const app = safeIconPath(theme && theme.app)
  const mime = safeIconPath(theme && theme.mime)
  return { folder, app, mime, preview: folder || app || mime }
}

const carouselRow = (theme, selected) => {
  const name = stringValue(theme && theme.name).trim()
  const paths = iconPreviewPaths(theme)
  return {
    filePath: paths.preview || name,
    fileName: name,
    thumbnailPath: paths.preview,
    displayName: labelForIconTheme(name),
    searchText: [name, labelForIconTheme(name)].join(" "),
    iconTheme: name,
    previewFolder: paths.folder,
    previewApp: paths.app,
    previewMime: paths.mime,
    current: selected !== "" && selected === name
  }
}

const carouselRows = (themes, currentName = "") => {
  const selected = stringValue(currentName).trim()
  const values = Array.isArray(themes) ? themes : []
  return values.map((theme) => carouselRow(theme, selected))
}

const indexForIconTheme = (rows, themeName) => {
  const selected = stringValue(themeName).trim()
  if (!selected) return 0
  const values = Array.isArray(rows) ? rows : []
  const index = values.findIndex((row) => row && row.iconTheme === selected)
  return index >= 0 ? index : 0
}

if (typeof module !== "undefined") {
  module.exports = {
    skippedThemeNames,
    isSafeIconThemeName,
    labelForIconTheme,
    loadInventoryRows,
    carouselRows,
    indexForIconTheme
  }
}
