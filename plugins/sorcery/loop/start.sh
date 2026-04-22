#!/usr/bin/env bash
# start.sh — called at the beginning of each improvement-loop iteration.
# Either reports recovery (previous iteration didn't finish) or assigns the
# current persona via the modulo counter.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.state.json"
COUNTER_FILE="$SCRIPT_DIR/counter.txt"
PERSONAS_FILE="$SCRIPT_DIR/personas.json"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')

# Recovery path — if the state file survived, the previous iteration didn't
# reach finish.sh. Let the helper decide whether to wait or report recovery.
if [[ -f "$STATE_FILE" ]]; then
    bun run "$SCRIPT_DIR/helpers.ts" start-recovery "$STATE_FILE" "$TIMESTAMP"
    exit 0
fi

COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

bun run "$SCRIPT_DIR/helpers.ts" start-assign "$PERSONAS_FILE" "$COUNTER" "$TIMESTAMP" "$STATE_FILE" "$COUNTER_FILE" "$SCRIPT_DIR"
