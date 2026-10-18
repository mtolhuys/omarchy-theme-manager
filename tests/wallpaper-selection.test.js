const test = require("node:test")
const assert = require("node:assert/strict")
const { readFileSync } = require("node:fs")
const { runInNewContext } = require("node:vm")
const ThemeMemoryModel = require("../v0200/ThemeMemoryModel.js")
const source = readFileSync("v0200/ImagePicker.qml", "utf8")
const path = "/home/example/.config/omarchy/backgrounds/test/with spaces.png"

const harness = () => {
  const writes = []
  const remembered = []
  const calls = []
  const state = {
    opened: true,
    requestSerial: 7,
    requestActive: true,
    selectionFile: "/tmp/selection",
    doneFile: "/tmp/done",
    applySerial: 0,
    wallpaperPickerActive: true,
    currentThemeName: "test",
    homeDir: "/home/example",
    pendingWallpaperSelection: null,
    wallpaperApplyError: "",
    wallpaperInstallProc: { running: false },
    wallpaperApply: {
      busy: false,
      apply: (value, serial) => {
        calls.push([value, serial])
        return true
      }
    },
    ThemeMemoryModel,
    wallhavenMode: false,
    folderMode: false,
    writeSmallFile: (file, value) => writes.push([file, value]),
    rememberWallpaperSelection: (value) => remembered.push(value),
    beginWallpaperInstall: () => true,
    syncInstalledWallpaperIntoLocalSnapshot: () => {},
    showStatus: () => {},
    focusPicker: () => {},
    Qt: { callLater: () => {} },
    cancel: () => {
      state.opened = false
    }
  }
  const functions = ["beginWallpaperApply", "completeWallpaperApply", "finishSelection"]
    .map((name) => {
      const match = source.match(new RegExp("  function " + name + "\\([^]*?\\n  \\}"))
      assert.ok(match, name)
      return match[0]
    })
    .join("\n")
  runInNewContext(functions, state)
  return { state, writes, remembered, calls }
}

test("local wallpaper selection applies explicitly before completing the caller", () => {
  const { state, writes, remembered, calls } = harness()
  state.finishSelection(path)
  assert.deepEqual(calls, [[path, 7]])
  assert.deepEqual(writes, [])
  assert.deepEqual(remembered, [])
  assert.equal(state.opened, true)
  state.completeWallpaperApply(path, 7, "")
  assert.deepEqual(writes, [
    ["/tmp/selection", path + "\n"],
    ["/tmp/done", ""]
  ])
  assert.deepEqual(remembered, [path])
  assert.equal(state.opened, false)
})

test("failed wallpaper application stays open and never completes or remembers success", () => {
  const { state, writes, remembered } = harness()
  state.finishSelection(path)
  state.completeWallpaperApply("", 7, "Background command failed")
  assert.equal(state.opened, true)
  assert.equal(state.wallpaperApplyError, "Background command failed")
  assert.deepEqual(writes, [])
  assert.deepEqual(remembered, [])
  state.finishSelection(path)
  state.completeWallpaperApply(path, 7, "")
  assert.equal(writes.length, 2)
})

test("a cancelled or replaced request cannot complete a newer picker", () => {
  for (const replacement of [{ opened: false }, { requestSerial: 8 }]) {
    const { state, writes, remembered } = harness()
    state.finishSelection(path)
    Object.assign(state, replacement)
    state.completeWallpaperApply(path, 7, "")
    assert.deepEqual(writes, [])
    assert.deepEqual(remembered, [])
  }
})

test("generic image selection preserves the filename-only contract", () => {
  const { state, writes, calls } = harness()
  state.wallpaperPickerActive = false
  state.finishSelection(path)
  assert.deepEqual(calls, [])
  assert.equal(writes.length, 2)
})
