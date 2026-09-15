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

const createHarness = async ({ colors, legacy = "", mutateResponses = () => {} }) => {
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
  const commit = run(realGit, ["-C", repository, "rev-parse", "HEAD"]).stdout.trim()
  const tree = run(realGit, ["-C", repository, "rev-parse", "HEAD^{tree}"]).stdout.trim()
  const api = "https://api.github.com/repos/example/omarchy-safe-theme"
  const responses = {}
  const jsonResponse = (value) => ({ data: Buffer.from(JSON.stringify(value)).toString("base64") })
  responses[`${api}/commits?per_page=1`] = jsonResponse([
    { sha: commit, commit: { tree: { sha: tree } } }
  ])
  for (const directory of ["", "backgrounds"]) {
    const reference = directory ? `HEAD:${directory}` : "HEAD"
    const sha = directory
      ? run(realGit, ["-C", repository, "rev-parse", reference]).stdout.trim()
      : tree
    const entries = run(realGit, ["-C", repository, "ls-tree", "-l", "-z", reference])
      .stdout.split("\0")
      .filter(Boolean)
      .map((record) => {
        const [metadata, path] = record.split("\t")
        const [mode, type, sha, size] = metadata.trim().split(/\s+/)
        return { mode, type, sha, size: type === "blob" ? Number(size) : undefined, path }
      })
    responses[`${api}/git/trees/${sha}`] = jsonResponse({ sha, truncated: false, tree: entries })
    for (const entry of entries.filter((entry) => entry.type === "blob")) {
      const path = directory ? `${directory}/${entry.path}` : entry.path
      const contents = spawnSync(realGit, ["-C", repository, "show", `HEAD:${path}`])
      assert.equal(contents.status, 0, contents.stderr.toString())
      responses[
        `https://raw.githubusercontent.com/example/omarchy-safe-theme/${commit}/${encodeURI(path)}`
      ] = {
        data: contents.stdout.toString("base64")
      }
    }
  }
  mutateResponses(responses)
  const responsesPath = join(root, "responses.json")
  const requestsPath = join(root, "requests.jsonl")
  const launcher = join(root, "launch.py")
  await writeFile(responsesPath, JSON.stringify(responses))
  await writeFile(
    launcher,
    `import base64, io, json, os, runpy, sys, urllib.request
responses = json.load(open(os.environ["MOCK_HTTP_RESPONSES"]))
class Response(io.BytesIO):
    status = 200
    def __init__(self, fixture):
        super().__init__(base64.b64decode(fixture["data"]))
        self.headers = fixture.get("headers", {})
class Opener:
    def open(self, request, **kwargs):
        with open(os.environ["MOCK_HTTP_REQUESTS"], "a") as log:
            log.write(json.dumps(request.full_url) + "\\n")
        if request.full_url not in responses:
            raise RuntimeError("Unexpected HTTP request: " + request.full_url)
        return Response(responses[request.full_url])
urllib.request.build_opener = lambda *args: Opener()
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
`
  )

  await writeFile(
    join(mockBin, "git"),
    `#!/usr/bin/env node
const { spawnSync } = require("node:child_process")
const args = process.argv.slice(2)
if (args.some(arg => ["clone", "fetch", "cat-file", "ls-remote"].includes(arg))) {
  console.error("Remote Git and lazy object reads are forbidden")
  process.exit(99)
}
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
      spawnSync("python3", [launcher, installer, url], {
        encoding: "utf8",
        timeout: 20000,
        env: {
          ...process.env,
          PATH: `${mockBin}:${process.env.PATH}`,
          MOCK_HTTP_RESPONSES: responsesPath,
          MOCK_HTTP_REQUESTS: requestsPath,
          MOCK_OMARCHY_LOG: omarchyLog
        }
      }),
    log: async () => JSON.parse(await readFile(omarchyLog, "utf8")),
    requests: async () => (await readFile(requestsPath, "utf8")).trim().split("\n").map(JSON.parse),
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

test("rejects oversized tree metadata during the initial read", async () => {
  const harness = await createHarness({
    colors: semanticColors,
    mutateResponses: (responses) => {
      const url = Object.keys(responses).find((url) => url.includes("/git/trees/"))
      responses[url].data = Buffer.alloc(1024 * 1024 + 1, 32).toString("base64")
    }
  })
  try {
    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /byte limit/)
    assert.equal((await harness.requests()).length, 2)
    await assert.rejects(harness.log(), { code: "ENOENT" })
  } finally {
    await harness.cleanup()
  }
})

test("refuses an oversized remote blob before requesting its content", async () => {
  const harness = await createHarness({
    colors: semanticColors,
    mutateResponses: (responses) => {
      const url = Object.keys(responses).find((url) => url.includes("/git/trees/"))
      const tree = JSON.parse(Buffer.from(responses[url].data, "base64").toString())
      tree.tree.find((entry) => entry.path === "colors.toml").size = 64 * 1024 + 1
      responses[url].data = Buffer.from(JSON.stringify(tree)).toString("base64")
    }
  })
  try {
    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /Oversized theme file: colors.toml/)
    assert.equal((await harness.requests()).length, 2)
    await assert.rejects(harness.log(), { code: "ENOENT" })
  } finally {
    await harness.cleanup()
  }
})

test("rejects blob bytes that disagree with the pinned tree identity", async () => {
  const harness = await createHarness({
    colors: semanticColors,
    mutateResponses: (responses) => {
      const url = Object.keys(responses).find((url) => url.endsWith("/colors.toml"))
      const bytes = Buffer.from(responses[url].data, "base64")
      bytes[0] ^= 1
      responses[url].data = bytes.toString("base64")
    }
  })
  try {
    const result = harness.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /changed while reading/)
    await assert.rejects(harness.log(), { code: "ENOENT" })
  } finally {
    await harness.cleanup()
  }
})

test("converts a legacy Alacritty palette using the same bounded snapshot", async () => {
  const harness = await createHarness({
    legacy: `[colors.normal]\n${[
      "black",
      "red",
      "green",
      "yellow",
      "blue",
      "magenta",
      "cyan",
      "white"
    ]
      .map((name) => `${name} = "0x112233"`)
      .join("\n")}\n`
  })
  try {
    const result = harness.run()
    assert.equal(result.status, 0, result.stderr)
    assert.match((await harness.log()).colors, /color0 = "#112233"/)
    assert.equal(
      (await harness.requests()).some((url) => url.endsWith("/colors.toml")),
      false
    )
  } finally {
    await harness.cleanup()
  }
})

test("download byte budgets and redirect restrictions", () => {
  run("python3", [join(process.cwd(), "tests", "theme-install-download.py")])
})
