#!/usr/bin/env bash
# Run on the host. Walks you through giving SSH sessions in the VM the Screen Recording and
# Accessibility permissions, so scripts can take screenshots and send keys there.
# macOS doesn't allow granting these from a script, so you click "+" once per pane.
set -euo pipefail

VM="${FRACTALWM_VM:-fractalvm}"
TARGET="/usr/libexec/sshd-keygen-wrapper"

grant() {
  local name="$1" pane="$2"
  echo
  echo "== $name"
  ssh "$VM" "printf %s '$TARGET' | pbcopy; open 'x-apple.systempreferences:com.apple.preference.security?$pane'"
  echo "In the VM, the $name settings page is now open."
  echo "  1. Click + at the bottom of the list."
  echo "  2. Press Cmd+Shift+G, paste with Cmd+V (or type $TARGET), press Return, click Open."
  echo "  3. Make sure the toggle next to it is on."
  read -rp "Press Return here when done... " _
}

grant "Screen & System Audio Recording" "Privacy_ScreenCapture"
grant "Accessibility" "Privacy_Accessibility"

echo
echo "== Checking (new SSH sessions pick up the permissions)"
if ssh "$VM" 'screencapture -x /tmp/.perm-test.png && rm -f /tmp/.perm-test.png'; then
  echo "OK: Screen Recording works"
else
  echo "FAIL: Screen Recording not granted yet"
fi
if ssh "$VM" 'osascript -e "tell application \"System Events\" to get name of first process" >/dev/null'; then
  echo "OK: Accessibility works"
else
  echo "FAIL: Accessibility not granted yet (the VM may show an Automation prompt for System Events; allow it)"
fi
