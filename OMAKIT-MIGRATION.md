# omakit Run/Store migration — working notes

Branch: `feat/omakit-blocks`, branched from `feat/theme-collections` (0.8.0);
finished on `release/0.9.0`, which merged `run-port` into the reviewed 0.8.0
line rather than rebasing. **Shipped in 0.9.0.**

Goal: every program the plugin starts goes through the Run block, and every
file the plugin keeps of its own goes through the Store block, per
`skills/omarchy-plugin-build`. One coherent change, not a per-feature drip.

## omakit inspect numbers

Measured with `omakit inspect . --json` on a clean tree. "before" is 0.8.0 as
released (`f27014c`, tag `v0.8.0`); "after" is 0.9.0.

| pattern                         | `3800b5c` | before (`f27014c`) | after (0.9.0) | target        |
| ------------------------------- | --------- | ------------------ | ------------- | ------------- |
| process-lifecycle (no deadline) | 23        | 23                 | **0**         | 0 in QML      |
| unbounded-buffering (no cap)    | 18        | 18                 | **0**         | 0 in QML      |
| file-and-state-boundary         | 7         | 7                  | 7             | at or below 7 |
| environment-trust               | 475       | 490                | 469           | —             |
| argument-grammar                | 17        | 17                 | 17            | 17            |
| network-egress                  | 1         | 1                  | 3             | 1             |

`blocks` went from `[]` to run 0.2.1 and store 0.2.0, both `unmodified` and
`complete`, which is the row inspect raises nothing for.

Both target rows reach zero, and not only in QML: `process-lifecycle` and
`unbounded-buffering` no longer appear in the report at all. Every program the
plugin starts now has a deadline and a byte cap, and no QML file is left with a
`Process`, a `StdioCollector`, an `onDataChanged` byte count or a `.signal(9)`.

The two rows that moved the wrong way earlier came back down. `environment-trust`
is _below_ 0.8.0 (469 against 490), because inspect stops counting tool names in
a helper Run starts — it reports "50 tool names in 9 helpers started through
Run, resolved in the block's closed PATH and not counted". `file-and-state-boundary`
is back at 7: the plugin's own writes moved into Store, which is not a counted
site, so the helpers' `mkdir` calls no longer push the number up.

`network-egress` is 1 → 3, and both new sites are test fixtures, not shipped
code: `tests/theme-install-hostile.py` binds a loopback socket to serve the
hostile repositories its two tests need.

One display artifact worth knowing before it is reported as a finding: the
`environment-trust` name list shows `]]*` and `$THEME_BG_SET`. Both come from
`hooks/theme-set.d/50-theme-manager-memory` — the first from a `[[:cntrl:]]`
glob class the extractor splits on, the second from a command called by an
absolute path held in a variable, which is the opposite of a PATH lookup. The
hook's site count is unchanged from 0.8.0 (9 either way).

## Done

- `omakit add store` (pulls in run). Block files are unmodified and stay that
  way; a fix belongs in omakit, not in the copy.
- Five helper scripts replacing every `bash -c` string, since Run refuses a
  shell string: `install-hook.sh`, `verify-wallpaper.sh`, `apply-icons.sh`,
  `reset-icons.sh`, `probe-theme-lock.sh`. Wired into `lint:shell`, and the
  contract test pins each one as a `pluginScriptPath` the picker resolves.
- `ThemeManagerController.qml` — inventory, uninstall (2 sites).
- `ThemeCatalogController.qml` — catalog load, theme install (2 sites).
- `IconBrowseController.qml` — search, install (2 sites).
- `WallpaperBrowserController.qml` — search, download (2 sites).
- `WallpaperPalette.qml` — `magick` (1 site).
- `ImagePicker.qml` — 15 sites.
- Five `FileView` writes to Store, one private root, and the one-time
  migration, all through `v0200/PluginState.qml`.
- `hooks/theme-set.d/50-theme-manager-memory` reads the new root, falls back
  to the 0.8.x file until the picker has migrated, and closes its own
  environment; it runs where Run did not start it.

