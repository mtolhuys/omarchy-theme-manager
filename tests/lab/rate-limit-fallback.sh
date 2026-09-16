#!/bin/bash

# Real-session proof for the temporary GitHub rate-limit fallback. The helper
# failure and browser launcher are deterministic guest-only fixtures; the QML
# action is exercised through the user's Return key route.

omarchy_host_test() {
  local install_source install_source_q plugin_root version
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=/tmp/omarchy-theme-manager-rate-limit
  printf -v install_source_q '%q' "$install_source"
  version=$(jq -r '.version' "$plugin_root/manifest.json")

  log "Staging Theme Manager $version rate-limit regression"
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

  ssh_session "plugin=\"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\" && \
    printf '%s\n' '#!/bin/bash' \
      'printf \"%s\\n\" \"Theme install paused: GitHub download rate limit reached; retry later\" >&2' \
      'exit 75' >\"\$plugin/install-theme.py\" && \
    chmod 755 \"\$plugin/install-theme.py\" && \
    mkdir -p \"\$HOME/.local/share/omarchy/bin\" && \
    printf '%s\n' '#!/bin/bash' \
      'printf \"%s\\n\" \"\$#\" \"\$1\" > /tmp/theme-manager-opened-source' \
      >\"\$HOME/.local/share/omarchy/bin/xdg-open\" && \
    chmod 755 \"\$HOME/.local/share/omarchy/bin/xdg-open\" && \
    rm -f /tmp/theme-manager-opened-source /tmp/theme-manager-rate-limit-expected && \
    [[ \$(bash -lc 'command -v xdg-open') == \"\$HOME/.local/share/omarchy/bin/xdg-open\" ]]" || return 1
  wait_for_guest_state "the rate-limit fixture rescan settles on Theme Manager $version" 20 ssh_session \
    "[[ \$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '') == \"$version\" ]]" || return 1
  sleep 1
  ssh_session "date --iso-8601=seconds > /tmp/theme-manager-rate-limit-start" || return 1

  press meta_l-shift-ctrl-spc || return 1
  wait_for_guest_state "the theme picker opens" 25 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\"'" || return 1
  press ctrl-b || return 1
  wait_for_guest_state "the catalog selects an installable theme" 75 ssh_session \
    "state=\$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '') && \
     jq -e '.mode == \"catalog\" and .images > 0 and .catalogCanInstall == true and \
       .catalogAction == \"Install\"' <<<\"\$state\" && \
     jq -r '.selectedPath' <<<\"\$state\" > /tmp/theme-manager-rate-limit-expected" || return 1

  press ret || return 1
  wait_for_guest_state "Return opens the install confirmation" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.catalogInstallConfirmationOpen == true'" || return 1
  press ret || return 1
  wait_for_guest_state "a rate limit offers View source without installing" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.catalogAction == \"View source\" and .catalogCanOpenSource == true and \
         .catalogCanInstall == true and \
         .catalogError == \"GitHub rate limit reached — view the source or retry shortly\"'" || return 1
  capture_console "theme-manager-rate-limit-01-view-source" || return 1

  press ret || return 1
  wait_for_guest_state "View source opens one literal URL and immediately restores Install" 20 ssh_session \
    "state=\$(omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '') && \
     [[ \$(sed -n '1p' /tmp/theme-manager-opened-source) == 1 ]] && \
     [[ \$(sed -n '2p' /tmp/theme-manager-opened-source) == \$(cat /tmp/theme-manager-rate-limit-expected) ]] && \
     jq -e '.catalogAction == \"Install\" and .catalogCanOpenSource == false and \
       .catalogCanInstall == true and .catalogError == \"\"' <<<\"\$state\"" || return 1
  capture_console "theme-manager-rate-limit-02-install-restored" || return 1

  if ! ssh_session "test -z \"\$(hyprctl configerrors)\" && \
    ! journalctl --user --since \"\$(cat /tmp/theme-manager-rate-limit-start)\" --no-pager | \
      grep -Eiq 'TypeError|ReferenceError|failed to load|error loading'"; then
    ssh_session "journalctl --user --since \"\$(cat /tmp/theme-manager-rate-limit-start)\" --no-pager" \
      >"$RUN_DIR/rate-limit-shell-errors.log" 2>&1 || true
    return 1
  fi

  printf 'ok - rate-limit fallback opened the source once and restored Install\n'
}
