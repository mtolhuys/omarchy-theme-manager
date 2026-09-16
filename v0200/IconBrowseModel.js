const maxQueryLength = 120
const maxSearchResponseLength = 2 * 1024 * 1024
const maxInstallResponseLength = 16 * 1024
const defaultPageSize = 24
const contentIdPattern = /^[0-9]{1,12}$/
const sortingOptions = [
  { value: "new", label: "Newest" },
  { value: "down", label: "Downloads" },
  { value: "high", label: "Score" }
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
    .slice(0, maxQueryLength)

const optionForValue = (options, value) =>
  options.find((option) => option.value === stringValue(value))

const normalizeFilters = (filters) => {
  const input = filters && typeof filters === "object" ? filters : {}
  const sorting = stringValue(input.sorting)
  return {
    sorting: optionForValue(sortingOptions, sorting) ? sorting : "new"
  }
}

const filterKey = (filters) => normalizeFilters(filters).sorting

const sortingLabel = (sorting) =>
  (optionForValue(sortingOptions, sorting) || sortingOptions[0]).label

const filterSummary = (filters) => sortingLabel(normalizeFilters(filters).sorting)

const cloneOptions = (options) =>
  options.map((option) => ({ value: option.value, label: option.label }))

const getSortingOptions = () => cloneOptions(sortingOptions)

const safePreviewUrl = (value) => {
  const url = stringValue(value).trim()
  const plingImage = /^https:\/\/images\.pling\.com\/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+$/i
  return plingImage.test(url) && url.length <= 512 ? url : ""
}

const searchArguments = (scriptPath, query, page = 0, filters = {}, pagesize = defaultPageSize) => {
  const script = stringValue(scriptPath)
  if (!script.startsWith("/") || script.includes("\0")) return []
  const normalized = normalizeFilters(filters)
  const size = Math.max(1, Math.min(48, integerValue(pagesize, defaultPageSize) || defaultPageSize))
  const args = [
    script,
    "search",
    "--sort",
    normalized.sorting,
    "--page",
    String(integerValue(page, 0)),
    "--pagesize",
    String(size)
  ]
  const normalizedQuery = normalizeQuery(query).trim()
  if (normalizedQuery) args.push("--query", normalizedQuery)
  return args
}

const installArguments = (scriptPath, contentId) => {
  const script = stringValue(scriptPath)
  const id = stringValue(contentId)
  if (!script.startsWith("/") || script.includes("\0") || !contentIdPattern.test(id)) return []
  return [script, "install", id]
}

const plainText = (value, maximumLength) =>
  stringValue(value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .trim()
    .slice(0, maximumLength)

const iconDownloadFields = (item) => ({
  version: stringValue(item.version).slice(0, 40),
  personid: stringValue(item.personid).slice(0, 80),
  downloads: integerValue(item.downloads),
  score: integerValue(item.score),
  downloadName: stringValue(item.downloadName || item.downloadname1).slice(0, 160),
  downloadSize: integerValue(item.downloadSize || item.downloadsize1)
})

const iconRow = (item) => {
  if (!item || typeof item !== "object") return null
  const id = stringValue(item.id)
  const name = plainText(item.name, 160)
  if (!contentIdPattern.test(id) || !name) return null
  const fields = iconDownloadFields(item)
  const summary = plainText(item.summary, 280)
  return Object.assign(
    {
      id,
      filePath: "ocs-icons:" + id,
      fileName: "ocs-icons-" + id,
      thumbnailPath: safePreviewUrl(item.previewUrl || item.previewpic1),
      displayName: name,
      summary
    },
    fields,
    { ocsIcon: true, searchText: [name, summary, fields.personid, id].filter(Boolean).join(" ") }
  )
}

const parsedJson = (text) => {
  try {
    return { payload: JSON.parse(text) }
  } catch (_error) {
    return { payload: null, invalid: true }
  }
}

const searchFailure = (error) => ({ error, rows: [], meta: {} })

// The first thing wrong with a search payload, or "" when it can be read.
const searchPayloadError = (responseText, parsed) => {
  if (responseText.length > maxSearchResponseLength)
    return "Icon catalog returned an oversized response"
  if (parsed.invalid) return "Icon catalog returned invalid JSON"
  const payload = parsed.payload
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.items)) {
    return "Icon catalog returned an incomplete response"
  }
  if (payload.items.length > 48) return "Icon catalog returned too many records"
  return ""
}

