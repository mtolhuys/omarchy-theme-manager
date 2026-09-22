const test = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const { mkdtempSync, rmSync, mkdirSync, writeFileSync } = require("node:fs")
const { join } = require("node:path")
const { tmpdir } = require("node:os")
const process = require("node:process")

const script = join(process.cwd(), "theme-inventory.sh")

const inventory = (home, omarchyPath) => {
  const stdout = execFileSync(script, {
    encoding: "utf8",
    env: {
      PATH: "/usr/bin",
      HOME: home,
      LANG: "C.UTF-8",
      ...(omarchyPath ? { OMARCHY_PATH: omarchyPath } : {})
    }
  })
  return stdout.split("\n").filter(Boolean)
}

const sandbox = () => {
  const root = mkdtempSync(join(tmpdir(), "theme-inventory-"))
  const stock = join(root, "omarchy/themes")
  for (const name of ["catppuccin", "nord"]) mkdirSync(join(stock, name), { recursive: true })
  writeFileSync(join(stock, "nord/icons.theme"), "Yaru-blue\n")
  mkdirSync(join(root, "home/.config/omarchy"), { recursive: true })
  return { root, home: join(root, "home"), omarchyPath: join(root, "omarchy") }
}

const addUserTheme = (home, name) => {
  mkdirSync(join(home, ".config/omarchy/themes", name), { recursive: true })
}

// A fresh Omarchy has no ~/.config/omarchy/themes until the user installs a
// theme of their own. That is a valid state: the picker still needs the stock
// themes, and a non-zero exit blanks the whole inventory.
test("lists stock themes on a fresh install with no user themes directory", () => {
  const { root, home, omarchyPath } = sandbox()
  try {
    const rows = inventory(home, omarchyPath)
    assert.deepEqual(
      rows.map((row) => row.split("\t")[0]),
      ["stock", "stock"]
    )
    assert.deepEqual(
      rows.map((row) => row.split("\t")[1]),
      ["catppuccin", "nord"]
    )
    assert.equal(rows[1].split("\t")[3], "Yaru-blue", "package icons still come through")
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test("treats an empty user themes directory the same as a missing one", () => {
  const { root, home, omarchyPath } = sandbox()
  try {
    mkdirSync(join(home, ".config/omarchy/themes"), { recursive: true })
    assert.equal(inventory(home, omarchyPath).length, 2)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test("reports both kinds once the user installs a theme", () => {
  const { root, home, omarchyPath } = sandbox()
  try {
    addUserTheme(home, "matte-black")
    const rows = inventory(home, omarchyPath)
    assert.deepEqual(
      rows.map((row) => row.split("\t").slice(0, 2).join(" ")),
      ["user matte-black", "stock catppuccin", "stock nord"]
    )
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test("succeeds with nothing to report rather than failing", () => {
  const { root, home } = sandbox()
  try {
    assert.deepEqual(inventory(home, join(root, "nowhere")), [])
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})
