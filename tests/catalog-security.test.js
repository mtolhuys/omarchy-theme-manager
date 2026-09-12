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
  rm,
  symlink,
  writeFile
} = require("node:fs/promises")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const process = require("node:process")

const catalogScript = join(process.cwd(), "catalog.sh")
const catalogByteLimit = 8 * 1024 * 1024

const catalogEntry = (index, overrides = {}) => ({
  name: `Theme ${index}`,
  github_url: `https://github.com/example/theme-${index}`,
  canonical_github_url: `https://github.com/example/theme-${index}`,
  github_owner: "example",
  description: "A bounded test theme",
  stars: index,
  apps_json: "[]",
  security_warnings: "[]",
  preview_url: `https://raw.githubusercontent.com/example/theme-${index}/main/preview.png`,
  ...overrides
})

const officialPage = Array.from(
  { length: 21 },
  (_, index) => `<a href="https://github.com/official/theme-${index}">Theme</a>`
).join("\n")

const createHarness = async (catalogContent) => {
  const root = await mkdtemp(join(tmpdir(), "theme-manager-catalog-"))
  const mockBin = join(root, "bin")
  const catalogSource = join(root, "catalog.json")
  const officialSource = join(root, "official.html")
  const curlLog = join(root, "curl.log")
  await mkdir(mockBin)
  await writeFile(catalogSource, catalogContent)
  await writeFile(officialSource, officialPage)
  await writeFile(curlLog, "")

  const mockCurl = join(mockBin, "curl")
  await writeFile(
    mockCurl,
    `#!/usr/bin/env node
const fs = require("node:fs")
const args = process.argv.slice(2)
const outputAt = args.indexOf("--output")
if (outputAt < 0 || !args[outputAt + 1]) process.exit(2)
const source = args.at(-1).includes("themes-data.json")
  ? process.env.MOCK_CATALOG_SOURCE
  : process.env.MOCK_OFFICIAL_SOURCE
fs.copyFileSync(source, args[outputAt + 1])
fs.appendFileSync(process.env.MOCK_CURL_LOG, JSON.stringify(args) + "\\n")
`
  )
  await chmod(mockCurl, 0o755)

  return {
    home: root,
    run: () =>
      spawnSync(catalogScript, [], {
        encoding: "utf8",
        timeout: 15000,
        env: {
          ...process.env,
          HOME: root,
          PATH: `${mockBin}:${process.env.PATH}`,
          XDG_CACHE_HOME: join(root, "cache"),
          OMARCHY_THEME_CATALOG_MAX_AGE: "0",
          MOCK_CATALOG_SOURCE: catalogSource,
          MOCK_OFFICIAL_SOURCE: officialSource,
          MOCK_CURL_LOG: curlLog
        }
      }),
    curlArguments: async () =>
      (await readFile(curlLog, "utf8")).trim().split("\n").filter(Boolean).map(JSON.parse),
    cleanup: () => rm(root, { recursive: true, force: true })
  }
}

test("catalog downloads and QML output stay within hard limits", async (context) => {
  await context.test("passes explicit byte ceilings to both downloads", async () => {
    const harness = await createHarness(JSON.stringify([catalogEntry(1)]))
    try {
      const result = harness.run()
      assert.equal(result.status, 0, result.stderr)
      assert.equal(JSON.parse(result.stdout).themes.length, 1)

      const curlArguments = (await harness.curlArguments()).flat()
      assert.ok(curlArguments.includes("--max-filesize"))
      assert.ok(curlArguments.includes(String(catalogByteLimit)))
      assert.ok(curlArguments.includes(String(2 * 1024 * 1024)))
    } finally {
      await harness.cleanup()
    }
  })

  await context.test("rejects a download larger than eight MiB", async () => {
    const harness = await createHarness(Buffer.alloc(catalogByteLimit + 1, 0x20))
    try {
      assert.notEqual(harness.run().status, 0)
    } finally {
      await harness.cleanup()
    }
  })

  await context.test("rejects more than two thousand catalog records", async () => {
    const entries = Array.from({ length: 2001 }, (_, index) => catalogEntry(index))
    const harness = await createHarness(JSON.stringify(entries))
    try {
      assert.notEqual(harness.run().status, 0)
    } finally {
      await harness.cleanup()
    }
  })

  await context.test(
    "rejects a bounded input that expands past the QML output ceiling",
    async () => {
      const largeArray = JSON.stringify(["x".repeat(900)])
      const entries = Array.from({ length: 2000 }, (_, index) =>
        catalogEntry(index, {
          description: "d".repeat(400),
          apps_json: largeArray,
          security_warnings: largeArray
        })
      )
      const source = JSON.stringify(entries)
      assert.ok(Buffer.byteLength(source) < catalogByteLimit)

      const harness = await createHarness(source)
      try {
        const result = harness.run()
        assert.notEqual(result.status, 0)
        assert.match(result.stderr, /output exceeds the safe size limit/i)
      } finally {
        await harness.cleanup()
      }
    }
  )

  await context.test("does not follow a planted cache-file symlink", async () => {
    const harness = await createHarness(JSON.stringify([catalogEntry(1)]))
    try {
      const cacheDirectory = join(harness.home, "cache", "omarchy-theme-manager")
      const victim = join(harness.home, "victim.txt")
      const planted = join(cacheDirectory, "themes-data.json")
      await mkdir(cacheDirectory, { recursive: true, mode: 0o700 })
      await writeFile(victim, "do not overwrite")
      await symlink(victim, planted)

      const result = harness.run()
      assert.equal(result.status, 0, result.stderr)
      assert.equal(await readFile(victim, "utf8"), "do not overwrite")
      assert.equal((await lstat(planted)).isFile(), true)
      assert.equal((await lstat(planted)).isSymbolicLink(), false)
      assert.equal(JSON.parse(result.stdout).themes.length, 1)
    } finally {
      await harness.cleanup()
    }
  })

  await context.test("rejects a symlinked cache directory", async () => {
    const harness = await createHarness(JSON.stringify([catalogEntry(1)]))
    try {
      const cacheHome = join(harness.home, "cache")
      const victimDirectory = join(harness.home, "victim-directory")
      await mkdir(victimDirectory, { mode: 0o700 })
      await symlink(victimDirectory, cacheHome)

      const result = harness.run()
      assert.notEqual(result.status, 0)
      assert.match(result.stderr, /Not a directory|symbolic link|Too many levels/i)
    } finally {
      await harness.cleanup()
    }
  })
})
