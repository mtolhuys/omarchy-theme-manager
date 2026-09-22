#!/bin/bash

# End-to-end proof for the combined Theme Manager picker. All installation,
# activation, UI interaction, downloads, and lifecycle mutations run only in
# the disposable Omarchy plugin lab guest.

# Manual visual pass for 0.8.0 (favorites, collections, grid). The automated
# steps below never open the grid or a collections sheet, so run this by hand
# on a guest with the release candidate installed and enabled, and record the
# outcome in the issue update.
#
#   Preconditions
#   - omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity ''
#     prints 0.8.0, and ~/.config/omarchy/theme-collections.json does not exist.
#   - At least one user-installed theme beside the stock ones, with the applied
#     theme visible in the carousel.
#
#   Carousel (Super+Shift+Ctrl+Space)
#   1. The applied theme's card carries an ACTIVE pill at its bottom-left corner
#      even while another card is highlighted; the highlight border stays on the
#      highlighted card only.
#   2. Ctrl+D on the highlighted theme toasts "Starred", draws a star at the
#      card's top-right, and creates theme-collections.json holding exactly
#      {"version":1,"favorites":[<id>],"collections":[]}; runtimeState reports
#      themeFavoriteCount 1.
#   3. Ctrl+Shift+D narrows the carousel to starred themes and shows the
#      "Starred themes only" hint; Ctrl+Shift+D again restores every theme. With
#      no stars the toggle only toasts "No starred themes yet".
#   4. Delete on a theme still opens the uninstall confirmation; Escape cancels.
#
#   Grid (Ctrl+G or the footer Grid chip)
#   5. Sections read Favorites, Omarchy defaults, Installed in that order, each
#      with a count on the right; every card has a name caption, the applied
#      theme its ACTIVE pill at the top-left, starred themes a star. Slices,
#      skew and carousel motion are gone; nothing renders outside the card.
#   5b. The grid is centred: the gap left of the first column equals the gap
#      right of the last, and each section's count sits at the right edge of the
#      last column, not out at the card edge. Check on a screen narrower than
#      ~1900px too, where the card clamps and the carousel overhangs it.
#   5c. With more themes than fit, the mouse wheel scrolls the grid and the
#      highlight stays on its card; the next arrow key brings it back into view.
#      No card is ever blank or duplicated while scrolling.
#   6. Left/Right/Tab walk cards across section boundaries; Up/Down keep the
#      column and stop at the first and last row; the footer label follows the
#      highlight; Enter applies the highlighted theme as in the carousel.
#   7. Ctrl+Shift+N, type Work, Enter: a Work section appears last containing
#      the highlighted theme, the highlight moves into it, and the hint line
#      ends with "Delete removes from Work"; runtimeState reports
#      themeCollection "c1" and themeCollectionCount 1.
#   8. Ctrl+M lists Favorites then Work with filled/empty marks; Space toggles,
#      Up/Down move, Enter saves, Escape cancels without writing.
#   9. Delete inside Work removes the theme from Work only (toast, no dialog);
#      the emptied section disappears and the highlight lands on the same theme
#      elsewhere. Delete inside Favorites unstars. Delete inside Omarchy defaults
#      or Installed opens the uninstall confirmation.
#  10. Ctrl+R on a Work card opens the rename sheet prefilled; a blank or
#      duplicate name shows the reason and Enter does nothing. Delete inside the
#      sheet turns it into the red "Delete Work?" state; Escape keeps the
#      collection, Enter removes it. Ctrl+R outside a user collection only toasts
#      "Highlight a collection in the grid first".
#  11. Typing wo keeps only themes whose name or collection matches; Escape
#      clears the search and every section returns.
#  12. Ctrl+G returns to the carousel on the same highlighted theme; reopening
#      the picker keeps the last layout and resets favorites-only. The layout
#      also survives omarchy-shell restarting: switch to the grid, restart the
#      shell, reopen the picker, and it is still the grid; theme-collections.json
#      reads "view": "grid".
#
#   Readability (run on a light theme and again with a white page behind the
#   overlay, since a theme may set image-picker.scrim-alpha as low as 0.5)
#  R1. With a maximised white page behind it, every footer control reads as a
#      filled control, not an outline around the page: Wallpapers, Grid/Carousel,
#      Browse themes, Icons, Uninstall, and the Actions hamburger in wallpaper
#      mode. No page text shows through a button interior.
#  R2. The centred theme name, the hint line, section titles and their counts,
#      the grid captions and the status toast are all legible against that page.
#  R3. The uninstall confirmation, the collections sheets and the filter sheets
#      dim the picker behind them; none of them lets the page show through.
#  R4. Repeat on a theme whose shell.toml raises image-picker.scrim-alpha above
#      the floor (or set it to 0.98 by hand): the picker keeps that theme's
#      heavier wash rather than being pinned to the floor.
#
#   Storage
#  13. Uninstall a starred theme: its id stays in theme-collections.json while
#      the card leaves Favorites; reinstalling it brings the star back.
#  14. Write "{ not json" over theme-collections.json and run
#      omarchy-shell shell rescanPlugins: theme-collections.json.bak holds the
#      broken text, runtimeState reports themeFavoriteCount 0, and the next
#      Ctrl+D rewrites the main file as valid JSON.
#  15. Remove both files, reopen the picker, browse, search and apply a theme
#      without starring anything and without pressing Ctrl+G: no
#      theme-collections.json appears. Pressing Ctrl+G alone does create it,
#      holding only the remembered view with empty favorites and collections.