Validated live, not only by qmllint: the inventory round trip was driven
through a real `quickshell` process against a sandbox HOME and returned 2 user
plus 22 stock themes with `inventoryReady` true. The Store round trip and the
hook were driven the same way, against a sandbox HOME — the private directory
comes out `0700`, the file `0600`, and a missing file reports `missing` rather
than an error.

24 Run sites in QML, none of them a bare `Process`; every one has a deadline
and a byte cap, and each carries a comment naming what the deadline covers.

## A trap worth writing down: FileView inside a QtObject

The one-time migration was written, reviewed and unit-tested, and it did
nothing at all. Driving `PluginState` through a real `quickshell` against a
sandbox HOME showed why: Store correctly reported the private copy `missing`,
the legacy path was assigned, `reload()` was called — and `onLoaded` never
fired.

`QtObject` has no default property, so a `FileView` can only be held there as
`property FileView _legacy: FileView { … }`, and in that position its async
load never delivers. `blockLoading: true` fixes the load, but it blocks on
_access_, not on `reload()`, so an `onLoaded` handler still never runs. The
read has to be taken:

```qml
_legacy.path = legacyPath
_legacy.reload()
_adopt(_legacy.text())
```

Blocking is the right shape here regardless: one small JSON file, read once
per plugin start, and the migration settles before anything else looks at the
state. Every other controller in this tree is an `Item` with a plain
`FileView` child, which is why none of them hit this.

Nothing in `npm run quality` could have caught it — qmllint is happy, and the
models it feeds are pure functions with their own tests. Only the live run
found it. The contract test now pins the shape that works and refuses an
`onLoaded` handler on that view.

Had it shipped, every upgrading user would have opened 0.9.0 to find their
theme memory, collections, starred wallpapers and stored filters apparently
empty. The files were never in danger — the migration only ever reads them —
but none of it would have been on screen.

## Found while porting the hook

`hooks/theme-set.d/50-theme-manager-memory` rejected **every** theme name. The
unsafe-name guard tested `$THEME_NAME == *$'\0'*`, and bash strips the NUL out
of the pattern, leaving `**` — which matches anything. The hook returned at
that line on every theme switch, so the sticky wallpaper and icon restore has
never run on the hook path; only the picker's own in-process restore did.

Present in 0.8.0 and every release before it. Fixed here with a `case` and a
`[[:cntrl:]]` class, and covered by `tests/theme-set-hook.test.js`; seven of
its nine tests fail against 0.8.0's hook. This is the one behaviour change in
0.9.0 and it is called out in the changelog and the submission, because the
rest of the release is a refactor with a zero behaviour diff.

## Decisions

**Absolute paths and `OMARCHY_BIN`.** Run gives the child `PATH=/usr/bin` and
nothing else, but Omarchy's own commands are not in `/usr/bin`: a normal
install puts them under `~/.local/share/omarchy/bin`, and a `omarchy dev link`
checkout somewhere else entirely (this machine: `~/Projects/omarchy/core/bin`,
and `~/.local/share/omarchy` does not exist here at all). So:

- QML resolves `omarchyBinDir` from `OMARCHY_PATH`, which the shell sets in
  both layouts, falling back to the normal install path.
- A `Run` whose command is an Omarchy command uses that absolute path.
- A helper that needs one receives `OMARCHY_BIN` by name through Run's
  `environment`, and calls `"$OMARCHY_BIN/omarchy-theme-dir"`. `PATH` stays
  closed at `/usr/bin`; only the one variable the helper needs is added.

Hardcoding `~/.local/share/omarchy/bin` would have broken every dev-linked
machine, including this one, and only at run time.

**No site stays on `Quickshell.execDetached`.** The four this note once
reserved were each resolved another way, so the picker has no `execDetached`
left at all and the contract test asserts that:

- `finishDoneFile` — the completion mark is written from this process,
  synchronously, through a `blockWrites` `FileView`. No child is involved, so
  a plugin rescan destroying the overlay right after `close()` cannot lose it.
  This is what the earlier note was reaching for with a detached `touch`.
- `openWallpapersSwitcher`, `openThemesSwitcher` — a Run with a 30-minute
  deadline. A switcher the user left open for half an hour is ended, which is
  the point; one they are still using is not.
- `xdg-open` — a Run with a 30-second deadline, which covers a handler that
  waits for the browser to start and then returns.

