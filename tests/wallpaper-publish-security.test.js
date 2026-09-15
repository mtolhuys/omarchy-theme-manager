const test = require("node:test")
const assert = require("node:assert/strict")
const { Buffer } = require("node:buffer")
const { spawnSync } = require("node:child_process")
const {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  rm,
  symlink,
  writeFile
} = require("node:fs/promises")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const process = require("node:process")

const installer = join(process.cwd(), "install-wallpaper.sh")

const createHarness = async () => {
  const home = await mkdtemp(join(tmpdir(), "theme-manager-wallpaper-"))
  const cache = join(home, ".cache", "aether", "wallpapers")
  const source = join(cache, "wallhaven-safe.png")
  await mkdir(cache, { recursive: true, mode: 0o700 })
  await writeFile(source, Buffer.alloc(5000, 0x42))
  return {
    home,
    source,
    run: () =>
      spawnSync(installer, ["tokyo-night", source], {
        encoding: "utf8",
        env: { ...process.env, HOME: home }
      }),
    cleanup: () => rm(home, { recursive: true, force: true })
  }
}

test("publishes wallpapers through an owner-checked no-follow directory", async () => {
  const harness = await createHarness()
  try {
    const result = harness.run()
    assert.equal(result.status, 0, result.stderr)
    const installed = result.stdout.trim()
    assert.equal(
      installed,
      join(harness.home, ".config", "omarchy", "backgrounds", "tokyo-night", "wallhaven-safe.png")
    )
    assert.deepEqual(await readFile(installed), await readFile(harness.source))
    assert.equal((await lstat(installed)).isSymbolicLink(), false)
  } finally {
    await harness.cleanup()
  }
})

test("a planted destination symlink cannot redirect an overwrite", async () => {
  const harness = await createHarness()
  try {
    const themeDirectory = join(harness.home, ".config", "omarchy", "backgrounds", "tokyo-night")
    const victim = join(harness.home, "victim.txt")
    const planted = join(themeDirectory, "wallhaven-safe.png")
    await mkdir(themeDirectory, { recursive: true, mode: 0o700 })
    await writeFile(victim, "do not overwrite")
    await symlink(victim, planted)

    const result = harness.run()
    assert.equal(result.status, 0, result.stderr)
    assert.equal(await readFile(victim, "utf8"), "do not overwrite")
    assert.equal(await readlink(planted), victim)
    assert.equal(result.stdout.trim().endsWith("/wallhaven-safe-2.png"), true)
    assert.equal((await lstat(result.stdout.trim())).isFile(), true)
  } finally {
    await harness.cleanup()
  }
})

test("rejects a symlinked destination directory", async () => {
  const harness = await createHarness()
  try {
    const omarchy = join(harness.home, ".config", "omarchy")
    const victimDirectory = join(harness.home, "victim-directory")
    await mkdir(omarchy, { recursive: true, mode: 0o700 })
    await mkdir(victimDirectory, { mode: 0o700 })
    await symlink(victimDirectory, join(omarchy, "backgrounds"))

    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /symbolic link|Too many levels|Not a directory/i)
    assert.deepEqual(await readFile(harness.source), Buffer.alloc(5000, 0x42))
  } finally {
    await harness.cleanup()
  }
})

test("rejects destination directories writable by another user", async () => {
  const harness = await createHarness()
  try {
    const config = join(harness.home, ".config")
    await mkdir(config, { mode: 0o777 })
    await chmod(config, 0o777)

    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /writable by another user/)
  } finally {
    await harness.cleanup()
  }
})
