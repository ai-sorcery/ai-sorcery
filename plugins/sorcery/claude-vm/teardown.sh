#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Stop VM if running.
if tart ip "$VM_NAME" &> /dev/null 2>&1; then
  echo "Stopping VM..."
  tart stop "$VM_NAME" 2>/dev/null || true
  sleep 2
fi

# Delete VM.
if tart list -q 2>/dev/null | grep -q "^${VM_NAME}$"; then
  echo "Deleting VM '$VM_NAME'..."
  tart delete "$VM_NAME"
  echo "VM deleted."
else
  echo "VM '$VM_NAME' not found — nothing to delete."
fi
