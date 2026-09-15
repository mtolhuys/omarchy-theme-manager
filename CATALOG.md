# Catalog policy

Theme Manager combines two sources:

- [omarchytheme.com](https://omarchytheme.com/) supplies searchable discovery
  metadata and repository preview URLs through its versioned
  [theme dataset](https://github.com/limehawk/omarchy-theme-website/blob/main/src/data/themes-data.json).
- [Omarchy's official themes page](https://omarchy.org/themes/) supplies the
  **Official Omarchy listing** badge.

[omarchythemes.com](https://omarchythemes.com/) is not consumed because it does
not currently publish a documented, stable machine-readable feed.

## Identity and safety

The normalized GitHub repository URL is the primary identity. Protocol, `.git`,
trailing-slash, query, fragment, and URL-case variants collapse into one entry.
Different repositories with the same display name remain separate.

Theme Manager checks the destination slug used by Omarchy against stock themes,
user themes, and the Git origins of installed themes so availability remains
useful discovery metadata. Remote text is sanitized and bounded. Preview URLs
are accepted only from `raw.githubusercontent.com` or GitHub's
`/user-attachments/assets/` path.

Catalog records and badges are not security endorsements. Theme Manager never
passes a catalog repository directly to `omarchy theme install`. On confirmed
installation it resolves a full commit ID through GitHub's API and reads only
the root and background tree metadata and selected raw files at that commit.
No remote Git clone, pack fetch, or lazy blob download is used. It creates a separate
local repository containing a strictly parsed `colors.toml`, up to 16 bounded
wallpaper images, an optional bounded preview image, and source provenance.

The source repository is never checked out. Symlinks, submodules, nested
background trees, scripts, hooks, terminal/editor/application configs, and all
unknown content are excluded. Metadata is limited to 64 KiB for the commit and
1 MiB per nonrecursive tree. Palettes are capped at 64 KiB, individual images at
20 MiB, and combined images (including the preview) at 80 MiB. Declared blob sizes
are checked before requesting raw content, and response bytes are capped during
streaming even without a valid length header. All downloads share an aggregate
budget of 82.125 MiB, a 60-second deadline checked between reads, and a 10-second
socket timeout. Oversize detection may consume one extra byte before aborting.
Redirects and compressed responses are refused; downloaded blobs must match the
tree's SHA identity, and accepted images must match a supported file signature.
Git system/global configuration and prompts are disabled for the new local
repository. API errors, rate limits, or incomplete downloads stop installation. Omarchy
installs and applies only the newly constructed data-only repository. A missing
or malformed palette fails closed.

## Cache

Validated downloads are written atomically under
`$XDG_CACHE_HOME/omarchy-theme-manager`, normally
`~/.cache/omarchy-theme-manager`. The cache refreshes every six hours and falls
back to the last valid copy when a source is unavailable. Run
`catalog.sh --refresh` for an immediate refresh.

Downloads and the QML handoff are bounded before parsing or display: 8 MiB and
2,000 records for discovery metadata, 2 MiB and 1,000 repository links for the
official page, and 4 MiB for the final catalog payload. Oversized or malformed
fresh data is rejected; an older cache is reused only when it still passes the
same limits and validation.

## Source licensing

The `omarchytheme.com` README labels the project MIT, but its repository
currently lacks the referenced `LICENSE` file. Theme Manager fetches rather
than bundles the dataset and links previews from their source repositories.
Before marketplace submission, confirm this use with the source owner or wait
for the stated license file to be added.
