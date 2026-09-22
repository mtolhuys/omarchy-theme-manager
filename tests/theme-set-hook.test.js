const test = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } = require("node:fs")
const { join } = require("node:path")
const { tmpdir } = require("node:os")
const process = require("node:process")

const hook = join(process.cwd(), "hooks/theme-set.d/50-theme-manager-memory")
const pluginId = "io.github.mtolhuys.theme-manager"

const sandbox = () => {
  const home = mkdtempSync(join(tmpdir(), "theme-set-hook-"))
  mkdirSync(join(home, "wallpapers"), { recursive: true })
  writeFileSync(join(home, "wallpapers/remembered.png"), "not really a png")
  return home
}

// The hook is not started by Run, so it is handed the environment a theme
// switch leaves it: nothing it needs beyond HOME.
const runHook = (home, themeName, extra = {}) =>
  execFileSync(hook, [themeName], {
    encoding: "utf8",
    env: { PATH: "/usr/bin", HOME: home, LANG: "C.UTF-8", ...extra }
  })

const memory = (home, wallpaper) => ({
  version: 1,
  themes: { catppuccin: { wallpaper: join(home, wallpaper), icons: "Papirus" } }
})

const writeState = (home, base, value) => {
  mkdirSync(base, { recursive: true })
  writeFileSync(join(base, "theme-manager-memory.json"), JSON.stringify(value))
}

const appliedIcons = (home) => {
  const path = join(home, ".local/state/omarchy/current/theme/icons.theme")
  return existsSync(path) ? readFileSync(path, "utf8").trim() : ""
}

test("restores a remembered theme from the private state root", () => {
  const home = sandbox()
  writeState(home, join(home, ".local/state", pluginId), memory(home, "wallpapers/remembered.png"))

  runHook(home, "catppuccin")
  assert.equal(appliedIcons(home), "Papirus")
})

// 0.8.x kept the file under ~/.config/omarchy. A theme switch between the
// upgrade and the picker's next start still has to find it there.
test("falls back to the 0.8.x location until the picker has migrated", () => {
  const home = sandbox()
  writeState(home, join(home, ".config/omarchy"), memory(home, "wallpapers/remembered.png"))

  runHook(home, "catppuccin")
  assert.equal(appliedIcons(home), "Papirus")
})

test("prefers the private root once both files exist", () => {
  const home = sandbox()
  writeState(home, join(home, ".config/omarchy"), {
    version: 1,
    themes: { catppuccin: { icons: "Stale-legacy" } }
  })
  writeState(home, join(home, ".local/state", pluginId), memory(home, "wallpapers/remembered.png"))

  runHook(home, "catppuccin")
  assert.equal(appliedIcons(home), "Papirus")
})

test("honours XDG_STATE_HOME for the private root", () => {
  const home = sandbox()
  const stateHome = join(home, "elsewhere/state")
  writeState(home, join(stateHome, pluginId), memory(home, "wallpapers/remembered.png"))

  runHook(home, "catppuccin", { XDG_STATE_HOME: stateHome })
  assert.equal(appliedIcons(home), "Papirus")
})

// The NUL this test used to guard against is stripped out of a bash pattern,
// which left `**` behind and rejected every theme name, so nothing was ever
// restored. The guard has to reject the unsafe names and only those.
test("rejects unsafe theme names without rejecting ordinary ones", () => {
  const home = sandbox()
  writeState(home, join(home, ".local/state", pluginId), {
    version: 1,
    themes: {
      catppuccin: { icons: "Papirus" },
      "../escape": { icons: "Traversal" },
      "a/b": { icons: "Slash" }
    }
  })

  for (const unsafe of ["../escape", "a/b", "has\tcontrol"]) {
    runHook(home, unsafe)
    assert.equal(appliedIcons(home), "", unsafe + " must restore nothing")
  }

  runHook(home, "catppuccin")
  assert.equal(appliedIcons(home), "Papirus")
})

test("succeeds with nothing remembered and no state file at all", () => {
  const home = sandbox()
  runHook(home, "catppuccin")
  assert.equal(appliedIcons(home), "")
})
