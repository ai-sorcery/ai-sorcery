#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check that VM exists.
if ! tart list -q 2>/dev/null | grep -q "^${VM_NAME}$"; then
  echo "Error: VM '$VM_NAME' not found. Run ./setup.sh first."
  exit 1
fi

# Build --dir flags from shared-folders.json (active entries only). Each
# entry may set `guest` to override the default guest path (which mirrors
# the host path). The virtiofs tag is the basename of the guest path.
DIR_FLAGS=()
SHARED_FOLDERS_FILE="$SCRIPT_DIR/shared-folders.json"
if [ -f "$SHARED_FOLDERS_FILE" ]; then
  while IFS=$'\t' read -r host_entry guest_entry; do
    host_expanded="${host_entry/#\~/$HOME}"
    name="$(basename "$guest_entry")"

    if [ ! -d "$host_expanded" ]; then
      echo "Creating missing shared folder on host: $host_expanded"
      mkdir -p "$host_expanded"
    fi

    DIR_FLAGS+=(--dir "$host_expanded:tag=$name")
  done < <(jq -r '.[] | select(.active) | "\(.path)\t\(.guest // .path)"' "$SHARED_FOLDERS_FILE")
fi

if [ ${#DIR_FLAGS[@]} -gt 0 ]; then
  echo "Sharing folders:"
  for (( i=0; i < ${#DIR_FLAGS[@]}; i+=2 )); do
    echo "  ${DIR_FLAGS[i+1]}"
  done
  echo ""
fi

echo "Starting '$VM_NAME' with VNC..."
echo ""

# Expand DIR_FLAGS via ${arr[@]+"${arr[@]}"} so an empty array doesn't
# trip set -u on macOS bash 3.2 — the default shell on stock macOS.
tart run --vnc-experimental ${DIR_FLAGS[@]+"${DIR_FLAGS[@]}"} "$VM_NAME" 2> >(grep -v "GRPCConnectionPoolError" >&2) &
TART_PID=$!

# Wait for the VM to get an IP, then open Screen Sharing.
echo "Waiting for VM to boot..."
for i in $(seq 1 60); do
  IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
  if [ -n "$IP" ]; then
    echo "VM is up at $IP"
    echo "Opening Screen Sharing... (credentials: admin / admin)"
    open "vnc://$IP"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "VM did not get an IP within 120 seconds."
    echo "Try connecting manually: open vnc://\$(tart ip $VM_NAME)"
  fi
  sleep 2
done

# Run VM setup (install apps, mount shared folders, configure preferences).
echo ""
echo "Running VM setup..."
"$SCRIPT_DIR/vm-setup.sh"

echo ""
echo "Press Ctrl+C to stop the VM."

wait $TART_PID 2>/dev/null