omarchy_host_test() {
  local initial_thumb_count install_source install_source_q plugin_root version
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=${THEME_MANAGER_INSTALL_SOURCE:-/tmp/omarchy-theme-manager}
  printf -v install_source_q '%q' "$install_source"
  version=$(jq -r '.version' "$plugin_root/manifest.json")

  log "Staging Omarchy Theme Manager"
  tar \
    --exclude=.git \
    --exclude=.idea \
    --exclude=node_modules \
    -C "$plugin_root" -cf - . | ssh_guest \
    "rm -rf /tmp/omarchy-theme-manager && \
     mkdir -p /tmp/omarchy-theme-manager && \
     tar -C /tmp/omarchy-theme-manager -xf -"
  ssh_guest "git -C /tmp/omarchy-theme-manager init -q && \
    git -C /tmp/omarchy-theme-manager add . && \
    git -C /tmp/omarchy-theme-manager \
      -c user.name=PluginLab \
      -c user.email=lab@invalid \
      commit -qm candidate"

  ssh_session "python3 --version && magick -version" || return 1

  # The suite drives the guest for minutes at a time through virtual input,
  # which hypridle does not always count as activity. Without this the screen
  # locks partway through and every later keypress goes to hyprlock, which
  # shows up as an unrelated step failing wherever the timer happens to land.
  ssh_session "omarchy-toggle-idle stay-awake" || return 1

  # 0.9.0 keeps the plugin's own files in its private 0700 directory under the
  # XDG state base (the omakit Store block) instead of ~/.config/omarchy.
  # shellcheck disable=SC2016  # expanded in the guest, not here
  local state_root='${XDG_STATE_HOME:-$HOME/.local/state}/io.github.mtolhuys.theme-manager'

  # Seed a 0.8.x state file so the first picker start has something to adopt.
  # The value is deliberately one the plugin would never invent on its own.
  ssh_session "mkdir -p \"\$HOME/.config/omarchy\" && \
    printf '%s' '{\"version\":1,\"themes\":{\"lab-legacy-theme\":{\"icons\":\"LabLegacyIcons\"}}}' \
      >\"\$HOME/.config/omarchy/theme-manager-memory.json\" && \
    sha256sum \"\$HOME/.config/omarchy/theme-manager-memory.json\" \
      >/tmp/theme-manager-legacy-memory.sha256" || return 1

  ssh_session "omarchy-plugin-add $install_source_q --enable --yes" || return 1
  wait_for_guest_state "Theme Manager $version is installed" 25 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     jq -e '.version == \"$version\" and \
       .entryPoints.overlay == \"v0200/ImagePicker.qml\" and \
       .omarchy.clonedFrom == \"omarchy.image-picker\"' \
       \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/manifest.json\"" || return 1
  if ! wait_for_guest_state "Theme Manager $version is loaded" 25 ssh_session \
    "[[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"$version\" ]]"; then
    ssh_session "journalctl --user --since '-2 minutes' --no-pager | tail -n 500" \
      >"$RUN_DIR/theme-manager-shell-load-failure.log" 2>&1 || true
    return 1
  fi
  wait_for_guest_state "the Theme Manager hook is installed" 15 ssh_session \
    "test -x \"\$HOME/.config/omarchy/hooks/theme-set.d/50-theme-manager-memory\"" || return 1

  # The one-time migration: 0.8.x's file is adopted into the private state
  # root, mode 0700, and the original is left byte-identical so a downgrade
  # still finds it.
  wait_for_guest_state "the 0.8.x state file is adopted into the private root" 25 ssh_session \
    "jq -e '.themes[\"lab-legacy-theme\"].icons == \"LabLegacyIcons\"' \
       \"$state_root/theme-manager-memory.json\" && \
     [[ \$(stat -c %a \"$state_root\") == 700 ]] && \
     [[ \$(stat -c %a \"$state_root/theme-manager-memory.json\") == 600 ]] && \
     sha256sum --check --status /tmp/theme-manager-legacy-memory.sha256" || return 1

  press meta_l-shift-ctrl-spc || return 1
  wait_for_guest_state "the native theme shortcut opens Theme Manager's theme mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\" and .images > 0 and \
         .iconsInventoryCount > 0 and .footerIconHasPreviews == true' && \
     hyprctl -j layers | jq -e \
       '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length >= 1'" || return 1
  capture_console "success-theme-manager-01-installed-themes" || return 1

  ssh_session "cache_dir=\"\$HOME/.cache/omarchy-theme-manager\" && \
    victim=\"\$HOME/theme-manager-catalog-victim\" && \
    mkdir -p \"\$cache_dir\" && \
    rm -f \"\$cache_dir/themes-data.json\" && \
    printf 'untouched' >\"\$victim\" && \
    ln -s -- \"\$victim\" \"\$cache_dir/themes-data.json\"" || return 1
  press ctrl-b || return 1
  wait_for_guest_state "Ctrl+B opens the bounded theme catalog" 75 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"catalog\" and .images > 0' && \
     [[ \$(cat \"\$HOME/theme-manager-catalog-victim\") == untouched ]] && \
     [[ -f \"\$HOME/.cache/omarchy-theme-manager/themes-data.json\" && \
        ! -L \"\$HOME/.cache/omarchy-theme-manager/themes-data.json\" ]]" || return 1
  capture_console "success-theme-manager-02-theme-catalog" || return 1

  ssh_session "find \"\$HOME/.config/omarchy/themes\" -mindepth 1 -maxdepth 1 -type d | \
    wc -l > /tmp/theme-manager-theme-count-before-install" || return 1
  press ret || return 1
  wait_for_guest_state "Return opens the safe theme installation confirmation" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"catalog\" and .catalogInstallConfirmationOpen == true'" || return 1
  capture_console "success-theme-manager-02b-theme-install-confirmation" || return 1
  press ret || return 1
  wait_for_guest_state "confirming installs and applies only a sanitized exact snapshot" 90 ssh_session \
    "count=\$(find \"\$HOME/.config/omarchy/themes\" -mindepth 1 -maxdepth 1 -type d | wc -l) && \
     before=\$(cat /tmp/theme-manager-theme-count-before-install) && \
     (( count == before + 1 )) && \
     theme=\$(cat \"\$HOME/.local/state/omarchy/current/theme.name\") && \
     dir=\"\$HOME/.config/omarchy/themes/\$theme\" && \
     [[ -f \"\$dir/colors.toml\" && -f \"\$dir/SOURCE.md\" && -d \"\$dir/.git\" ]] && \
     grep -Eq '/commit/[0-9a-f]{40}' \"\$dir/SOURCE.md\" && \
     ! find \"\$dir\" -path \"\$dir/.git\" -prune -o -type l -print -quit | grep -q . && \
     ! find \"\$dir\" -path \"\$dir/.git\" -prune -o -type f \
       ! -name colors.toml ! -name SOURCE.md ! -name preview.png \
       ! -path \"\$dir/backgrounds/*.png\" ! -path \"\$dir/backgrounds/*.jpg\" \
       ! -path \"\$dir/backgrounds/*.jpeg\" ! -path \"\$dir/backgrounds/*.gif\" \
       ! -path \"\$dir/backgrounds/*.webp\" ! -path \"\$dir/backgrounds/*.bmp\" \
       -print -quit | grep -q ." || return 1

  ssh_session "rm -rf \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\"" || return 1
  press meta_l-ctrl-spc || return 1
  wait_for_guest_state "the background shortcut opens wallpaper mode, not theme mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and .images > 0 and \
         .paletteReady == true and (.paletteSampledPath | length > 0)'" || return 1
  capture_console "success-theme-manager-03-local-wallpapers" || return 1

  press ctrl-d || return 1
  wait_for_guest_state "Ctrl+D persists the selected wallpaper as a favorite" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.currentFavorite == true and .favoriteCount == 1' && \
     jq -e '.version == 2 and (.favorites | length) == 1' \
       \"$state_root/wallpaper-command-center.json\"" || return 1

  press esc || return 1
  wait_for_guest_state "the wallpaper picker closes with its favorite persisted" 20 ssh_session \
    "hyprctl -j layers | jq -e \
      '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1
  press meta_l-ctrl-spc || return 1
  wait_for_guest_state "the favorite survives a real picker reopen" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and \
         .layoutSettled == true and .currentFavorite == true and .favoriteCount == 1'" || return 1

  press ctrl-shift-d || return 1
  wait_for_guest_state "Ctrl+Shift+D enables favorites-only mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.favoritesOnly == true and .currentFavorite == true'" || return 1
  capture_console "success-theme-manager-04-favorite-wallpaper" || return 1
  press ctrl-shift-d || return 1
  press ctrl-d || return 1
  wait_for_guest_state "the favorite can be removed without leaving hidden state" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.favoritesOnly == false and .currentFavorite == false and .favoriteCount == 0' && \
     jq -e '.version == 2 and (.favorites | length) == 0' \
       \"$state_root/wallpaper-command-center.json\"" || return 1

  # Folder browsing: the picker reaches any image the user keeps under HOME,
  # and nothing above or beside it.
  local plugin_dir="\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager"
  ssh_session "mkdir -p \"\$HOME/Pictures/lab-walls\" \"\$HOME/Pictures/.lab-hidden\" && \
    stock=\$(find \"\$HOME/.local/state/omarchy/current/theme/backgrounds\" -maxdepth 1 \
      -type f -size +4095c \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
      -o -iname '*.webp' \\) | sort | head -1) && \
    [[ -n \$stock ]] && \
    cp -- \"\$stock\" \"\$HOME/Pictures/lab-walls/lab-pick.\${stock##*.}\" && \
    cp -- \"\$stock\" \"\$HOME/Pictures/.lab-hidden/hidden-pick.\${stock##*.}\" && \
    ln -sfn /etc \"\$HOME/Pictures/lab-escape\"" || return 1

  press o || return 1
  wait_for_guest_state "O opens the folder browser in the user's picture folder" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.opened == true and .mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures\") and .folderShowHidden == false and \
         .folderCanGoUp == true and .images == 2'" || return 1
  capture_console "success-theme-manager-04b-folder-browser" || return 1

  wait_for_guest_state "the listing helper refuses and never follows a link out of HOME" 20 ssh_session \
    "if \"$plugin_dir/browse-folder.sh\" \"\$HOME/Pictures/lab-escape\" >/dev/null 2>&1; then \
       exit 1; fi; \
     if \"$plugin_dir/browse-folder.sh\" /etc >/dev/null 2>&1; then exit 1; fi; \
     if \"$plugin_dir/browse-folder.sh\" \"\$HOME/Pictures\" | grep -q lab-escape; then \
       exit 1; fi; \
     exit 0" || return 1

  press ctrl-h || return 1
  wait_for_guest_state "Ctrl+H also lists hidden folders and remembers the choice" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"folder\" and .folderShowHidden == true and .images == 3' && \
     jq -e '.showHidden == true' \"$state_root/wallpaper-command-center.json\"" || return 1
  press ctrl-h || return 1
  wait_for_guest_state "Ctrl+H hides them again" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"folder\" and .folderShowHidden == false and .images == 2'" || return 1

  for key in l a b; do
    press "$key" || return 1
  done
  wait_for_guest_state "typing filters the folder listing down to one card" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and .matchingImages == 1 and \
         .selectedPath == (\$home + \"/Pictures/lab-walls\")'" || return 1

  press ret || return 1
  wait_for_guest_state "Return opens the folder and lands on the first image in it" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures/lab-walls\") and \
         (.selectedPath | startswith(\$home + \"/Pictures/lab-walls/lab-pick.\")) and \
         .paletteReady == true'" || return 1
  capture_console "success-theme-manager-04c-folder-image" || return 1

  press backspace || return 1
  wait_for_guest_state "Backspace steps back out onto the folder just left" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures\") and \
         .selectedPath == (\$home + \"/Pictures/lab-walls\")'" || return 1

  press ret || return 1
  wait_for_guest_state "the folder opens again" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures/lab-walls\")'" || return 1

  press ret || return 1
  wait_for_guest_state "a file chosen from disk is copied in, applied and remembered" 55 ssh_session \
    "theme=\$(cat \"\$HOME/.local/state/omarchy/current/theme.name\") && \
     background=\$(readlink -f \"\$HOME/.local/state/omarchy/current/background\") && \
     [[ \$background == \"\$HOME/.config/omarchy/backgrounds/\$theme/lab-pick.\"* ]] && \
     [[ -f \$background && ! -L \$background ]] && \
     cmp -s \"\$background\" \"\$(find \"\$HOME/Pictures/lab-walls\" -maxdepth 1 -type f | head -1)\" && \
     jq -e --arg theme \"\$theme\" --arg background \"\$background\" \
       '.themes[\$theme].wallpaper == \$background' \
       \"$state_root/theme-manager-memory.json\" && \
     jq -e --arg home \"\$HOME\" '.folder == (\$home + \"/Pictures/lab-walls\")' \
       \"$state_root/wallpaper-command-center.json\" && \
     hyprctl -j layers | jq -e \
       '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1
  capture_console "success-theme-manager-04d-folder-applied" || return 1

  press meta_l-ctrl-spc || return 1
  wait_for_guest_state "the wallpaper picker reopens on the local wallpapers" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and .layoutSettled == true'" || return 1
  # layoutSettled flips one callLater before the key handler takes focus, and a
  # chord sent into that window is dropped by Qt rather than by the picker.
  ssh_session "sleep 1" || return 1
  press ctrl-o || return 1
  wait_for_guest_state "folder browsing resumes where it was left" 30 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures/lab-walls\")'" || return 1
  press esc || return 1
  wait_for_guest_state "Escape returns from folder browsing to the local wallpapers" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and .images > 0'" || return 1

  # A remembered folder that will not read must cost one listing, never the
  # user's place: the browser steps up a level and the folder stays recorded,
  # so the next visit tries it again.
  ssh_session "mv \"\$HOME/Pictures/lab-walls\" \"\$HOME/Pictures/lab-walls-away\"" || return 1
  press ctrl-o || return 1
  wait_for_guest_state "an unreadable folder steps up instead of losing the place" 30 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures\")' && \
     jq -e --arg home \"\$HOME\" '.folder == (\$home + \"/Pictures/lab-walls\")' \
       \"$state_root/wallpaper-command-center.json\"" || return 1

  ssh_session "mv \"\$HOME/Pictures/lab-walls-away\" \"\$HOME/Pictures/lab-walls\"" || return 1
  press esc || return 1
  ssh_session "sleep 1" || return 1
  press ctrl-o || return 1
  wait_for_guest_state "and the next visit lands in it again" 30 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e --arg home \"\$HOME\" '.mode == \"folder\" and \
         .folderDirectory == (\$home + \"/Pictures/lab-walls\")'" || return 1
  press esc || return 1
  wait_for_guest_state "folder browsing closes back onto the local wallpapers" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and .images > 0'" || return 1

  press ctrl-b || return 1
  wait_for_guest_state "Ctrl+B enters the built-in open wallpaper catalog" 55 ssh_session \
    "test -d \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" && \
     find \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" -maxdepth 1 -type f -print -quit | grep -q . && \
     omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallhaven\" and .images > 0'" || return 1
  capture_console "success-theme-manager-05-wallhaven" || return 1

  for key in m o u n t a i n; do
    press "$key" || return 1
  done
  wait_for_guest_state "typing performs a real catalog name search" 55 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallhaven\" and .query == \"mountain\" and .images > 0'" || return 1

  initial_thumb_count=$(ssh_session \
    "find \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" -maxdepth 1 -type f | wc -l") || return 1
  for _step in {1..40}; do
    press right || return 1
  done
  wait_for_guest_state "near-end navigation automatically loads another catalog batch" 55 ssh_session \
    "(( \$(find \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" -maxdepth 1 -type f | wc -l) > $initial_thumb_count ))" || return 1

  press ctrl-f || return 1
  wait_for_guest_state "the staged filter sheet opens without leaving the catalog" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallhaven\" and .filtersOpen == true'" || return 1
  ssh_session "rm -rf \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\"" || return 1
  press right || return 1
  press spc || return 1
  press down || return 1
  press right || return 1
  press down || return 1
  press right || return 1
  press down || return 1
  for _color_step in {1..5}; do
    press right || return 1
  done
  ssh_session "test ! -e \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\"" || return 1
  capture_console "success-theme-manager-06-filter-sheet" || return 1

  press ret || return 1
  wait_for_guest_state "applying staged filters starts one fresh catalog search" 55 ssh_session \
    "test -d \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" && \
     find \"\$HOME/.cache/omarchy-theme-manager/wallpaper-thumbs\" -maxdepth 1 -type f -print -quit | grep -q . && \
     omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallhaven\" and .filtersOpen == false and .images > 0'" || return 1
  capture_console "success-theme-manager-07-filtered" || return 1

  press ret || return 1
  wait_for_guest_state "the selected full wallpaper is installed into the current theme and applied" 55 ssh_session \
    "theme=\$(cat \"\$HOME/.local/state/omarchy/current/theme.name\") && \
     background=\$(readlink -f \"\$HOME/.local/state/omarchy/current/background\") && \
     [[ \$background == \"\$HOME/.config/omarchy/backgrounds/\$theme/\"* ]] && \
     file --brief --mime-type \"\$background\" | grep -q '^image/' && \
     jq -e --arg theme \"\$theme\" --arg background \"\$background\" \
       '.themes[\$theme].wallpaper == \$background' \
       \"$state_root/theme-manager-memory.json\" && \
     hyprctl -j layers | jq -e \
       '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1
  ssh_session "test -z \"\$(hyprctl configerrors)\"" || return 1
  capture_console "success-theme-manager-08-wallpaper-applied" || return 1

  wait_for_guest_state "a planted wallpaper symlink cannot redirect publication" 20 ssh_session \
    "theme=\$(cat \"\$HOME/.local/state/omarchy/current/theme.name\") && \
     theme_dir=\"\$HOME/.config/omarchy/backgrounds/\$theme\" && \
     source=\"\$HOME/.local/share/omarchy-theme-manager/wallpapers/symlink-guard.png\" && \
     victim=\"\$HOME/theme-manager-symlink-victim\" && \
     mkdir -p \"\$(dirname \"\$source\")\" && \
     cp -- \"\$(readlink -f \"\$HOME/.local/state/omarchy/current/background\")\" \"\$source\" && \
     printf 'untouched' >\"\$victim\" && \
     ln -s -- \"\$victim\" \"\$theme_dir/symlink-guard.png\" && \
     installed=\$(\"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/install-wallpaper.sh\" \
       \"\$theme\" \"\$source\") && \
     [[ \$installed == \"\$theme_dir/symlink-guard-2.png\" ]] && \
     [[ \$(cat \"\$victim\") == untouched ]] && \
     [[ -L \$theme_dir/symlink-guard.png ]] && \
     [[ -f \$installed && ! -L \$installed ]]" || return 1

  ssh_session "omarchy-plugin-disable io.github.mtolhuys.theme-manager" || return 1
  wait_for_guest_state "disabling Theme Manager restores the native picker" 20 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == false) and \
       any(.[]; .id == \"omarchy.image-picker\" and .enabled == true)'" || return 1

  ssh_session "omarchy-plugin-enable io.github.mtolhuys.theme-manager" || return 1
  wait_for_guest_state "Theme Manager can be enabled again with the same runtime" 20 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     [[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"$version\" ]]" || return 1

  ssh_session "omarchy-plugin-remove io.github.mtolhuys.theme-manager --yes" || return 1
  wait_for_guest_state "removal restores the native picker and keeps the wallpaper" 20 ssh_session \
    "test ! -e \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\" && \
     test -f \"\$(readlink -f \"\$HOME/.local/state/omarchy/current/background\")\" && \
     omarchy-plugin-list --json | jq -e \
      'all(.[]; .id != \"io.github.mtolhuys.theme-manager\") and \
       any(.[]; .id == \"omarchy.image-picker\" and .enabled == true)'" || return 1

  printf 'ok - favorites, live palette, theme catalog, folder browsing, open wallpaper browsing, and plugin lifecycle completed\n'
}
