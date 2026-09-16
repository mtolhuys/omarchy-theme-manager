#!/bin/bash

# Real-session regression for bounded catalog rendering/search and wallpaper
# navigation. Installation and all UI interaction stay inside the disposable VM.

omarchy_host_test() {
  local install_source install_source_q plugin_root version
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=/tmp/omarchy-theme-manager-performance
  printf -v install_source_q '%q' "$install_source"
  version=$(jq -r '.version' "$plugin_root/manifest.json")

  log "Staging Theme Manager $version performance regression"
  tar \
    --exclude=.git \
    --exclude=.idea \
    --exclude=node_modules \
    -C "$plugin_root" -cf - . | ssh_guest \
    "rm -rf $install_source_q && mkdir -p $install_source_q && tar -C $install_source_q -xf -"
  ssh_guest "git -C $install_source_q init -q && \
    git -C $install_source_q add . && \
    git -C $install_source_q -c user.name=PluginLab -c user.email=lab@invalid \
      commit -qm candidate"

  ssh_session "rm -rf \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\"; \
    rm -f \"\$HOME/.config/omarchy/theme-catalog-filters.json\"; \
    omarchy-plugin-add $install_source_q --enable --yes" || return 1
  wait_for_guest_state "Theme Manager $version is loaded" 35 ssh_session \
    "[[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"$version\" ]]" || return 1

  ssh_session "date --iso-8601=seconds > /tmp/theme-manager-performance-start" || return 1
  press meta_l-shift-ctrl-spc || return 1
  wait_for_guest_state "the theme picker opens with a bounded delegate pool" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\" and .images > 0 and \
         .carouselDelegates == 17 and .visibleCarouselDelegates <= 15'" || return 1

  press ctrl-b || return 1
  wait_for_guest_state "the remote theme catalog stays bounded" 75 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .images > 0 and .matchingImages == .images and \
         .carouselDelegates == 17 and .visibleCarouselDelegates <= 15'" || return 1

  for key in a m b e r; do
    press "$key" || return 1
  done
  wait_for_guest_state "catalog name filtering remains responsive" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .query == \"amber\" and .images > 0 and \
         .matchingImages == .images and .carouselDelegates == 17 and \
         .visibleCarouselDelegates <= 15'" || return 1
  capture_console "theme-manager-performance-01-filtered-catalog" || return 1

  press esc || return 1
  wait_for_guest_state "clearing catalog search restores results without expanding the pool" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .query == \"\" and .images > 0 and \
         .carouselDelegates == 17 and .visibleCarouselDelegates <= 15'" || return 1
  for _step in {1..30}; do
    press right || return 1
  done
  wait_for_guest_state "catalog navigation remains live after repeated movement" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .selectedIndex >= 0 and \
         .carouselDelegates == 17 and .visibleCarouselDelegates <= 15'" || return 1

  press esc || return 1
  press esc || return 1
  wait_for_guest_state "the catalog closes" 20 ssh_session \
    "hyprctl -j layers | jq -e \
       '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1

  press meta_l-ctrl-spc || return 1
  wait_for_guest_state "the wallpaper picker opens with multiple wallpapers" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"wallpapers\" and .images > 1 and .carouselDelegates == 17 and \
         .visibleCarouselDelegates <= 15'" || return 1
  ssh_session "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
    jq -r '.carouselCursor' > /tmp/theme-manager-wallpaper-cursor-before" || return 1

  for _step in {1..40}; do
    press right || return 1
  done
  if ! wait_for_guest_state "wallpaper navigation settles on the selected palette without process churn" 25 ssh_session \
    "state=\$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '') && \
     before=\$(cat /tmp/theme-manager-wallpaper-cursor-before) && \
     after=\$(jq -r '.carouselCursor' <<<\"\$state\") && \
     jq -e '.mode == \"wallpapers\" and .paletteReady == true and \
       .paletteSampledPath == .paletteSourcePath and .carouselDelegates == 17 and \
       .visibleCarouselDelegates <= 15' <<<\"\$state\" && \
     [[ \$after =~ ^-?[0-9]+\$ && \$after -ne \$before ]] && \
     (( \$(pgrep -u \"\$USER\" -x magick | wc -l) <= 1 ))"; then
    ssh_session "printf '%s\\n' '--- runtime state ---'; \
      omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' || true; \
      printf '%s\\n' '--- palette processes ---'; \
      pgrep -a -u \"\$USER\" -x magick || true; \
      printf '%s\\n' '--- shell journal ---'; \
      journalctl --user --since \"\$(cat /tmp/theme-manager-performance-start)\" --no-pager" \
      >"$RUN_DIR/wallpaper-navigation-failure.txt" 2>&1 || true
    return 1
  fi
  capture_console "theme-manager-performance-02-wallpaper-navigation" || return 1

  ssh_session "since=\$(cat /tmp/theme-manager-performance-start); \
    ! journalctl --user --since \"\$since\" --no-pager | \
      grep -Eiq 'RangeError|Maximum call stack|bad_alloc|out of memory|failed to create texture'" || return 1

  printf 'ok - catalog rendering stayed bounded and wallpaper navigation settled cleanly\n'
}
