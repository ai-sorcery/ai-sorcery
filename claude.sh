#!/usr/bin/env bash
# Delegate to the sorcery plugin's canonical launcher so flag/env edits stay
# in one place. Unique to this repo: enable the in-tree copies of the
# sorcery and sorcery-dev plugins via --plugin-dir so contributors always
# run their latest changes to the plugins.
#
# Runnable from any cwd: ./claude.sh or /abs/path/to/ai-sorcery/claude.sh.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"

exec "$repo_root/plugins/sorcery/claude.sh" \
  --plugin-dir "$repo_root/plugins/sorcery" \
  --plugin-dir "$repo_root/plugins/sorcery-dev" \
  "$@"
