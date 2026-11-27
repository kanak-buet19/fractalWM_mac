#!/usr/bin/env bash
# Copies build/fractalWM.app into the VM and launches it there.
# Never launches anything on the host.
# Usage: scripts/run-in-vm.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VM="${FRACTALWM_VM:-fractalvm}"
APP="build/fractalWM.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run: swift build -c release && scripts/bundle.sh" >&2
  exit 1
fi

# Quit the running copy and remove the old build in the VM.
ssh "$VM" 'pkill -x FractalWM || true; mkdir -p ~/Applications; rm -rf ~/Applications/fractalWM.app'
scp -rq "$APP" "$VM:Applications/"
ssh "$VM" 'open ~/Applications/fractalWM.app'

echo "Launched fractalWM in $VM"