The open question for omakit itself — Run ends the whole process group when
the leader exits, which is wrong for a command that deliberately leaves work
behind — stands on its own and no longer blocks anything here. The draft is
not in this repository; it belongs in `omakit` and is the owner's to file.

**State migration.** Store's root is the plugin's private `0700` directory
under `$XDG_STATE_HOME`, which is the point of the block, so all five files
move there in one go rather than leaving state split across two roots:

| now                                                | after                                                                 |
| -------------------------------------------------- | --------------------------------------------------------------------- |
| `~/.config/omarchy/theme-catalog-filters.json`     | `<state>/io.github.mtolhuys.theme-manager/theme-catalog-filters.json` |
| `~/.config/omarchy/wallpaper-browser-filters.json` | `…/wallpaper-browser-filters.json`                                    |
| `~/.config/omarchy/wallpaper-command-center.json`  | `…/wallpaper-command-center.json`                                     |
| `~/.config/omarchy/theme-manager-memory.json`      | `…/theme-manager-memory.json`                                         |
| `~/.config/omarchy/theme-collections.json`         | `…/theme-collections.json`                                            |

One-time migration: when a Store read reports `missing`, the legacy path is
read once and written through Store. **The originals are left untouched**, so a
downgrade to 0.8.x keeps working and nothing is destroyed if the migration is
wrong. The theme-set hook has to move with them, since it reads the memory file
by path.

The `.bak` the collections file writes when the JSON is unreadable needs a
shape Store accepts: Store writes a _value_, and the corrupt text is by
definition not valid JSON. It travels in an envelope,
`ThemeCollectionsModel.serializeBackup`:

```json
{ "version": 1, "unreadable": false, "truncated": false, "text": "…" }
```

The text is cut at 48 KiB so the envelope around it always fits Store's 64 KiB
write cap, and `truncated` says when it had to cut. `backupPath` is gone with
the path it used to build; the copy is a Store file named
`theme-collections.json.bak` beside the state file.

No schema is passed to Store for any of the five. Store then checks only that
the file is JSON, which is exactly what `FileView` plus the model's own
`parseState` did before; the models keep doing the normalising and the bounds,
and none of them changed. `unreadable` in the envelope marks the one case the
two differ on: a file that is not JSON at all comes back from Store as
`invalid` without its bytes, so the copy records that rather than the text.

Store refuses a write over 64 KiB, which `FileView` did not. Every write site
reports it — `PluginState` raises `saveFailed`, and the callers turn that into
the same status toast a failed save has always shown — rather than losing it
quietly.

## Noticed in passing, not part of this branch

`theme-inventory.sh` exited 1 when `~/.config/omarchy/themes` does not exist:
`emit_themes` ended with a bare `return` whose status is the failed `[[ -d ]]`
test, and `set -e` stopped the script before stock themes were ever emitted. A
user who had never installed a third-party theme got "Could not read the
installed theme inventory" and no stock themes either.

**Resolved on `main` in 0.8.0** (`d5f1aba`), with four regression tests in
`tests/theme-inventory.test.js` and a lab run on a fresh 4.0.3 VM. The rebase
below brings the fix onto this branch; do not port it by hand.

## Hervatten

Done. Parked on 22 Sep 2026 while 0.8.0 (`f27014c`, tag `v0.8.0`) sat in
marketplace review as issue #5344; finished the same day once that cleared.

The rebase this section planned did not happen: `release/0.9.0` merged
`origin/run-port` into the reviewed `main` instead, 16 conflict blocks, which
kept 0.8.0's history intact and let the inventory fix arrive as its own commit
rather than as a conflict to resolve by hand. The wallpaper browser was ported
again from scratch against `main`'s `wallpaper-catalog.py` provider rather than
merged, because `run-port` still targeted the old `aether --wallhaven-*`
provider with its `categories`/`order`/`atLeast` filters. `main`'s semantics won
throughout.

Gates, all green on `release/0.9.0`:

```sh
npm run quality              # 122 unit + 13 catalog, lint, format, validate
omakit verify .              # zero findings, capability set unchanged (installer)
omakit inspect . --json      # process-lifecycle 0, unbounded-buffering 0
```
