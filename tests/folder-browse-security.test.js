const test = require("node:test")
const assert = require("node:assert/strict")
const { Buffer } = require("node:buffer")
const { spawnSync } = require("node:child_process")
const { mkdir, mkdtemp, rm, symlink, writeFile } = require("node:fs/promises")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const process = require("node:process")

const FolderBrowseModel = require("../v0200/FolderBrowseModel.js")

const browser = join(process.cwd(), "browse-folder.sh")

const image = (path, bytes = 9000) => writeFile(path, Buffer.alloc(bytes, 0x42))

const createHome = async () => {
  const home = await mkdtemp(join(tmpdir(), "theme-manager-folder-"))
  await mkdir(join(home, "Pictures", "Walls"), { recursive: true })
  await mkdir(join(home, "Pictures", "Empty"), { recursive: true })
  await mkdir(join(home, ".secret"), { recursive: true })
  await image(join(home, "Pictures", "top.webp"))
  await image(join(home, "Pictures", "Walls", "one.jpg"))
  await image(join(home, "Pictures", "Walls", "two.png"))
  await image(join(home, "Pictures", "Walls", "tiny.png"), 512)
  await image(join(home, "Pictures", "Walls", "notes.txt"), 9000)
  await image(join(home, ".secret", "hidden.png"))
  return home
}

const browse = (home, dir, ...flags) =>
  spawnSync(browser, [dir, ...flags], {
    encoding: "utf8",
    env: { ...process.env, HOME: home, XDG_CACHE_HOME: join(home, ".cache") }
  })

const rows = (result) =>
  result.stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => line.split("\t"))

test("lists subdirectories with a preview, then the images themselves", async () => {
  const home = await createHome()
  try {
    const result = browse(home, join(home, "Pictures"))
    assert.equal(result.status, 0, result.stderr)

    const listed = rows(result)
    assert.deepEqual(
      listed.map((row) => [row[0], row[1].slice(home.length)]),
      [
        ["D", "/Pictures/Empty"],
        ["D", "/Pictures/Walls"],
        ["F", "/Pictures/top.webp"]
      ]
    )

    // The empty directory has no preview and no count; the other counts only
    // the images the picker would actually be able to show.
    assert.deepEqual(listed[0].slice(2), ["", "0"])
    assert.equal(listed[1][2], join(home, "Pictures", "Walls", "one.jpg"))
    assert.equal(listed[1][3], "2")
    assert.equal(listed[2][3], "9000")
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})

test("hides dot-entries unless they are asked for", async () => {
  const home = await createHome()
  try {
    const plain = rows(browse(home, home)).map((row) => row[1])
    assert.deepEqual(plain, [join(home, "Pictures")])

    const withHidden = rows(browse(home, home, "--hidden")).map((row) => row[1])
    assert.ok(withHidden.includes(join(home, ".secret")))
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})

test("refuses any directory that resolves outside the home directory", async () => {
  const home = await createHome()
  try {
    await symlink("/etc", join(home, "escape"))

    for (const target of ["/etc", join(home, "escape"), join(home, "..")]) {
      const result = browse(home, target)
      assert.notEqual(result.status, 0, target)
      assert.match(result.stderr, /under HOME|Invalid directory/)
    }

    assert.notEqual(browse(home, "Pictures").status, 0)
    assert.notEqual(browse(home, "").status, 0)
    assert.notEqual(browse(home, join(home, "nowhere")).status, 0)
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})

test("never walks through a symlink planted inside the tree", async () => {
  const home = await createHome()
  try {
    await symlink("/etc", join(home, "Pictures", "linked"))
    await symlink("/etc/hostname", join(home, "Pictures", "linked.png"))

    const listed = rows(browse(home, join(home, "Pictures"))).map((row) => row[1])
    assert.ok(!listed.includes(join(home, "Pictures", "linked")))
    assert.ok(!listed.includes(join(home, "Pictures", "linked.png")))
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})

test("caps a directory that holds more images than the picker will list", async () => {
  const home = await createHome()
  const many = join(home, "Many")
  try {
    await mkdir(many, { recursive: true })
    await Promise.all(
      Array.from({ length: 640 }, (_unused, index) =>
        image(join(many, String(index).padStart(4, "0") + ".png"))
      )
    )

    const result = browse(home, many)
    assert.equal(result.status, 0, result.stderr)

    const listed = rows(result)
    assert.equal(listed.filter((row) => row[0] === "F").length, 600)
    assert.deepEqual(listed[listed.length - 1], ["X", "truncated"])

    // And the model reports that truncation rather than pretending it saw all.
    assert.equal(FolderBrowseModel.parseListing(result.stdout, many, home).truncated, true)
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})

test("produces rows the model accepts, with a usable thumbnail for each image", async () => {
  const home = await createHome()
  try {
    const result = browse(home, join(home, "Pictures", "Walls"))
    const listing = FolderBrowseModel.parseListing(
      result.stdout,
      join(home, "Pictures", "Walls"),
      home
    )

    assert.equal(listing.images, 2)
    assert.equal(listing.rows[0].entryKind, "parent")
    for (const row of listing.rows.slice(1)) {
      assert.equal(row.entryKind, "image")
      assert.ok(row.thumbnailPath.startsWith(home))
    }
  } finally {
    await rm(home, { recursive: true, force: true })
  }
})
