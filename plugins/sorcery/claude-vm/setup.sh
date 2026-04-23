#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Install Tart if not already installed.
if ! command -v tart &> /dev/null; then
  echo "Installing Tart via Homebrew..."
  brew install cirruslabs/cli/tart
else
  echo "Tart is already installed."
fi

# jq is used by run.sh and vm-setup.sh to parse shared-folders.json. Install
# it here so a missing jq never surfaces as an opaque "command not found"
# partway through a ./run.sh that's already started a background VM.
if ! command -v jq &> /dev/null; then
  echo "Installing jq via Homebrew..."
  brew install jq
fi

# Clone the macOS image if the VM doesn't exist yet. Either way, (re-)apply
# sizing from config.sh — this lets the user bump CPU / memory / disk by
# editing config.sh and re-running ./setup.sh, without a full teardown.
if tart list -q 2>/dev/null | grep -q "^${VM_NAME}$"; then
  echo "VM '$VM_NAME' already exists — reapplying config.sh sizing."
else
  echo "Pulling image '$IMAGE' (this may take a while on first run)..."
  tart clone "$IMAGE" "$VM_NAME"
fi

echo "Configuring VM..."
tart set "$VM_NAME" \
  --cpu "$VM_CPU" \
  --memory "$VM_MEMORY_MB" \
  --disk-size "$VM_DISK_GB" \
  --display "$VM_DISPLAY"

echo ""
echo "Setup complete. VM '$VM_NAME' is ready."
echo ""
echo "  Start the VM:     ./run.sh  (boots the VM and runs vm-setup.sh automatically)"
echo "  VM credentials:   admin / admin"
