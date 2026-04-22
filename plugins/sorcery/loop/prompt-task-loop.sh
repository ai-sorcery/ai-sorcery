#!/usr/bin/env bash
# prompt-task-loop.sh — sideload a prompt into a running `task-loop.sh` session.
#
# WHY THIS EXISTS
#
# task-loop.sh invokes Claude with `claude -p ... --rc ...` (headless / print
# mode) so stream-json can be piped through tee|jq|bun for custom rendering.
# In headless mode, Claude Code does NOT register a Remote Control bridge
# session even when --rc is passed, so the session is invisible to any tool
# expecting to reach it that way. Until Claude Code supports a headless RC
# daemon natively, this script + its paired PostToolUse hook provide a side
# channel: drop a file in data/task-loop-inbox/ and the hook injects it
# between tool calls.
#
# Tracking issue (remove this script + hook once it's fixed upstream):
#   https://github.com/anthropics/claude-code/issues/30447
#
# USAGE
#
#   ./prompt-task-loop.sh "quick one-line prompt"
#     Submits the single arg as the prompt text.
#
#   echo "multi-line prompt" | ./prompt-task-loop.sh
#     Reads stdin until EOF and submits it.
#
#   ./prompt-task-loop.sh
#     Interactive mode — reads stdin until Ctrl-D.

set -euo pipefail

# Prefer the git repo root so `prompt-task-loop.sh` works when invoked from
# any subdirectory of the repo (or via a symlink). Fall back to the script's
# own location (install-task-loop.sh drops it at the repo root, so that fallback
# matches the hook's default inbox path).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$(dirname "$0")" && pwd)"
INBOX_DIR="$REPO_ROOT/data/task-loop-inbox"
mkdir -p "$INBOX_DIR" "$INBOX_DIR/archive"

if [[ $# -gt 0 ]]; then
  PROMPT_BODY="$*"
elif [[ ! -t 0 ]]; then
  PROMPT_BODY="$(cat)"
else
  echo "Enter your prompt for the running task-loop. End with Ctrl-D." >&2
  PROMPT_BODY="$(cat)"
fi

if [[ -z "${PROMPT_BODY//[[:space:]]/}" ]]; then
  echo "prompt-task-loop: refusing to write an empty prompt." >&2
  exit 1
fi

TIMESTAMP="$(date -u +"%Y%m%d-%H%M%S")"
# Short random suffix guards against double-invocation within the same second
# collapsing to the same filename. `tr` receives SIGPIPE when `head` exits;
# the subshell with `set +o pipefail` absorbs that without tripping `set -e`.
SUFFIX="$(
  set +o pipefail
  LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6
)"
FILENAME="${TIMESTAMP}-${SUFFIX}.md"
FILEPATH="$INBOX_DIR/$FILENAME"

printf '%s\n' "$PROMPT_BODY" > "$FILEPATH"

echo "prompt-task-loop: queued $FILEPATH" >&2
echo "The running task-loop will inject it on the next PostToolUse hook firing." >&2