const uniqueIconRows = (items) => {
  const seen = {}
  return items.reduce((result, item) => {
    const row = iconRow(item)
    if (!row || seen[row.id]) return result
    seen[row.id] = true
    result.push(row)
    return result
  }, [])
}

const searchMeta = (payload, rows) => {
  const page = integerValue(payload.page)
  const pagesize = Math.max(1, integerValue(payload.pagesize, defaultPageSize) || defaultPageSize)
  const total = integerValue(payload.totalitems)
  return { page, pagesize, total, hasMore: (page + 1) * pagesize < total && rows.length > 0 }
}

const parseSearchResponse = (text) => {
  const responseText = stringValue(text)
  const parsed =
    responseText.length > maxSearchResponseLength ? { payload: null } : parsedJson(responseText)
  const error = searchPayloadError(responseText, parsed)
  if (error) return searchFailure(error)
  const rows = uniqueIconRows(parsed.payload.items)
  return { error: "", rows, meta: searchMeta(parsed.payload, rows) }
}

const appendUniqueRows = (existingRows, incomingRows) => {
  const combined = []
  const seen = {}
  const rows = (Array.isArray(existingRows) ? existingRows : []).concat(
    Array.isArray(incomingRows) ? incomingRows : []
  )
  for (const row of rows) {
    const id = stringValue(row && row.id)
    if (!contentIdPattern.test(id) || seen[id]) continue
    seen[id] = true
    combined.push(row)
  }
  return combined
}

const installFailure = (error) => ({ error, themeName: "", themeNames: [] })

const installedThemeNames = (payload) =>
  Array.isArray(payload && payload.themeNames)
    ? payload.themeNames.map((name) => stringValue(name).trim()).filter(Boolean)
    : []

const parseInstallResponse = (text) => {
  const responseText = stringValue(text)
  if (responseText.length > maxInstallResponseLength) {
    return installFailure("Icon install returned an oversized response")
  }
  const parsed = parsedJson(responseText)
  if (parsed.invalid) return installFailure("Icon install returned invalid JSON")

  const payload = parsed.payload
  const themeNames = installedThemeNames(payload)
  const themeName = stringValue(payload && payload.themeName).trim() || themeNames[0] || ""
  if (!themeName) return installFailure("Icon install did not report a theme name")
  return { error: "", themeName, themeNames, iconsRoot: stringValue(payload.iconsRoot) }
}

const installConfirmationLines = (entry) => {
  const name = stringValue(entry.displayName || entry.name || "this icon theme").slice(0, 120)
  const file = stringValue(entry.downloadName).slice(0, 80)
  const parts = [`Download and install “${name}” into ~/.local/share/icons?`]
  if (file) parts.push(`Archive: ${file}`)
  return parts
}

const installConfirmationMessage = (entry) => {
  if (!entry) return "Install this icon theme from the internet?"
  return installConfirmationLines(entry)
    .concat(["Only continue if you trust this Pling / gnome-look.org package."])
    .join("\n")
}

const errorFromStderr = (stderr, fallback) => {
  const firstLine = stringValue(stderr)
    .split("\n")
    .map((line) => line.trim())
    .find(Boolean)
  return (firstLine || fallback || "Icon catalog request failed").slice(0, 240)
}

if (typeof module !== "undefined") {
  module.exports = {
    maxQueryLength,
    defaultPageSize,
    normalizeQuery,
    normalizeFilters,
    filterKey,
    sortingLabel,
    filterSummary,
    getSortingOptions,
    safePreviewUrl,
    searchArguments,
    installArguments,
    iconRow,
    parseSearchResponse,
    appendUniqueRows,
    parseInstallResponse,
    installConfirmationMessage,
    errorFromStderr
  }
}
