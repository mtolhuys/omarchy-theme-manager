#!/bin/bash

# Diagnostic proof for image-selector request cleanup across a plugin reload.
# All installation, activation, input, and process inspection run in the
# disposable Omarchy Plugin Lab guest.

omarchy_host_test() {
  local install_source install_source_q launcher_pid plugin_root reload_count source_ref version
  plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  install_source=/tmp/omarchy-theme-manager-request-leak
  printf -v install_source_q '%q' "$install_source"
  source_ref=${THEME_MANAGER_SOURCE_REF:-}
  if [[ -n $source_ref ]]; then
    version=$(git -C "$plugin_root" show "$source_ref:manifest.json" | jq -r '.version')
  else
    version=$(jq -r '.version' "$plugin_root/manifest.json")
  fi

  log "Staging Theme Manager $version request-lifecycle diagnostic"
  if [[ -n $source_ref ]]; then
    git -C "$plugin_root" archive "$source_ref" | ssh_guest \
      "rm -rf $install_source_q && mkdir -p $install_source_q && tar -C $install_source_q -xf -"
  else
    tar \
      --exclude=.git \
      --exclude=.idea \
      --exclude=node_modules \
      -C "$plugin_root" -cf - . | ssh_guest \
      "rm -rf $install_source_q && mkdir -p $install_source_q && tar -C $install_source_q -xf -"
  fi
  ssh_guest "git -C $install_source_q init -q && \
    git -C $install_source_q add . && \
    git -C $install_source_q -c user.name=PluginLab -c user.email=lab@invalid \
      commit -qm candidate"

  ssh_session "rm -rf \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager\"; \
    omarchy-plugin-add $install_source_q --enable --yes" || return 1
  wait_for_guest_state "Theme Manager candidate is installed and enabled" 30 ssh_session \
    "omarchy-plugin-list --json | jq -e \
       'any(.[]; .id == \"io.github.mtolhuys.theme-manager\" and .enabled == true)' && \
     jq -e '.version == \"$version\"' \
       \"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/manifest.json\"" || return 1
  ssh_session "omarchy-restart-shell" || return 1
  if ! wait_for_guest_state "Theme Manager QML runtime is loaded" 45 ssh_session \
    "journalctl --user -t omarchy-shell --since '-2 minutes' --no-pager | \
       grep -q 'Theme Manager runtime $version'"; then
    ssh_session "journalctl --user -t omarchy-shell --since '-3 minutes' --no-pager" \
      >"$RUN_DIR/theme-manager-shell-journal.txt" || true
    return 1
  fi

  press meta_l-shift-ctrl-spc || return 1
  if ! wait_for_guest_state "the real theme shortcut opens the picker" 20 ssh_session \
    "omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' | \
       jq -e '.opened == true and .mode == \"themes\" and .images > 0'"; then
    ssh_session "journalctl --user -t omarchy-shell --since '-3 minutes' --no-pager; \
      printf '\\n--- plugin list ---\\n'; omarchy-plugin-list --json; \
      printf '\\n--- runtime identity ---\\n'; \
      omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeIdentity '' || true; \
      printf '\\n--- runtime state ---\\n'; \
      omarchy-shell shell call io.github.mtolhuys.theme-manager runtimeState '' || true; \
      printf '\\n--- matching binds ---\\n'; \
      hyprctl binds -j | jq '[.[] | select((.key // \"\") == \"SPACE\")]'" \
      >"$RUN_DIR/theme-manager-open-debug.txt" || true
    return 1
  fi

  launcher_pid=$(ssh_session \
    "pgrep -u \"\$USER\" -f '^/bin/bash .*/omarchy-menu-images .*--print-name' | tail -n 1") || return 1
  [[ $launcher_pid =~ ^[0-9]+$ ]] || return 1

  reload_count=$(ssh_session "journalctl --user -t omarchy-shell --no-pager | \
    grep -c 'Local plugin changed, reloading: io.github.mtolhuys.theme-manager' || true") || return 1
  [[ $reload_count =~ ^[0-9]+$ ]] || return 1
  ssh_session "printf '\\n' >>\"\$HOME/.config/omarchy/plugins/io.github.mtolhuys.theme-manager/v0200/ImagePickerModel.js\""
  wait_for_guest_state "the local plugin edit triggers a full plugin reload" 25 ssh_session \
    "(( \$(journalctl --user -t omarchy-shell --no-pager | \
       grep -c 'Local plugin changed, reloading: io.github.mtolhuys.theme-manager' || true) > $reload_count ))" || return 1

  if ! wait_for_guest_state "the original image-selector wrapper exits" 10 ssh_session \
    "! kill -0 '$launcher_pid' 2>/dev/null"; then
    ssh_session "ps -p '$launcher_pid' -o pid,ppid,lstart,etimes,time,%cpu,stat,comm,args; \
      pgrep -a -u \"\$USER\" -f '/omarchy-menu-images' || true" \
      >"$RUN_DIR/request-lifecycle-processes.txt" || true
    capture_console "request-lifecycle-after-reload" || true
    ssh_session "kill '$launcher_pid' 2>/dev/null || true"
    printf 'not ok - image-selector wrapper %s survived plugin reload\n' "$launcher_pid"
    return 1
  fi

  ssh_session "pgrep -a -u \"\$USER\" -f '/omarchy-menu-images' || true" \
    >"$RUN_DIR/request-lifecycle-processes.txt" || true
  capture_console "request-lifecycle-after-reload" || true
  printf 'ok - image-selector wrapper %s exited across plugin reload\n' "$launcher_pid"
}
