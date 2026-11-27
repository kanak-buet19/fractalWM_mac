#!/usr/bin/env bash
# Prints fractalWM's window frames inside the VM. Needs no permissions.
set -euo pipefail
cd "$(dirname "$0")/.."
ssh "${FRACTALWM_VM:-fractalvm}" 'osascript -l JavaScript -' < scripts/vm-windows.js
# The app's own debug snapshot (layout tree summary), if it has written one.
ssh "${FRACTALWM_VM:-fractalvm}" 'cat /tmp/fractalwm-state.txt 2>/dev/null || true'
