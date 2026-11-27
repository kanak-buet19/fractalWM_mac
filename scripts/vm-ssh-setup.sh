#!/usr/bin/env bash
# One-time setup: passwordless SSH from this Mac into the UTM macOS VM.
# Usage: scripts/vm-ssh-setup.sh <vm-username> [vm-ip]
set -euo pipefail

USER_NAME="${1:-}"
if [ -z "$USER_NAME" ]; then
  read -rp "VM username (the account you created inside the VM): " USER_NAME
fi
VM_IP="${2:-192.168.64.5}"
KEY="$HOME/.ssh/id_ed25519.pub"
ALIAS="fractalvm"

# 1. Copy the public key into the VM (asks for the VM password once).
ssh-copy-id -i "$KEY" "$USER_NAME@$VM_IP"

# 2. Add a short alias to ~/.ssh/config so `ssh fractalvm` works.
if ! grep -q "^Host $ALIAS\$" "$HOME/.ssh/config" 2>/dev/null; then
  cat >> "$HOME/.ssh/config" <<EOF

Host $ALIAS
  HostName $VM_IP
  User $USER_NAME
  IdentityFile ${KEY%.pub}
EOF
  echo "Added '$ALIAS' to ~/.ssh/config"
fi

# 3. Verify: should print the VM's hostname without asking for a password.
ssh -o BatchMode=yes "$ALIAS" hostname && echo "OK: passwordless SSH works. Use: ssh $ALIAS"
