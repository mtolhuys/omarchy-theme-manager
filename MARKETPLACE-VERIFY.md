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
- Addresses the resource-exhaustion blocker in issue #5344: no remote Git clone,
  pack fetch, or lazy blob download occurs
- The GitHub API resolves one exact commit and at most two nonrecursive trees;
  metadata is capped while streaming, and declared file sizes are checked before
  any raw blob request
- Raw files are streamed within per-file and aggregate byte budgets, without
  redirects or compression, and checked against their tree blob identities
- The installed repository contains only a strictly parsed palette, bounded
  image formats, and provenance with the exact source commit
- Scripts, symlinks, submodules, application configs, nested backgrounds, and
  unknown files are excluded before `omarchy theme install` is called
- `omakit verify` reports no findings; the expected `installer` capability
  requires maintainer review
- Version 0.6.6 includes the catalog/search crash fix, replacing the unbounded
  GPU-backed QML Repeater with a reusable 17-delegate pool (15 visible), building
  one fuzzy-search index per query, and pre-indexing catalog search metadata
- Wallpaper navigation now debounces stale palette work and caches 24 recent
  palettes instead of immediately chaining ImageMagick work while moving
- A confirmed GitHub public API rate limit now returns a typed temporary-failure
  status. The picker offers **View source** for that normalized repository and
  immediately restores **Install** after opening it or changing selection
- Exact-candidate local quality and marketplace checks must be rerun after the
  release commit; focused disposable Omarchy 4.0.3 evidence is recorded in the
  issue update

Transport contracts: GitHub's [commit listing](https://docs.github.com/en/rest/commits/commits#list-commits)
defaults to the repository's default branch; its [tree endpoint](https://docs.github.com/en/rest/git/trees#get-a-tree)
is nonrecursive when the `recursive` parameter is omitted and exposes blob size,
mode, and SHA. Python's [HTTPResponse.read1](https://docs.python.org/3/library/http.client.html#http.client.HTTPResponse.read1)
supports bounded reads. API rate limits and download errors abort installation.
