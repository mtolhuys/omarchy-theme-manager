#!/usr/bin/bash
# Exit 0 when omarchy-theme-set's lock is free, 1 while it is held. The lock
# file persists after unlock, so ownership is probed with flock rather than
# existence. Started by Run from ImagePicker.qml every 250 ms while a theme
# switch settles; a bash -c string before the Run port.
set -euo pipefail

lock="${XDG_RUNTIME_DIR:-/tmp}/omarchy-theme-set.lock"
exec flock -n "$lock" true
