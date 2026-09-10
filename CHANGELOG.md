# Changelog

## 0.5.12 - 2026-09-10

- Omarchy 4.0.3 compatibility: resolve all bundled helper scripts from the
  plugin's own file location instead of the host's private `__sourceDir`
  manifest field, which third-party manifests no longer carry. Theme and icon
  inventory, wallpaper install/remove/reset, catalog loading, and the theme-set
  hook run again.

## 0.5.11 - 2026-09-08

- Fix image-selector launchers surviving a local plugin reload. Completion now
  uses a detached process, so destroying the QML loader cannot cancel the done
  marker that releases `omarchy-menu-images`.
- Add a real Plugin Lab regression that opens the theme shortcut, reloads the
  plugin, and asserts that the original launcher PID exits.

## 0.5.10 - 2026-09-06

- Fix Icons chip cold-start: after shell restart the footer showed plain
  **Icons** until an icon set was picked. Inventory previously ran in
  `Component.onCompleted` before the shell injected `manifest`, so
  `pluginScriptPath("icons-inventory.sh")` was empty and previews never
  warmed. Resolve the current icon theme early (`icons.theme`, sticky memory,
  then `gsettings`), run inventory once `manifest` is available and again on
  picker open, and populate the 3-preview showcase before first paint.

## 0.5.9 - 2026-09-06

- Footer layout: move **Browse themes** / **Browse Wallhaven** to the right,
  beside the Icons showcase; add **Wallpapers** / **Themes** cross-nav on the
  left (hamburger + Themes on local wallpapers).
- Theme carousel Icons chip previews the **highlighted theme’s** icons (sticky
  memory, else package `icons.theme`) instead of the globally applied set.
- Shortcuts: `Ctrl+T` Themes, `Ctrl+W` Wallpapers (or leave Wallhaven),
  `B`/`Ctrl+B` Browse for the current mode, `M` Actions menu on local
  wallpapers; bare letter shortcuts stay off while filter typing is active.
- Theme inventory now includes each package’s `icons.theme` for live previews.

## 0.5.8 - 2026-09-06

- Fix Remove TypeError: `root.wallpaperRemoveProc` is undefined inside its own
  `StdioCollector.onStreamFinished`, so `acceptRemovedInstalledWallpaper` never
  ran after a successful delete. Capture stdout on a root string property and
  drive accept from `onExited` when `exitCode === 0` (same pattern for Reset).
- Drop the Remove tile **before** starting `remove-wallpaper.sh`; on nonzero
  exit, restore the carousel via `reloadLocalWallpapersFromDisk`.

## 0.5.7 - 2026-09-06

- Fix live **Remove** tile drop: optimistic `dropWallpaperFromCarousel` while the
  picker stays visible, then authoritative `list.sh` rescan (no more
  `imagesLoaded=false` blank that deferred Repeater teardown).
- Carousel Repeater now uses a length + epoch model with index-bound
  `imageArray[index]` (JS-array object model left Behaviors/sourceActivated
  ghosts until Escape/reopen). Hamburger Actions → Remove shares the same path.

## 0.5.6 - 2026-09-06

- Fix empty black **Wallhaven Zp92gy**-style ghosts after Remove/reopen: remembered
  picker paths are only selected when `list.sh` actually found them. Missing or
  <4KiB remembered files are pruned from theme memory instead of being injected
  (blind inject recreated the deleted tile as a black preview).
- Row-backed wallpaper opens leave `imageDirs` empty; Remove/Reset now rebuild
  from derived theme+stock scan dirs via `list.sh` so the live carousel matches
  disk immediately (no drop-only fallback that left Repeater ghosts).
- Clear wallpaper memory on Remove when path/basename matches; treat verify
  `MISSING` / failed ensure-install as stale memory to drop.

## 0.5.5 - 2026-09-06

- Enlarge the wallpaper footer Actions hamburger (☰) slightly (`Style.font.icon`).
- Animate the Actions chevron open/closed with a short rotation
  (0° → 180°) via `Behavior` / `NumberAnimation`.

## 0.5.4 - 2026-09-06

- Icons footer chip keeps the live 3-preview showcase but drops the wide theme
  name label (name stays in the tooltip); click / Ctrl+I still opens Icons mode.
- Replace the left **Actions** word trigger with a compact hamburger (☰) +
  chevron menu, and fix popup layout (gap under trigger, padded list, full-width
  hover) so the open menu no longer clips or double-borders.

## 0.5.3 - 2026-09-06

- Restore the live **Icons** three-preview showcase chip (folder/app/mime) that
  opens Icons mode (`Ctrl+I`). The SearchableDropdown broke icon selection.
- Collapse crowded left footer chips (☆ Save / All / Reset wallpaper / Remove)
  into a single **Actions** dropdown; keep Browse Wallhaven + Icons on the right.
