#!/usr/bin/env bash
# Delegate to the plugin's canonical author-claiming script so logic edits
# stay in one place. Run from the repo root.

set -euo pipefail

./plugins/sorcery/me.sh "$@"
