const maxHistogramEntries = 16

const clamp = (value, minimum = 0, maximum = 1) =>
  Math.max(minimum, Math.min(maximum, Number(value) || 0))

const rgbForHex = (hex) => {
  const match = String(hex || "").match(/^#?([0-9a-fA-F]{6})$/)
  if (!match) return null
  const value = match[1]
  return {
    r: parseInt(value.slice(0, 2), 16) / 255,
    g: parseInt(value.slice(2, 4), 16) / 255,
    b: parseInt(value.slice(4, 6), 16) / 255
  }
}

const hueForRgb = (rgb, maximum, delta) => {
  if (delta === 0) return 0
  let hue
  if (maximum === rgb.r) hue = ((rgb.g - rgb.b) / delta) % 6
  else if (maximum === rgb.g) hue = (rgb.b - rgb.r) / delta + 2
  else hue = (rgb.r - rgb.g) / delta + 4
  return (hue * 60 + 360) % 360
}

const metricsForHex = (hex) => {
  const rgb = rgbForHex(hex)
  if (!rgb) return null
  const maximum = Math.max(rgb.r, rgb.g, rgb.b)
  const delta = maximum - Math.min(rgb.r, rgb.g, rgb.b)
  return {
    r: rgb.r,
    g: rgb.g,
    b: rgb.b,
    hue: hueForRgb(rgb, maximum, delta),
    saturation: maximum === 0 ? 0 : delta / maximum,
    luminance: 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
  }
}

const histogramEntry = (line) => {
  const match = line.match(/^\s*([0-9]+):.*#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?\b/)
  if (!match) return null
  const hex = "#" + match[2].toUpperCase()
  const metrics = metricsForHex(hex)
  if (!metrics) return null
  return Object.assign({ count: clamp(parseInt(match[1], 10), 1, 10000000), hex }, metrics)
}

const parseHistogram = (raw) => {
  const entries = []
  for (const line of String(raw || "").split("\n")) {
    const entry = histogramEntry(line)
    if (entry) entries.push(entry)
    if (entries.length >= maxHistogramEntries) break
  }
  return entries
}

const hueDistance = (left, right) => {
  const distance = Math.abs(left - right) % 360
  return Math.min(distance, 360 - distance) / 180
}

const bestScored = (best, entry, score) => (!best || score > best.score ? { entry, score } : best)

// A colour is a usable accent when it is saturated, mid-light and contrasts with the base.
const accentScore = (entry, base, population) => {
  const usableLight = 1 - Math.min(1, Math.abs(entry.luminance - 0.58) / 0.58)
  const contrast = Math.min(1, Math.abs(entry.luminance - base.luminance) * 2.4)
  return (
    population(entry) *
    (0.18 + entry.saturation * 0.82) *
    (0.42 + usableLight * 0.58) *
    (0.62 + contrast * 0.38)
  )
}

const secondaryScore = (entry, accent, population) => {
  const separation = hueDistance(entry.hue, accent.hue)
  return population(entry) * (0.22 + entry.saturation * 0.78) * (0.48 + separation * 0.52)
}

// The entry with the highest score, or null when there is none.
const highestScored = (entries, scoreOf) =>
  entries.reduce((best, entry) => bestScored(best, entry, scoreOf(entry)), null)

const paletteFromHistogram = (raw) => {
  const entries = parseHistogram(raw)
  if (entries.length === 0) return null

  const total = entries.reduce((sum, entry) => sum + entry.count, 0)
  const population = (entry) => Math.pow(entry.count / total, 0.38)
  const base = entries.reduce((best, entry) => (entry.count > best.count ? entry : best))
  const accent = highestScored(entries, (entry) => accentScore(entry, base, population))
  const secondary = highestScored(
    entries.filter((entry) => entry.hex !== accent.entry.hex),
    (entry) => secondaryScore(entry, accent.entry, population)
  )

  return {
    base: base.hex,
    accent: accent.entry.hex,
    secondary: secondary ? secondary.entry.hex : base.hex
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    maxHistogramEntries,
    rgbForHex,
    metricsForHex,
    parseHistogram,
    hueDistance,
    paletteFromHistogram
  }
}
