#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Refresh the cached upstream macOS image. Does not touch any existing VM.
# `tart clone` (in setup.sh) only consults the registry on first pull, so
# without an explicit `tart pull` later teardown/setup cycles silently
# reuse the stale cached image. Run this before `./teardown.sh && ./setup.sh`
# when you actually want to move to a newer macOS or Cirrus image build.

if ! command -v tart &> /dev/null; then
  echo "Error: tart is not installed. Run ./setup.sh first."
  exit 1
fi

echo "Pulling '$IMAGE'..."
echo "(no-op if the cached image already matches the registry)"
echo ""
tart pull "$IMAGE"

echo ""
echo "Image cache refreshed."
echo ""
echo "Existing VMs are unchanged. To rebuild on the refreshed image:"
echo "  ./teardown.sh && ./setup.sh"
echo "(this discards VM-internal state — Chrome profile, signed-in apps, etc.)"
