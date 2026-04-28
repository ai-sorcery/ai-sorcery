#!/usr/bin/env bash
# Demo variant of ./claude.sh: sets SKIP_RC=1 so the canonical launcher
# omits --rc and the remote-control URL stays out of screen recordings.
# Everything else (IS_DEMO banner masking, --effort max, --model
# claude-opus-4-7, in-tree plugin dirs) matches the regular launcher.
#
# Runnable from any cwd: ./demo-claude.sh or /abs/path/to/ai-sorcery/demo-claude.sh.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"

exec env SKIP_RC=1 "$repo_root/claude.sh" "$@"
