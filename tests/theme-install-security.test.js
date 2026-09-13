const test = require("node:test")
const assert = require("node:assert/strict")
const { Buffer } = require("node:buffer")
const { spawnSync } = require("node:child_process")
const { chmod, mkdir, mkdtemp, readFile, rm, symlink, writeFile } = require("node:fs/promises")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const process = require("node:process")

const installer = join(process.cwd(), "install-theme.py")
const realGit = "/usr/bin/git"
const sourceUrl = "https://github.com/example/omarchy-safe-theme"

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, { encoding: "utf8", ...options })
  assert.equal(result.status, 0, result.stderr)
  return result
}

const createHarness = async ({ colors, legacy = "" }) => {
  const root = await mkdtemp(join(tmpdir(), "theme-manager-install-"))
  const repository = join(root, "source")
  const mockBin = join(root, "bin")
  const omarchyLog = join(root, "omarchy.json")
  await mkdir(repository)
  await mkdir(mockBin)
  await mkdir(join(repository, "backgrounds"))
  if (colors) await writeFile(join(repository, "colors.toml"), colors)
  if (legacy) await writeFile(join(repository, "alacritty.toml"), legacy)
  await writeFile(join(repository, "preview.png"), Buffer.from("89504e470d0a1a0a0000", "hex"))
  await writeFile(join(repository, "backgrounds", "one.jpg"), Buffer.from("ffd8ff00", "hex"))
  await writeFile(join(repository, "backgrounds", "ignored.txt"), "not an image")
  await writeFile(join(repository, "install.sh"), "touch /tmp/should-never-run\n")
  await writeFile(join(root, "secret"), "secret")
  await symlink(join(root, "secret"), join(repository, "backgrounds", "linked.png"))
  run(realGit, ["init", "-q", repository])
  run(realGit, ["-C", repository, "config", "user.name", "Test"])
  run(realGit, ["-C", repository, "config", "user.email", "test@example.invalid"])
  run(realGit, ["-C", repository, "add", "--all"])
  run(realGit, ["-C", repository, "commit", "-qm", "fixture"])

  await writeFile(
    join(mockBin, "git"),
    `#!/usr/bin/env node
const { spawnSync } = require("node:child_process")
const args = process.argv.slice(2)
const index = args.indexOf(${JSON.stringify(sourceUrl)})
if (index >= 0) args[index] = new URL("file://" + process.env.MOCK_THEME_REPOSITORY).href
const result = spawnSync(${JSON.stringify(realGit)}, args, { stdio: "inherit", env: process.env })
process.exit(result.status === null ? 1 : result.status)
`
  )
  await chmod(join(mockBin, "git"), 0o755)

  await writeFile(
    join(mockBin, "omarchy"),
    `#!/usr/bin/env node
const fs = require("node:fs")
const { spawnSync } = require("node:child_process")
const args = process.argv.slice(2)
if (args[0] !== "theme" || args[1] !== "install") process.exit(2)
const repo = new URL(args[2]).pathname
const tree = spawnSync(${JSON.stringify(realGit)}, ["-C", repo, "ls-tree", "-r", "--name-only", "HEAD"], { encoding: "utf8" })
if (tree.status !== 0) process.exit(tree.status)
const show = (path) => spawnSync(${JSON.stringify(realGit)}, ["-C", repo, "show", "HEAD:" + path], { encoding: "utf8" }).stdout
fs.writeFileSync(process.env.MOCK_OMARCHY_LOG, JSON.stringify({ args, files: tree.stdout.trim().split("\\n"), colors: show("colors.toml"), source: show("SOURCE.md") }))
`
  )
  await chmod(join(mockBin, "omarchy"), 0o755)

  return {
    root,
    run: (url = sourceUrl) =>
      spawnSync(installer, [url], {
        encoding: "utf8",
        timeout: 20000,
        env: {
          ...process.env,
          PATH: `${mockBin}:${process.env.PATH}`,
          MOCK_THEME_REPOSITORY: repository,
          MOCK_OMARCHY_LOG: omarchyLog
        }
      }),
    log: async () => JSON.parse(await readFile(omarchyLog, "utf8")),
    cleanup: () => rm(root, { recursive: true, force: true })
  }
}

const semanticColors = `
mode = "dark"
accent = "#445566"
background = "#101010"
foreground = "#eeeeee"
red = "#aa0000"
green = "#00aa00"
yellow = "#aaaa00"
blue = "#0000aa"
magenta = "#aa00aa"
cyan = "#00aaaa"
unknown = "ignored"
`

test("installs only a data-only snapshot through Omarchy", async () => {
  const harness = await createHarness({ colors: semanticColors })
  try {
    const result = harness.run()
    assert.equal(result.status, 0, result.stderr)
    assert.equal(result.stdout.trim(), "safe")
    const installed = await harness.log()
    assert.deepEqual(installed.files.sort(), [
      "SOURCE.md",
      "backgrounds/one.jpg",
      "colors.toml",
      "preview.png"
    ])
    assert.doesNotMatch(installed.colors, /unknown/)
    assert.match(installed.source, /\/commit\/[0-9a-f]{40}/)
  } finally {
    await harness.cleanup()
  }
})

test("fails closed when the palette is incomplete", async () => {
  const harness = await createHarness({ colors: 'background = "#101010"\n' })
  try {
    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /complete base color set/)
  } finally {
    await harness.cleanup()
  }
})

test("refuses non-GitHub and path-bearing repository input", async () => {
  const harness = await createHarness({ colors: semanticColors })
  try {
    for (const url of ["https://example.com/theme", "https://github.com/example/theme/tree/main"]) {
      const result = harness.run(url)
      assert.equal(result.status, 2)
      assert.match(result.stderr, /normalized GitHub URL/)
    }
  } finally {
    await harness.cleanup()
  }
})
