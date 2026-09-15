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
- Publishing 0.5.16: restores confirmed one-click catalog installation through
  a data-only boundary rather than passing a mutable catalog URL to Omarchy
- Remote repositories are fetched bare and never checked out; the installed
  repository contains only a strictly parsed palette, bounded image formats,
  and provenance with the exact source commit
- Scripts, symlinks, submodules, application configs, nested backgrounds, and
  unknown files are excluded before `omarchy theme install` is called
- `omakit verify` reports no findings; the expected `installer` capability
  requires maintainer review
