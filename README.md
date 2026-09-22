# Omarchy Theme Manager

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://plugins.omarchy.org/plugin.html?id=io.github.mtolhuys.theme-manager)
[![OmaPicks Themes & Appearance champion](assets/omapicks-themes-appearance-2026-W39.svg)](https://omapicks.com/picks/themes-appearance/)

<p align="center">
  <img src="assets/banner.gif" alt="Omarchy Theme Manager walkthrough on Matte Black — installed themes in the carousel, the grouped grid with favorites and collections, the community theme catalog and its filters, wallpapers with a live palette, the Actions menu, icon themes with live previews, and the open wallpaper catalog" width="100%" />
</p>

<p align="center">
  Themes, sticky wallpapers/icons, open wallpaper browsing, and Pling icons inside
  Omarchy's native full-screen picker — one replacement for
  <code>omarchy.image-picker</code>.
</p>

## Features

- **Sticky per-theme memory** — wallpaper and icon overrides persist in
  `~/.local/state/io.github.mtolhuys.theme-manager/theme-manager-memory.json`
  and restore after theme switches (including native `omarchy-theme-set`).
- **Favorites and collections** — star installed themes (`Ctrl+D`), group them
  into named collections (`Ctrl+M` / `Ctrl+Shift+N` / `Ctrl+R`), and switch the
  theme picker between the carousel and a grouped grid (`Ctrl+G`) with
  Favorites, Omarchy defaults, Installed, and your collections as sections. An
  **ACTIVE** badge marks the applied theme apart from the highlighted card, and
  search also matches collection names. The chosen layout and everything else
  lives in
  `~/.local/state/io.github.mtolhuys.theme-manager/theme-collections.json`;
  nothing is written until you use it.
- **Icons mode** — `Ctrl+I` opens a live-preview grid of installed icon themes;
  the footer Icons chip shows three previews for the _highlighted_ theme
  (sticky memory or package default). **Browse icons** pulls Full Icon Themes
  from gnome-look.org / Pling (OCS) with search + sort, then installs into
  `~/.local/share/icons` and applies via sticky memory.
- **Themes ⇄ Wallpapers cross-nav** — jump with footer chips or `Ctrl+T` /
  `Ctrl+W`; **Browse** stays on the right next to Icons.
- **Theme catalog** — sticky filters (listing / availability / sort / min stars)
  in
  `~/.local/state/io.github.mtolhuys.theme-manager/theme-catalog-filters.json`
  (includes last search query), indexed fuzzy search, safe install/uninstall with confirmations, official
  Omarchy badge. Rendering stays bounded to a small reusable delegate pool even
  when the catalog reaches its 2,000-record input ceiling.
- **Wallpaper picker** — favorites (`Ctrl+D`), live palette while browsing,
  Actions hamburger (Save / All / Open folder / Reset / Remove), and a built-in
  open-art catalog. Rapid left/right navigation debounces palette extraction and
  reuses recent palettes.
- **Any image on disk** — **Open folder** / `O` browses your home directory in
  the same carousel: folder cards show a preview of what is inside and how many
  images they hold, the breadcrumb jumps to any step of the path, typing filters
  the folder, and `Ctrl+H` adds dot-entries. Choosing an image copies it into
  the theme's backgrounds and remembers it like any other wallpaper. The folder
  you were last in comes back next time.
- **Open wallpapers** — the wallpaper library bundled with Omarchy is the
  offline default. Unbranded community abstract, minimal, dark, space, and
  neon art plus Commons photography remain optional. Community sort and license
  filters map to provider queries or validated metadata. The last query and
  filters persist in
  `~/.local/state/io.github.mtolhuys.theme-manager/wallpaper-browser-filters.json`;
  downloaded images keep an attribution sidecar and appear in the local carousel.

## Requirements

- Omarchy 4.0 (Quattro)
- Python 3, ImageMagick, `curl`, `git`, `jq`, and GNU core utilities from a
  standard Omarchy install

## Install

```bash
omarchy plugin add https://github.com/mtolhuys/omarchy-theme-manager.git --enable
```

Update:

```bash
omarchy plugin update io.github.mtolhuys.theme-manager
```

The plugin declares `omarchy.clonedFrom: omarchy.image-picker`. Disabling or
removing it restores Omarchy’s built-in picker.

## Use

### Theme picker

Open the Omarchy theme switcher (`Super+Shift+Ctrl+Space`).

- Footer: **Wallpapers** on the left; **Browse themes** + Icons on the right.
- Type to search; arrows to navigate; `Enter` to install (with confirmation).
- Uninstall non-active themes with **Uninstall** / `Delete`.
- **Grid** / `Ctrl+G` shows Favorites, Omarchy defaults, Installed, and your
  collections as sections; `↑↓←→` move between cards and sections. Inside
  Favorites or a collection, `Delete` removes the theme from that list only.
  The mouse wheel scrolls the grid. Your choice of grid or carousel is
  remembered across shell restarts.
- `Ctrl+M` edits which collections the highlighted theme belongs to;
  `Ctrl+Shift+N` creates a collection with it; `Ctrl+R` renames the selected
  collection (press `Delete` inside that sheet to delete the collection).
- Catalog metadata caches for six hours — see [CATALOG.md](CATALOG.md).

### Wallpaper picker

Open the background switcher (`Super+Ctrl+Space`).

- Footer: Actions (☰) + **Themes** on the left; **Open folder**,
  **Browse wallpapers** and Icons on the right.
- Local favorites, live palette, Remove/Reset for user backgrounds.
- Open wallpapers: type to search, **Filters** / `Ctrl+F`, **Load more** / `Ctrl+N`.

### Folder browser

**Open folder** / `O` / `Ctrl+O` from the wallpaper picker.

- Folder cards show a preview and an image count; image cards behave exactly as
  local wallpapers do, live palette included.
- `Enter` opens a folder or sets an image as the wallpaper; `Backspace` (or
  `Alt+↑`, or the **Up** chip) goes back out, landing on the folder you left.
- The breadcrumb above the footer is clickable — every step back to Home is one
  click away.
- Type to filter the folder; `Ctrl+H` also lists dot-folders and dot-files.
- Browsing stays inside your home directory, which is also the only place
  Omarchy's wallpaper installer accepts sources from.

### Icons mode

Open from any picker footer Icons chip or `Ctrl+I`.

- Footer: **Back** on the left; **Icon defaults** + **Browse icons** on the right.
- **Browse icons** / `B` / `Ctrl+B` opens the Pling OCS gallery (search, sort,
  Install, Load more / `Ctrl+N`, Filters / `Ctrl+F`).

### Keyboard shortcuts

| Shortcut       | Action                                  |
| -------------- | --------------------------------------- |
| `Ctrl+T` / `T` | Themes (bare `T` when search inactive)  |
| `Ctrl+W` / `W` | Wallpapers / leave online browsing      |
| `B` / `Ctrl+B` | Browse (themes, wallpapers, or icons)   |
| `M`            | Actions menu (local wallpapers)         |
| `O` / `Ctrl+O` | Open folder (local wallpapers)          |
| `Ctrl+H`       | Show hidden files (folder browser)      |
| `Backspace`    | Up one folder (folder browser)          |
| `Ctrl+I`       | Icons mode                              |
| `Ctrl+F`       | Filters (catalog, wallpapers, or icons) |
| `Ctrl+D`       | Toggle favorite (wallpaper or theme)    |
| `Ctrl+Shift+D` | Favorites-only filter                   |
| `Ctrl+G`       | Theme carousel ⇄ grouped grid           |
| `Ctrl+M`       | Edit the theme's collections            |
| `Ctrl+Shift+N` | New collection with the theme           |
| `Ctrl+R`       | Rename the selected collection          |
| `↑` / `↓`      | Move between grid rows and sections     |
| `Ctrl+N`       | Load more (wallpapers / Browse icons)   |
| `Delete`       | Remove from collection, else uninstall  |
| `Escape`       | Clear search / back / close             |

Bare letter shortcuts stay off while filter typing is active.

## Built-in open wallpaper catalog

Wallpaper browsing uses the plugin's own bounded `wallpaper-catalog.py` helper;
there is no Aether, paid service, account, or API-key dependency:

- The Omarchy-bundled collection is the local, curated default; OpenDesktop's
  broad Abstract catalog supplies optional community styles, with obvious GNOME-,
  KDE-, distro-, OS-, and logo-branded entries excluded
- Commons photography is kept as a separate optional collection
- Community entries require a free direct image and explicit CC0, CC-BY, or
  CC-BY-SA metadata; packages and ambiguous licenses are excluded
- Omarchy, Abstract, Minimal, Dark, Space, Neon, Photos, sort, and license filters
  map directly to provider queries or validated result metadata
- The first page is generated in a 24-item batch with at most three concurrent
  thumbnail fetches. Local thumbnails are reused until their bundled source changes;
  remote queries are cached for six hours and stale results remain available during outages
- Full downloads include `<image>.attribution.json` with source, author, and license

### Trademark and bundled assets

This is an independent community plugin and is not affiliated with or endorsed
by the Omarchy project or the Omarchy Foundation. Omarchy is used here only to
describe compatibility. The plugin does not ship an Omarchy logo or redistribute
the bundled wallpaper collection; it reads the user's installed files locally,
excludes logo-named variants, and copies only the wallpaper the user selects.
Bundled image rights remain with their respective owners and upstream sources.

Theme browsing and the bundled Omarchy wallpaper collection stay available if a
remote provider is offline. The optional community and photography collections
require network access but no account or API key.

## Security and privacy

Shell plugins run unsandboxed with the current user's permissions. Review
sources before enabling.

Themes: only normalized GitHub repository URLs; bounded catalog fields;
previews from strict GitHub allowlists. One-click installation resolves one
exact commit through a 1 MiB-bounded Git smart-HTTP reference advertisement,
then downloads one source archive pinned to that SHA. It does not use GitHub's
REST API quota, a remote Git clone, a pack fetch, or a lazy blob read.

The archive is capped at 88 MiB while downloading and 160 MiB while
decompressing, with at most 4,096 entries and 4,096-byte paths beneath the exact
commit root. Redirects and HTTP content encoding are refused. All network and
archive work shares a 60-second deadline and 10-second socket timeout. Selected
palettes and images retain their per-file and 80 MiB combined image limits. A
new local theme is built from the strictly parsed palette and signature-checked
images. Scripts, links, devices, submodules, nested backgrounds, application
configs, and all other upstream content are excluded before Omarchy sees the
theme. The exact source commit is recorded in the installed theme. A catalog
badge is not a security endorsement.

GitHub errors stop the install without invoking Omarchy. If GitHub throttles a
download, the picker offers a one-shot **View source** fallback and immediately
restores **Install** afterward so the user can retry later. No GitHub credentials
are requested.

Oversized themes are not retried. The picker reports which safety limit was
crossed and switches the action to **View source**. If GitHub declares the total,
the message includes the observed size and exact excess; otherwise downloading
stops at the configured limit and the message says so explicitly.

Wallpapers: only the bundled Python helper talks to strict OpenDesktop and
Wikimedia host allowlists; responses and downloads are size-capped, ids and image
signatures are validated, every directory from `HOME` to the cache and data
locations is owner-checked/no-follow, and publication uses atomic replacement.
Downloads retain source/license attribution.

Folder browsing: `browse-folder.sh` lists one directory at a time. The
directory must resolve, through `realpath`, to the home directory or something
under it; `/etc`, a parent of `$HOME`, and a symlink pointing out of the tree
are all refused. The walk never follows symlinks, so a link planted inside the
tree cannot widen it either. A listing is capped at 240 directories, 600 images
and 1 MiB of output, previews are resolved for the first 96 directories only,
and names carrying a tab or newline are dropped rather than escaped. A chosen
image goes through the same `install-wallpaper.sh` path as a catalog download.

Icon packs: only the `icons-browse.sh` helper talks to
`api.gnome-look.org` OCS; downloads are size-capped, extracted with path-traversal
guards, and installed under `~/.local/share/icons` after confirmation.

No install hooks; no elevated privileges. Catalog installs deliberately favor
the portable palette and wallpapers over repository-specific executable or
application configuration.

## Development

```bash
npm run quality
```

Acceptance testing belongs in the disposable plugin lab:

```bash
cd ~/Projects/omarchy/plugin-lab
./bin/lab plugin ~/Projects/plugins/omarchy-theme-manager/tests/lab/acceptance.sh
./bin/lab plugin ~/Projects/plugins/omarchy-theme-manager/tests/lab/performance.sh
./bin/lab plugin ~/Projects/plugins/omarchy-theme-manager/tests/lab/rate-limit-fallback.sh
./bin/lab plugin ~/Projects/plugins/omarchy-theme-manager/tests/lab/marketing-preview.sh
```

Read [UPSTREAM.md](UPSTREAM.md) before rebasing derived picker files.
See [CHANGELOG.md](CHANGELOG.md) for 0.5.x notes.

## Remove

```bash
omarchy plugin remove io.github.mtolhuys.theme-manager
```

Removing restores the built-in picker. Installed themes and downloaded
wallpapers stay. Everything the plugin keeps of its own is in one directory,
`~/.local/state/io.github.mtolhuys.theme-manager/` (or under `$XDG_STATE_HOME`
where that is set); delete it to clear saved wallpaper favorites, theme
favorites and collections, sticky memory and the stored filters, or delete
`wallpaper-command-center.json`, `theme-collections.json`,
`theme-manager-memory.json` and the two `*-filters.json` files inside it
individually. `wallpaper-command-center.json` also holds the folder the browser
was last in and whether it was showing hidden files.

Before 0.9.0 these lived in `~/.config/omarchy/`. Upgrading copies each one
into the directory above on the picker's next start and leaves the original
where it is, so a downgrade still finds it; delete the old copies yourself once
you are sure you are staying on 0.9.0 or later.

## Credits

Wallpaper favorites, live palette previews, and carousel motion began as a
community contribution by [Fred Nix](https://github.com/nixfred).

## License

MIT. Picker code derived from Omarchy retains its upstream copyright notice in
[LICENSE](LICENSE).
