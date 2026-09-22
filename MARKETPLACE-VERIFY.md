### Verification action

Verify and publish a newer upstream commit

### Plugin ID

io.github.mtolhuys.theme-manager

### Repository URL

https://github.com/mtolhuys/omarchy-theme-manager

### Target commit

Use the full 40-character commit printed by `git rev-parse origin/main` after
the release has been pushed.

### Verification acknowledgment

- [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.

---

Maintainer notes (not required by form):

0.8.0 — Organise your themes (this submission):

- Adds local theme organisation to the existing picker: star installed themes,
  group them into user-named collections, and switch the installed-theme view
  between the carousel and a grouped grid. Everything is local to the machine.
- No new capability, host, process, timer or permission. The feature reads the
  installed-theme inventory the picker already builds and keeps one JSON file,
  `~/.config/omarchy/theme-collections.json`, written through the same atomic
  `FileView` used by the existing sticky-memory file. No helper runs for it.
- `omakit verify` reports no findings. The only capability is still `installer`
  (`install-theme.py`, `install-wallpaper.sh`), unchanged from 0.7.1.
- `omakit inspect` observes the same 497 processes, 77 hosts and 8 timers as
  0.7.1. Writes move 45 to 47: the state file and the backup beside it.
- Grid rendering reuses the picker's existing 17-delegate pool rather than
  adding delegates per theme. At most 16 cells and four section titles are on
  screen at any width or scroll offset; a test sweeps widths 320-2400px and
  every scroll offset to hold that bound.
- Themes may set `image-picker.scrim-alpha` as low as 0.5, which left picker
  text at 1.9:1 contrast against a bright window behind the overlay. Every
  surface the picker paints text on now has a minimum opacity, lifting that to
  7.8:1 while keeping each theme's own color and honouring a higher alpha where
  a theme sets one. This changes appearance in the wallpaper, icons and catalog
  modes as well as the theme picker.
- Themes missing from disk stay in the file and reappear when reinstalled; an
  unreadable file is copied to `theme-collections.json.bak` and treated as
  empty. Nothing is written until the first star, collection or layout switch.
- Collections follow the feature set of the community Extended Theme Picker,
  reimplemented on this picker's bounded delegate pool; no code was taken.

Standing notes:

- Category already Appearance; tag quickshell
- Version 0.7.0 replaces Wallhaven/Aether with a bundled, stdlib-only Python
  catalog helper backed by installed Omarchy art, explicitly licensed
  OpenDesktop images, and Wikimedia Commons photography
- No account, API key, paid service, or separately installed Aether binary is
  required; the offline Omarchy collection remains the default
- Remote requests use exact HTTPS host allowlists and size limits; responses are
  cached for six hours, thumbnails are fetched three-wide, and stale search
  results remain available during provider outages
- Community downloads require a direct image, zero price, explicit CC0/CC-BY/
  CC-BY-SA metadata, and pass image-signature validation before atomic storage
- Obvious GNOME, KDE, distro, OS, Tux, and logo-branded entries are excluded
- Addresses the resource-exhaustion blocker in issue #5344: no remote Git clone,
  pack fetch, or lazy blob download occurs
- A 1 MiB-bounded Git smart-HTTP reference advertisement resolves one exact
  default-branch commit without consuming GitHub's unauthenticated REST quota
- One archive pinned to that SHA is capped at 88 MiB compressed, 160 MiB per
  decompression pass, 4,096 entries, and 4,096 bytes per path; redirects and HTTP
  content encoding are refused
- Oversized resources produce a typed refusal with the resource and safety limit,
  plus the exact excess when it is known; the picker then offers **View source**
- The installed repository contains only a strictly parsed palette, bounded
  image formats, and provenance with the exact source commit
- Scripts, symlinks, submodules, application configs, nested backgrounds, and
  unknown files are excluded before `omarchy theme install` is called
- `omakit verify` reports no findings; the expected `installer` capability
  requires maintainer review
- Version 0.6.8 includes the catalog/search crash fix, replacing the unbounded
  GPU-backed QML Repeater with a reusable 17-delegate pool (15 visible), building
  one fuzzy-search index per query, and pre-indexing catalog search metadata
- Wallpaper navigation now debounces stale palette work and caches 24 recent
  palettes instead of immediately chaining ImageMagick work while moving
- Confirmed GitHub throttling still returns a typed temporary-failure
  status. The picker offers **View source** for that normalized repository and
  immediately restores **Install** after opening it or changing selection
- Exact-candidate local quality and marketplace checks must be rerun after the
  release commit; focused disposable Omarchy 4.0.3 evidence is recorded in the
  issue update

Transport contracts: Git's [smart HTTP protocol](https://git-scm.com/docs/gitprotocol-http)
defines the bounded reference advertisement used to resolve `HEAD`; GitHub
documents stable extracted contents for archives addressed by a commit ID in its
[source archive guidance](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives).
Python's [HTTPResponse.read1](https://docs.python.org/3/library/http.client.html#http.client.HTTPResponse.read1)
supports bounded reads. Transport errors and throttling abort installation.
