#!/usr/bin/env bash
# finish.sh — called at the end of each improvement-loop iteration.
# Appends the iteration to SUCCINCT-CHANGELOG.md + VERBOSE-CHANGELOG.md,
# clears IN-PROGRESS.md, and removes the state file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: No active iteration. Run ./improvement/start.sh first." >&2
    exit 1
fi

SUMMARY="${1:?Usage: ./improvement/finish.sh 'summary' ['detailed description']}"
DETAILS="${2:-}"
END_TIME=$(date -u '+%Y-%m-%d %H:%M UTC')

bun run "$SCRIPT_DIR/helpers.ts" finish "$STATE_FILE" "$SCRIPT_DIR" "$SUMMARY" "$DETAILS" "$END_TIME"