- Fix still-stale **Remove** tiles: clear the carousel model and force a
  `list.sh` rescan of `imageDirs` after delete/reset so ghosts vanish immediately
  without closing the picker (in-memory Repeater surgery was not enough).

## 0.5.2 - 2026-09-06

- **Remove** now drops the tile from the live carousel immediately (array-backed
  Repeater, path/basename match, row-cache sync, neighbor reselect) so deleted
  wallpapers no longer ghost until Escape/reopen.
- **Reset wallpaper** deletes ALL user/external wallpapers under
  `~/.config/omarchy/backgrounds/<theme>/`, clears wallpaper memory, applies a
  usable stock background, and purges externals from the open carousel.
- Replace the Icons footer chip/mode entry with a real **Icons SearchableDropdown**
  (`Icons · <theme>` trigger, searchable popup, applies with the same persistence).
- Skip empty/near-empty wallpaper files (<4KiB) in `list.sh` / install / reset so
  solid-black brand tiles like vantablack `omarchy.webp` (712B) cannot reappear.

## 0.5.1 - 2026-09-06

- Fix **Remove** and **Reset wallpaper**: dedicated `remove-wallpaper.sh` /
  `reset-wallpaper.sh` scripts (QML inline `find \(` was eaten by JS string
  escaping and always failed). Reset now restores stock theme backgrounds only
  and stays enabled without a memory override.
- Replace the wide three-icon Icons footer chip with a compact
  `Icons · <theme>` button matching Wallhaven/Save chip style.

## 0.5.0 - 2026-09-06

- Add Wallhaven-style **theme catalog filters** (Listing / Availability / Sort / Min stars) with stage-then-apply sheet, Ctrl+F, summary bar, and optional persistence in `~/.config/omarchy/theme-catalog-filters.json`.
- Upgrade picker search to tokenized fuzzy matching (hyphen/underscore normalization, unordered tokens, compact forms like `vangogh` ↔ `van-gogh`, light subsequence/edit-distance).
- Install Wallhaven/external wallpaper picks into `~/.config/omarchy/backgrounds/<theme>/` so they appear in the local wallpaper picker carousel.
- Add a stylish **Remove** control for user-installed theme backgrounds (deletes the file, updates memory/carousel, and retargets the current background when needed).
- Reserve independent left/right footer space so the selected wallpaper title no longer overlaps Save/Reset or Browse Wallhaven/Icons.
- Remember per-theme wallpaper and icon overrides in
  `~/.config/omarchy/theme-manager-memory.json`, restoring them after theme
  switches (including native `omarchy-theme-set`) once theme-set finishes.
- Add a stylish Icons mode with live previews of installed icon themes, sticky
  apply via `icons.theme` + `gsettings`, and keyboard access (`Ctrl+I`).
- Add one-shot **Reset wallpaper** / **Icon defaults** controls for the active
  theme without disturbing Wallhaven favorites or the wallpaper command center.

## 0.4.0 - 2026-09-04

- Add persistent, theme-aware local wallpaper favorites with favorite-first
  ordering and a favorites-only view.
- Add live wallpaper palette extraction and palette-driven picker atmosphere
  without changing the active desktop theme.
- Add native mouse controls and smooth, no-overshoot carousel motion.
- Keep palette sampling bounded to one attempt per selected source and fall
  back cleanly when an image cannot be sampled.
- Extend disposable-VM acceptance to cover favorite persistence, public
  shortcuts, live palette readiness, and the complete plugin lifecycle.
- Thanks to [Fred Nix](https://github.com/nixfred) for the wallpaper command
  center contribution.

## 0.2.0 - 2026-08-29

- Add contextual SFW Wallhaven browse, keyword search, staged filters,
  continuous pagination, full-resolution download, and apply to the native
  background-picker path.
- Delegate Wallhaven search, thumbnail caching, and downloads to Aether 4.19+
  with bounded output, strict record validation, and cache/data path checks.
- Keep theme catalog, safe uninstall, and generic image selection independent
  by classifying every row-backed picker request instead of retaining stale
  directories between invocations.
- Use Wallhaven's official palette values and document that color is a metadata
  palette match rather than dominant color or brightness.
- Version the complete QML/JavaScript runtime graph to prevent mixed Qt caches
  during updates.
- Add combined contract, model, source-quality, and disposable-VM acceptance
  coverage for both theme and wallpaper journeys.

## 0.1.0

- Add catalog browsing, search, previews, trust metadata, and confirmed theme
  installation through Omarchy's CLI.
- Add safe uninstall controls for non-active user themes.
- Deduplicate by canonical GitHub repository and block installed or stock-theme
  collisions.
- Add validated caching with offline fallback.
- Bound remote downloads, catalog records, and the QML payload, and allowlist
  GitHub preview hosts and paths.
- Preserve the native theme and background picker behavior.
- Add model tests and reproducible JavaScript, shell, QML, formatting, and
  manifest checks.
