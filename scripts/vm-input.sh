#!/usr/bin/env bash
# Sends input to the VM (needs Accessibility, see scripts/vm-grant-permissions.sh).
# Usage:
#   scripts/vm-input.sh key f control,option,command   # press ⌃⌥⌘F
#   scripts/vm-input.sh menu "Retile"                   # click an item in fractalWM's menu-bar menu
set -euo pipefail

VM="${FRACTALWM_VM:-fractalvm}"
cmd="${1:?usage: $0 key <char> [mods] | menu <item title>}"

case "$cmd" in
  key)
    char="${2:?key needs a character}"
    mods="${3:-}"
    using=""
    if [ -n "$mods" ]; then
      using=" using {$(echo "$mods" | sed -E 's/([a-z]+)/\1 down/g; s/,/, /g')}"
    fi
    ssh "$VM" "osascript -e 'tell application \"System Events\" to keystroke \"$char\"$using'"
    ;;
  menu)
    title="${2:?menu needs an item title}"
    ssh "$VM" "osascript" <<EOF
tell application "System Events"
  tell (first process whose bundle identifier is "local.fractalwm")
    click menu bar item 1 of last menu bar
    delay 0.3
    click menu item "$title" of menu 1 of menu bar item 1 of last menu bar
  end tell
end tell
EOF
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
