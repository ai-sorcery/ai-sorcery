#!/usr/bin/env bash
# timestamp.sh — print the current local wall-clock time with an optional
# label. Cheap checkpoint marker that makes stalls obvious in the log.

set -euo pipefail

label="${1:-}"
now="$(date '+%Y-%m-%d %H:%M:%S %Z')"

if [[ -n "$label" ]]; then
    printf '[%s] %s\n' "$now" "$label"
else
    printf '[%s]\n' "$now"
fi
