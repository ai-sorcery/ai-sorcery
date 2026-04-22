#!/usr/bin/env bash
# task-loop-sideload-hook.sh — PostToolUse hook that injects sideloaded
# prompts from data/task-loop-inbox/ into a running task-loop.sh session.
#
# WHY THIS EXISTS
#
# `claude -p --rc ...` (headless print mode, used by task-loop.sh) does NOT
# register a Remote Control bridge session. So remote tools (the iPhone app,
# a curl call, a sibling script) can't see the task-loop session to send
# messages to it directly. This hook is the paired end of prompt-task-loop.sh:
# the user writes a file to the inbox, this hook reads it between tool calls,
# injects it as additionalContext, and archives the file.
#
# Tracking issue (delete this hook + prompt-task-loop.sh once it lands):
#   https://github.com/anthropics/claude-code/issues/30447
#
# GUARDS (see each comment):
#   1. Only fires under task-loop.sh (CLAUDE_RUN_BY check).
#   2. Only fires on the main agent, not subagents (parent_session_id check).
#   3. -maxdepth 1 on find so archive/ is never re-read.
#   4. Atomic `mv`-to-archive claim prevents concurrent double-inject.
#   5. Errors exit 0 so a hook failure doesn't break the agent.

set -u  # not -e — each step is guarded with `|| true` where failure is OK.

# Never block the agent: any hook crash exits cleanly so stderr shows up in
# the task-loop log but the tool call proceeds.
trap 'echo "task-loop-sideload hook: error at line $LINENO" >&2; exit 0' ERR

# --- Guard 1: only fire under task-loop.sh ---
if [[ "${CLAUDE_RUN_BY:-}" != "task-loop.sh" ]]; then
  exit 0
fi

# Read the hook payload from stdin (JSON). Used to detect subagents.
INPUT="$(cat)"

# --- Guard 2: only fire on the main agent (not subagents).
#
# Subagents inherit the parent's env (including CLAUDE_RUN_BY), so the env
# check alone is insufficient. Claude Code's hook payload includes a
# `parent_session_id` field on subagent firings — its presence is the
# cleanest available signal that we're inside a subagent's tool call.
PARENT_SESSION="$(echo "$INPUT" | jq -r '.parent_session_id // empty' 2>/dev/null || echo "")"
if [[ -n "$PARENT_SESSION" ]]; then
  exit 0
fi

# Inbox path. An override is supported for tests — parallel suites need
# per-test isolation so they don't race on the real inbox.
if [[ -n "${TASK_LOOP_INBOX_DIR:-}" ]]; then
  INBOX_DIR="$TASK_LOOP_INBOX_DIR"
else
  # Hook lives at <plugin>/loop/; the inbox lives under the target repo at
  # data/task-loop-inbox. Resolve the repo via git toplevel, falling back to
  # the hook's CWD if git fails (shouldn't normally).
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  INBOX_DIR="$REPO_ROOT/data/task-loop-inbox"
fi
ARCHIVE_DIR="$INBOX_DIR/archive"
mkdir -p "$INBOX_DIR" "$ARCHIVE_DIR" 2>/dev/null || true

# --- Guard 3: -maxdepth 1 so archived files don't get re-read. Sort oldest
#     first so a burst of queued prompts inject in order.
shopt -s nullglob
INBOX_FILES=()
while IFS= read -r f; do
  INBOX_FILES+=("$f")
done < <(
  find "$INBOX_DIR" -maxdepth 1 -type f -print 2>/dev/null |
    xargs -I {} stat -f '%m %N' {} 2>/dev/null |
    sort -n |
    awk '{$1=""; sub(/^ /,""); print}'
)
shopt -u nullglob

if [[ ${#INBOX_FILES[@]} -eq 0 ]]; then
  exit 0
fi

CHUNKS=()
for FILEPATH in "${INBOX_FILES[@]}"; do
  [[ -f "$FILEPATH" ]] || continue
  BASENAME="$(basename "$FILEPATH")"
  ARCHIVE_PATH="$ARCHIVE_DIR/$BASENAME"

  # --- Guard 4: atomic claim via `mv` — if two hook firings race, only the
  #     one that successfully moves the file injects it. The losing firing's
  #     mv returns non-zero and we skip that file.
  if ! mv "$FILEPATH" "$ARCHIVE_PATH" 2>/dev/null; then
    continue
  fi

  CONTENT="$(head -c 200000 "$ARCHIVE_PATH" 2>/dev/null || echo "")"
  [[ -z "$CONTENT" ]] && continue

  TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  CHUNKS+=("--- SIDELOADED USER MESSAGE (from prompt-task-loop.sh at $TIMESTAMP, file: $BASENAME) ---
$CONTENT
--- END SIDELOADED MESSAGE ---")
done

if [[ ${#CHUNKS[@]} -eq 0 ]]; then
  exit 0
fi

# Join chunks with a blank line, then serialize into the hook response JSON.
# additionalContext is the documented injection shape for PostToolUse.
JOINED="$(printf '%s\n\n' "${CHUNKS[@]}")"
jq -n --arg ctx "$JOINED" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
