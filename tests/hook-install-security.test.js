const test = require("node:test")
const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  rm,
  stat,
  symlink,
  writeFile
} = require("node:fs/promises")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const process = require("node:process")

const installer = join(process.cwd(), "install-hook.sh")
const HOOK_BODY = "#!/usr/bin/bash\necho theme-manager-memory\n"

const createHarness = async () => {
  const home = await mkdtemp(join(tmpdir(), "theme-manager-hook-"))
  const sourceDirectory = join(home, "plugin", "hooks", "theme-set.d")
  const source = join(sourceDirectory, "50-theme-manager-memory")
  await mkdir(sourceDirectory, { recursive: true, mode: 0o700 })
  await writeFile(source, HOOK_BODY)
  const hookDirectory = join(home, ".config", "omarchy", "hooks", "theme-set.d")
  const destination = join(hookDirectory, "50-theme-manager-memory")
  return {
    home,
    source,
    hookDirectory,
    destination,
    run: () =>
      spawnSync(installer, [source, destination], {
        encoding: "utf8",
        env: { ...process.env, HOME: home }
      }),
    cleanup: () => rm(home, { recursive: true, force: true })
  }
}

test("installs the hook through an owner-checked no-follow directory chain", async () => {
  const harness = await createHarness()
  try {
    const result = harness.run()
    assert.equal(result.status, 0, result.stderr)
    assert.equal(await readFile(harness.destination, "utf8"), HOOK_BODY)
    assert.equal((await lstat(harness.destination)).isSymbolicLink(), false)
    assert.equal((await stat(harness.destination)).mode & 0o777, 0o755)
  } finally {
    await harness.cleanup()
  }
})

test("a planted destination symlink cannot redirect the copy", async () => {
  const harness = await createHarness()
  try {
    const victim = join(harness.home, "victim.txt")
    await writeFile(victim, "do not overwrite")
    await mkdir(harness.hookDirectory, { recursive: true, mode: 0o700 })
    await symlink(victim, harness.destination)

    const result = harness.run()

    // The victim keeps its contents whatever the helper decides to do.
    assert.equal(await readFile(victim, "utf8"), "do not overwrite")
    if (result.status === 0) {
      // Replacing the link by rename is correct: the name now holds the hook.
      assert.equal((await lstat(harness.destination)).isSymbolicLink(), false)
      assert.equal(await readFile(harness.destination, "utf8"), HOOK_BODY)
    } else {
      assert.equal(await readlink(harness.destination), victim)
    }
  } finally {
    await harness.cleanup()
  }
})

test("a planted parent directory symlink cannot redirect the copy", async () => {
  const harness = await createHarness()
  try {
    const omarchy = join(harness.home, ".config", "omarchy")
    const victimDirectory = join(harness.home, "victim-directory")
    await mkdir(omarchy, { recursive: true, mode: 0o700 })
    await mkdir(victimDirectory, { mode: 0o700 })
    await symlink(victimDirectory, join(omarchy, "hooks"))

    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /symbolic link|Too many levels|Not a directory/i)
    assert.rejects(() => stat(join(victimDirectory, "theme-set.d", "50-theme-manager-memory")))
  } finally {
    await harness.cleanup()
  }
})

test("rejects a destination directory writable by another user", async () => {
  const harness = await createHarness()
  try {
    const config = join(harness.home, ".config")
    await mkdir(config, { recursive: true, mode: 0o777 })
    await chmod(config, 0o777)

    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /writable by another user/)
  } finally {
    await harness.cleanup()
  }
})

test("refuses a destination outside the theme-set hook directory", async () => {
  const harness = await createHarness()
  try {
    const elsewhere = join(harness.home, ".config", "autostart", "50-theme-manager-memory")
    const result = spawnSync(installer, [harness.source, elsewhere], {
      encoding: "utf8",
      env: { ...process.env, HOME: harness.home }
    })
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /outside the theme-set hook directory/)
    await assert.rejects(() => stat(elsewhere))
  } finally {
    await harness.cleanup()
  }
})

test("refuses a symlinked source and never dereferences it", async () => {
  const harness = await createHarness()
  try {
    const secret = join(harness.home, "secret.txt")
    const linkedSource = join(harness.home, "plugin", "hooks", "theme-set.d", "linked")
    await writeFile(secret, "secret contents")
    await symlink(secret, linkedSource)

    const result = spawnSync(installer, [linkedSource, harness.destination], {
      encoding: "utf8",
      env: { ...process.env, HOME: harness.home }
    })
    assert.notEqual(result.status, 0)
    await assert.rejects(() => stat(harness.destination))
  } finally {
    await harness.cleanup()
  }
})

test("is idempotent and rewrites only when the hook body differs", async () => {
  const harness = await createHarness()
  try {
    assert.equal(harness.run().status, 0)
    const first = await stat(harness.destination)

    assert.equal(harness.run().status, 0)
    const second = await stat(harness.destination)
    assert.equal(second.ino, first.ino, "an unchanged hook must not be republished")

    await writeFile(harness.source, HOOK_BODY + "# changed\n")
    assert.equal(harness.run().status, 0)
    const third = await stat(harness.destination)
    assert.notEqual(third.ino, first.ino, "a changed hook must be republished")
    assert.equal(await readFile(harness.destination, "utf8"), HOOK_BODY + "# changed\n")
    assert.equal(third.mode & 0o777, 0o755)
  } finally {
    await harness.cleanup()
  }
})

test("restores the executable bit when the destination lost it", async () => {
  const harness = await createHarness()
  try {
    assert.equal(harness.run().status, 0)
    await chmod(harness.destination, 0o644)

    assert.equal(harness.run().status, 0)
    assert.equal((await stat(harness.destination)).mode & 0o777, 0o755)
  } finally {
    await harness.cleanup()
  }
})

test("leaves no temporary file behind", async () => {
  const harness = await createHarness()
  try {
    assert.equal(harness.run().status, 0)
    const { readdir } = require("node:fs/promises")
    const entries = await readdir(harness.hookDirectory)
    assert.deepEqual(entries, ["50-theme-manager-memory"])
  } finally {
    await harness.cleanup()
  }
})
