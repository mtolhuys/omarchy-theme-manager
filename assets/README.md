# Showcase assets

Lab-shot Matte Black marketing frames from the disposable Omarchy Plugin Lab
(`tests/lab/marketing-preview.sh`), then composed for README / marketplace.

- `banner.gif` — the README loop, and the only banner. Eleven scenes from a
  single capture run: themes, search, the grouped grid, the theme catalog and
  its filters, wallpapers with the live palette, Actions, icons, and the open
  wallpaper catalog. Built by `tests/lab/compose-banner.sh` from the frames
  `tests/lab/marketing-preview.sh` captures, so a release can regenerate it:

  ```bash
  ./bin/lab plugin tests/lab/marketing-preview.sh   # capture, in the lab
  tests/lab/compose-banner.sh <run-dir>             # compose, on the host
  ```

- `../preview.webp` — marketplace still (Matte Black themes carousel, bar cropped)
- `theme-library.webp` — themes carousel with Wallpapers / Browse / Icons
- `theme-grid.webp` — grouped grid: Favorites, Omarchy defaults, stars (0.8.0)
- `catalog-browse.webp` — community catalog
- `wallpaper-picker.webp` — wallpaper picker with live palette
- `actions-menu.webp` — Actions hamburger open
- `icons-mode.webp` — Icons showcase
- `open-wallpaper-catalog.webp` — the built-in open wallpaper catalog
- `safety-confirmation.webp` — install confirmation
- `omapicks-themes-appearance-2026-W39.svg` — OmaPicks Themes & Appearance
  badge for week 2026-W39, served from this repository rather than from a
  path on omapicks.com, so the README does not depend on a URL whose contents
  can change. The badge links to OmaPicks; only the image is vendored.

Screenshots are product UI from the disposable guest under Matte Black — not the
daily host desktop. Distributed under the repository MIT license.
