#!/usr/bin/env bash
# time-check.sh — print elapsed time for the current iteration, plus a
# comparison to past session durations pulled from VERBOSE-CHANGELOG.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: No active iteration. Run ./improvement/start.sh first." >&2
    exit 1
fi

bun run "$SCRIPT_DIR/helpers.ts" time-check "$STATE_FILE" "$SCRIPT_DIR"
