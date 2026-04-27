#!/usr/bin/env bash
# Delegate to the canonical fix-cache script with this repo's root as the
# target mount point. Extra args (e.g., --tag) pass through.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")" && pwd)"
exec "$repo_root/plugins/sorcery/claude-vm/fix-cache.sh" "$repo_root" "$@"
