#!/bin/bash

# Networked marketing capture for Theme Manager README / marketplace banner.
# Runs only in the disposable Omarchy plugin lab guest — never on the daily host.
# Applies Matte Black, walks Themes · Catalog · Wallpapers · Icons · Wallhaven ·
# Actions, and keeps full-bleed console evidence for banner composition.

omarchy_host_test() {
  local install_source install_source_q plugin_root start_epoch viewport_width viewport_height
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=${THEME_MANAGER_INSTALL_SOURCE:-/tmp/omarchy-theme-manager}
  printf -v install_source_q '%q' "$install_source"
  start_epoch="$(date +%s)"

  qmp_pointer_park() {
    local width="$1" height="$2" x="${3:-4}" y="${4:-4}" qx qy response
    qx=$((x * 32767 / (width - 1)))
    qy=$((y * 32767 / (height - 1)))
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$qx}},
      {\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$qy}}
    ]}")
    ! grep -q '"error"' <<<"$response"
  }

  log "Staging Omarchy Theme Manager for marketing capture"
  tar \
    --exclude=.git \
    --exclude=.idea \
    --exclude=node_modules \
    --exclude=.tmp \
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

  log "Applying Matte Black marketing theme"
  ssh_session "omarchy-theme-set matte-black >/dev/null" || return 1
  wait_for_guest_state "Matte Black is the active theme" 25 ssh_session \
    "[[ \$(readlink -f \"\$HOME/.config/omarchy/current/theme\" 2>/dev/null || \
         readlink -f \"\$HOME/.local/state/omarchy/current/theme\") == *matte-black* ]] || \
     hyprctl -j getoption general:col.active_border >/dev/null" || return 1

  ssh_session "aether --version && \
    aether --help | grep -q -- '--wallhaven-thumbs' && \
    aether --help | grep -q -- '--wallhaven-download'" || return 1

  ssh_session "omarchy-plugin-add $install_source_q --enable --yes" \
    >"$RUN_DIR/theme-manager-marketing-install.log" || return 1
  wait_for_guest_state "Theme Manager 0.5.12 is installed and loaded" 25 ssh_session \
    "omarchy-plugin-list --json | jq -e \
      'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     jq -e '.version == \"0.5.12\" and \
       .entryPoints.overlay == \"v0200/ImagePicker.qml\" and \
       .omarchy.clonedFrom == \"omarchy.image-picker\"' \
       \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/manifest.json\" && \
     [[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"0.5.12\" ]]" || return 1

  viewport_width="$(ssh_session "hyprctl -j monitors | jq -r '.[0].width'")" || return 1
  viewport_height="$(ssh_session "hyprctl -j monitors | jq -r '.[0].height'")" || return 1
  printf '%s\n' "{\"viewport\":[${viewport_width},${viewport_height}],\"theme\":\"matte-black\"}" \
    >"$RUN_DIR/theme-manager-marketing-geometry.json"

  # --- Themes carousel ---
  press meta_l-shift-ctrl-spc || return 1
  wait_for_guest_state "theme shortcut opens Theme Manager themes mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\" and .images > 0' && \
     hyprctl -j layers | jq -e \
       '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length >= 1'" || return 1
  sleep 0.8
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.4
  capture_console "success-theme-manager-marketing-01-themes" || return 1

  for _step in 1 2 3 4; do
    press right || return 1
    sleep 0.35
  done
  sleep 0.5
  capture_console "success-theme-manager-marketing-02-themes-scroll" || return 1

  # --- Theme catalog ---
  press ctrl-b || return 1
  wait_for_guest_state "Ctrl+B opens the theme catalog" 75 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"catalog\" and .images > 0'" || return 1
  sleep 0.6
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.3
  capture_console "success-theme-manager-marketing-03-catalog" || return 1

  press ctrl-f || return 1
  wait_for_guest_state "catalog filter sheet opens" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .filtersOpen == true'" || return 1
  sleep 0.5
  capture_console "success-theme-manager-marketing-04-catalog-filters" || return 1
  press esc || return 1
  wait_for_guest_state "catalog filter sheet closes" 15 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.mode == \"catalog\" and .filtersOpen == false'" || return 1
  press esc || return 1
  wait_for_guest_state "Escape returns to installed themes" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\"'" || return 1

  # --- Wallpapers ---
  press ctrl-w || return 1
  wait_for_guest_state "Ctrl+W opens wallpaper mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\" and .images > 0'" || return 1
  sleep 0.7
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.3
  capture_console "success-theme-manager-marketing-05-wallpapers" || return 1

  for _step in 1 2 3; do
    press right || return 1
    sleep 0.4
  done
  sleep 0.4
  capture_console "success-theme-manager-marketing-06-wallpapers-scroll" || return 1

  # --- Actions menu ---
  press m || return 1
  sleep 0.7
  capture_console "success-theme-manager-marketing-07-actions" || return 1
  press esc || return 1
  sleep 0.35

  # --- Icons mode ---
  press ctrl-i || return 1
  wait_for_guest_state "Ctrl+I opens Icons mode" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"icons\"'" || return 1
  sleep 0.8
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.3
  capture_console "success-theme-manager-marketing-08-icons" || return 1
  press esc || return 1
  wait_for_guest_state "Escape leaves Icons back to wallpapers" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallpapers\"'" || return 1

  # --- Wallhaven ---
  ssh_session "rm -rf \"\$HOME/.cache/aether/wallhaven-thumbs\"" || return 1
  press ctrl-b || return 1
  wait_for_guest_state "Ctrl+B enters Wallhaven via Aether" 55 ssh_session \
    "test -d \"\$HOME/.cache/aether/wallhaven-thumbs\" && \
     find \"\$HOME/.cache/aether/wallhaven-thumbs\" -maxdepth 1 -type f -print -quit | grep -q . && \
     omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"wallhaven\" and .images > 0'" || return 1
  sleep 0.6
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.3
  capture_console "success-theme-manager-marketing-09-wallhaven" || return 1

  for _step in 1 2 3; do
    press right || return 1
    sleep 0.35
  done
  sleep 0.4
  capture_console "success-theme-manager-marketing-10-wallhaven-scroll" || return 1

  # --- Sticky memory finale: return to themes ---
  press ctrl-t || return 1
  wait_for_guest_state "Ctrl+T returns to themes" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\"'" || return 1
  sleep 0.6
  capture_console "success-theme-manager-marketing-11-themes-finale" || return 1

  press esc || return 1
  wait_for_guest_state "picker closes cleanly" 20 ssh_session \
    "hyprctl -j layers | jq -e \
      '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1

  # Clean desktop still under Matte Black (no picker chrome)
  sleep 0.5
  qmp_pointer_park "$viewport_width" "$viewport_height" || return 1
  sleep 0.3
  capture_console "success-theme-manager-marketing-12-matte-desktop" || return 1

  ssh_session "omarchy-plugin-remove io.github.mtolhuys.theme-manager --yes" >/dev/null || return 1
  wait_for_guest_state "marketing candidate removes cleanly" 20 ssh_session \
    "test ! -e \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\" && \
     omarchy-plugin-list --json | jq -e \
      'all(.[]; .id != \"io.github.mtolhuys.theme-manager\") and \
       any(.[]; .id == \"omarchy.image-picker\" and .enabled == true)'" || return 1

  ssh_session "journalctl --user --since '@$start_epoch' --no-pager" \
    >"$RUN_DIR/theme-manager-marketing-journal.log" || true

  printf 'ok - Matte Black marketing frames captured for Themes, Catalog, Wallpapers, Icons, Wallhaven\n'
}
