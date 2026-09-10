#!/bin/bash

# End-to-end proof for the combined Theme Manager picker. All installation,
# activation, UI interaction, downloads, and lifecycle mutations run only in
# the disposable Omarchy plugin lab guest.

omarchy_host_test() {
  local initial_thumb_count install_source install_source_q plugin_root
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=${THEME_MANAGER_INSTALL_SOURCE:-/tmp/omarchy-theme-manager}
  printf -v install_source_q '%q' "$install_source"

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

  ssh_session "aether --version && \
    aether --help | grep -q -- '--wallhaven-thumbs' && \
    aether --help | grep -q -- '--wallhaven-download'" || return 1

  ssh_session "omarchy-plugin-add $install_source_q --enable --yes" || return 1
  wait_for_guest_state "Theme Manager 0.5.13 is installed" 25 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     jq -e '.version == \"0.5.13\" and \
       .entryPoints.overlay == \"v0200/ImagePicker.qml\" and \
       .omarchy.clonedFrom == \"omarchy.image-picker\"' \
       \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/manifest.json\"" || return 1
  if ! wait_for_guest_state "Theme Manager 0.5.13 is loaded" 25 ssh_session \
    "[[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"0.5.13\" ]]"; then
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

  press ctrl-b || return 1
  wait_for_guest_state "Ctrl+B opens the bounded theme catalog" 75 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"catalog\" and .images > 0'" || return 1
  capture_console "success-theme-manager-02-theme-catalog" || return 1

  ssh_session "find \"\$HOME/.config/omarchy/themes\" -mindepth 1 -maxdepth 1 -type d | \
    wc -l > /tmp/theme-manager-theme-count-before-review" || return 1
  press ret || return 1
  wait_for_guest_state "Return opens the catalog repository for review without installing it" 30 ssh_session \
    "hyprctl -j clients | jq -e \
       'any(.[]; ((.class // \"\") | ascii_downcase | test(\"chromium|chrome|firefox|brave\")))' && \
     [[ \$(find \"\$HOME/.config/omarchy/themes\" -mindepth 1 -maxdepth 1 -type d | wc -l) == \
        \$(cat /tmp/theme-manager-theme-count-before-review) ]]" || return 1
  press alt-f4 || return 1
  wait_for_guest_state "closing the review browser returns to the catalog" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"catalog\"'" || return 1

  press esc || return 1
  wait_for_guest_state "Escape returns from the catalog to installed themes" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\" and .images > 0'" || return 1
  press esc || return 1
  wait_for_guest_state "the theme picker closes cleanly" 20 ssh_session \
    "hyprctl -j layers | jq -e \
      '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1

  ssh_session "rm -rf \"\$HOME/.cache/aether/wallhaven-thumbs\"" || return 1
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
  wait_for_guest_state "Ctrl+B enters the Aether-backed Wallhaven browser" 55 ssh_session \
    "test -d \"\$HOME/.cache/aether/wallhaven-thumbs\" && \
     find \"\$HOME/.cache/aether/wallhaven-thumbs\" -maxdepth 1 -type f -print -quit | grep -q . && \
     omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallhaven\" and .images > 0'" || return 1
  capture_console "success-theme-manager-05-wallhaven" || return 1

  for key in m o u n t a i n; do
    press "$key" || return 1
  done
  wait_for_guest_state "typing performs a real Wallhaven name search" 55 ssh_session \
    "! pgrep -u \"\$USER\" -x aether >/dev/null && \
     omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallhaven\" and .query == \"mountain\" and .images > 0'" || return 1

  initial_thumb_count=$(ssh_session \
    "find \"\$HOME/.cache/aether/wallhaven-thumbs\" -maxdepth 1 -type f | wc -l") || return 1
  for _step in {1..40}; do
    press right || return 1
  done
  wait_for_guest_state "near-end navigation automatically loads another Aether batch" 55 ssh_session \
    "(( \$(find \"\$HOME/.cache/aether/wallhaven-thumbs\" -maxdepth 1 -type f | wc -l) > $initial_thumb_count ))" || return 1

  press ctrl-f || return 1
  wait_for_guest_state "the staged filter sheet opens without leaving Wallhaven" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallhaven\" and .filtersOpen == true'" || return 1
  ssh_session "rm -rf \"\$HOME/.cache/aether/wallhaven-thumbs\"" || return 1
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
  ssh_session "test ! -e \"\$HOME/.cache/aether/wallhaven-thumbs\"" || return 1
  capture_console "success-theme-manager-06-filter-sheet" || return 1

  press ret || return 1
  wait_for_guest_state "applying staged blue-palette filters starts one fresh Aether search" 55 ssh_session \
    "test -d \"\$HOME/.cache/aether/wallhaven-thumbs\" && \
     find \"\$HOME/.cache/aether/wallhaven-thumbs\" -maxdepth 1 -type f -print -quit | grep -q . && \
     ! pgrep -u \"\$USER\" -x aether >/dev/null && \
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

  ssh_session "omarchy-plugin-disable io.github.mtolhuys.theme-manager" || return 1
  wait_for_guest_state "disabling Theme Manager restores the native picker" 20 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == false) and \
       any(.[]; .id == \"omarchy.image-picker\" and .enabled == true)'" || return 1

  ssh_session "omarchy-plugin-enable io.github.mtolhuys.theme-manager" || return 1
  wait_for_guest_state "Theme Manager can be enabled again with the same runtime" 20 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     [[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"0.5.13\" ]]" || return 1

  ssh_session "omarchy-plugin-remove io.github.mtolhuys.theme-manager --yes" || return 1
  wait_for_guest_state "removal restores the native picker and keeps the wallpaper" 20 ssh_session \
    "test ! -e \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\" && \
     test -f \"\$(readlink -f \"\$HOME/.local/state/omarchy/current/background\")\" && \
     omarchy-plugin-list --json | jq -e \
      'all(.[]; .id != \"io.github.mtolhuys.theme-manager\") and \
       any(.[]; .id == \"omarchy.image-picker\" and .enabled == true)'" || return 1

  printf 'ok - favorites, live palette, theme catalog, Aether browsing, and plugin lifecycle completed\n'
}
