#!/usr/bin/env bash
# Delegate to the plugin's canonical launcher so flag/env edits stay in one
# place. Run from the repo root.

set -euo pipefail

./plugins/sorcery/claude.sh "$@"
