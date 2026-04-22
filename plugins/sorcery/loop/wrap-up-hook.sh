#!/usr/bin/env bash
# wrap-up-hook.sh — PostToolUse hook that injects a soft-deadline reminder.
#
# Once a loop iteration has been running longer than the wrap-up threshold,
# inject a system-reminder asking the agent to finalize gracefully — before
# the hard-kill SIGTERM watchdog fires.
#
# Fires for both improvement/loop.sh and task-loop.sh iterations; both
# harnesses write improvement/.iteration-start on iteration start and clean
# it up on iteration end, and both observe the same SIGTERM ceiling. The
# hook reads that marker to compute elapsed time.
#
# Silent no-op outside of iterations (the marker is only present while a
# loop iteration is in flight). Fires at most once per iteration — the
# .wrap-up-fired sentinel sits alongside the marker after the first emission
# and subsequent hook calls in the same iteration stay quiet. Rationale: the
# agent should see the signal clearly once, not every tool call for 30
# minutes.

set -euo pipefail

# Consume and discard stdin (hook event JSON).
cat >/dev/null

# Resolve marker + sentinel location. Defaults to <repo-root>/improvement/;
# overridable via LOOP_WRAPUP_MARKER for tests.
if [[ -n "${LOOP_WRAPUP_MARKER:-}" ]]; then
  marker="$LOOP_WRAPUP_MARKER"
  marker_dir="$(dirname "$marker")"
else
  marker_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  marker="$marker_dir/.iteration-start"
fi
sentinel="$marker_dir/.wrap-up-fired"

[[ -f "$marker" ]] || exit 0

# Rate-limit: already fired this iteration → stay quiet.
[[ -f "$sentinel" ]] && exit 0

start_ts=$(cat "$marker" 2>/dev/null || true)
[[ -n "${start_ts:-}" && "$start_ts" =~ ^[0-9]+$ ]] || exit 0

now=$(date +%s)
elapsed=$(( now - start_ts ))
threshold=${LOOP_WRAPUP_THRESHOLD:-3600}   # 60 minutes
hard_kill=${LOOP_MAX_RUN:-5400}            # 90 minutes

# Below threshold → nothing to say yet.
(( elapsed >= threshold )) || exit 0

# Past the hard-kill deadline (plus 60s grace) → harness crashed or was
# killed before it could clean up the marker. Treat as stale and stay quiet.
(( elapsed <= hard_kill + 60 )) || exit 0

elapsed_min=$(( elapsed / 60 ))
remaining_min=$(( (hard_kill - elapsed + 59) / 60 ))
(( remaining_min < 0 )) && remaining_min=0

# Claim the firing slot before we emit. `set -C` (noclobber) makes the
# redirect fail if the file already exists — so if two PostToolUse hooks
# race, only the one that wins the create emits.
if ! (set -C; : > "$sentinel") 2>/dev/null; then
  exit 0
fi

# Harness-specific tail: task-loop.sh wraps up by completing the current
# task MD and renaming to DONE-; improvement/loop.sh wraps up via its own
# finish.sh + commit flow.
if [[ "${CLAUDE_RUN_BY:-}" == "task-loop.sh" ]]; then
  tail_msg="Finalize NOW: complete the current task's markdown (Completion Notes), rename any in-flight task to DONE-<name>, run the project's test command, and move the DONE-* files into completed/batch-N/ if they're ready. Do NOT start a new task."
else
  tail_msg="Finalize NOW: get tests passing, and run ./improvement/finish.sh with a brief summary; if any changes are incomplete, create an LLM task so a future iteration finishes them."
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "WRAP-UP SIGNAL: this loop iteration has been running for ${elapsed_min} minutes. The watchdog will SIGTERM in roughly ${remaining_min} minutes. ${tail_msg}"
  }
}
EOF
