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
