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
#      the picker keeps grid mode for the shell session and resets favorites-only.
#
#   Storage
#  13. Uninstall a starred theme: its id stays in theme-collections.json while
#      the card leaves Favorites; reinstalling it brings the star back.
#  14. Write "{ not json" over theme-collections.json and run
#      omarchy-shell shell rescanPlugins: theme-collections.json.bak holds the
#      broken text, runtimeState reports themeFavoriteCount 0, and the next
#      Ctrl+D rewrites the main file as valid JSON.
#  15. Remove both files, reopen the picker, browse, search and apply a theme
#      without starring anything: no theme-collections.json appears.

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
       \"\$HOME/.config/omarchy/wallpaper-command-center.json\"" || return 1

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
       \"\$HOME/.config/omarchy/wallpaper-command-center.json\"" || return 1

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
       \"\$HOME/.config/omarchy/theme-manager-memory.json\" && \
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

  printf 'ok - favorites, live palette, theme catalog, open wallpaper browsing, and plugin lifecycle completed\n'
}
