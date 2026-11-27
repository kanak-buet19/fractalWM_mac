#!/usr/bin/env bash
# Takes a screenshot inside the VM and copies it to the host.
# Usage: scripts/vm-screenshot.sh [output.png]   (default: build/vm-shot.png)
set -euo pipefail
cd "$(dirname "$0")/.."

VM="${FRACTALWM_VM:-fractalvm}"
OUT="${1:-build/vm-shot.png}"
mkdir -p "$(dirname "$OUT")"

ssh "$VM" 'screencapture -x /tmp/vm-shot.png'
scp -q "$VM:/tmp/vm-shot.png" "$OUT"
ssh "$VM" 'rm -f /tmp/vm-shot.png'
echo "$OUT"
