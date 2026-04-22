#!/usr/bin/env bash
# progress.sh — called mid-iteration to update status + files-touched list.
# The tracked files list is what finish.sh records in the changelog; files
# edited without a progress.sh call won't appear in the changelog entry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: No active iteration. Run ./improvement/start.sh first." >&2
    exit 1
fi

STATUS="${1:?Usage: ./improvement/progress.sh 'status message' [file1 file2 ...]}"
shift

bun run "$SCRIPT_DIR/helpers.ts" progress "$STATE_FILE" "$SCRIPT_DIR" "$STATUS" "$@"
