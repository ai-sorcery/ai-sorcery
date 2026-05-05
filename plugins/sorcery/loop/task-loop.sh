#!/usr/bin/env bash
#
# task-loop.sh — LLM-task worker loop.
#
# Companion to improvement/loop.sh. Instead of running general improvements, it
# wakes Claude up repeatedly until every pending LLM task has been finished,
# automatically recovering from stalls and crashes.
#
# Behaviour per iteration:
#   1. Count pending task files in llm-tasks/ (anything not DONE-* or IGNORE-*).
#   2. If zero, sleep for TASK_LOOP_IDLE_WAIT (default 15m) and re-check. This
#      lets the loop keep running so the next batch is picked up without a
#      manual restart.
#   3. Otherwise, launch `claude -p` with an inline prompt telling Claude
#      it's running under the task-loop harness and how to recover from
#      prior iterations via the prev-log-file hint.
#   4. Output is tee'd into data/task-loop-logs/task-$TS.log so a later
#      iteration can read the previous iteration's state to resume.
#   5. Kill-switches honored: touch stop.txt OR press q/s/h to end cleanly
#      at the end of the current iteration.
#
# Expected to live at the repo root (task-loop.sh is self-contained; drop it
# alongside your llm-tasks/ directory and run it from there).
#
# Kill-signals for runaway iterations come from the same watchdog pattern as
# improvement/loop.sh (SIGTERM after TASK_LOOP_MAX_RUN, SIGKILL 10s later).
#
# Configuration (env vars):
#   TASK_LOOP_IDLE_WAIT       seconds to wait when pending=0 (default 900 = 15m)
#   TASK_LOOP_WAIT            seconds between successful iterations when pending>0 (default 60)
#   TASK_LOOP_FAIL_WAIT       seconds to wait after a failed iteration (default 600 = 10m)
#   TASK_LOOP_MAX_RUN         per-iteration wall-clock ceiling (default 5400 = 90m)
#   TASK_LOOP_MIN_RUN         iterations shorter than this count as failures (default 10)
#   TASK_LOOP_RESULT_GRACE    seconds to let Claude exit after first result event (default 15)
#   TASK_LOOP_LOG_DIR         log directory (default data/task-loop-logs)
#   TASK_LOOP_STOP_FILE       sentinel file that terminates the loop (default stop.txt)
#   TASK_LOOP_EXIT_WHEN_DONE  if "1", exit instead of idling when pending=0 (default 0)

# Deliberately omit `set -e`: an intermediate failure (e.g., a bad jq pipe or
# a missing optional log file from the previous iteration) should NOT abort
# the harness. `set -u` + `pipefail` still catch undefined vars and silently
# swallowed pipe failures.
set -uo pipefail

cd "$(dirname "$0")"

# Force OAuth auth; prevents silent fallback to a stale API key.
unset ANTHROPIC_API_KEY

: "${TASK_LOOP_IDLE_WAIT:=900}"
: "${TASK_LOOP_WAIT:=60}"
: "${TASK_LOOP_FAIL_WAIT:=600}"
: "${TASK_LOOP_MIN_RUN:=10}"
: "${TASK_LOOP_MAX_RUN:=5400}"
: "${TASK_LOOP_RESULT_GRACE:=15}"
: "${TASK_LOOP_LOG_DIR:=data/task-loop-logs}"
: "${TASK_LOOP_STOP_FILE:=stop.txt}"
: "${TASK_LOOP_EXIT_WHEN_DONE:=0}"

mkdir -p "$TASK_LOOP_LOG_DIR"

# Shared marker with improvement/loop.sh so improvement/wrap-up-hook.sh fires
# for task-loop.sh iterations too. Only one loop harness should run at a time.
rm -f improvement/.iteration-start improvement/.wrap-up-fired 2>/dev/null || true

format_duration() {
  local total=$1
  local hrs=$(( total / 3600 ))
  local mins=$(( (total % 3600) / 60 ))
  local secs=$(( total % 60 ))
  if (( hrs > 0 )); then
    printf '%dh%dm' "$hrs" "$mins"
  elif (( mins > 0 )); then
    printf '%dm%02ds' "$mins" "$secs"
  else
    printf '%ds' "$secs"
  fi
}

# Count pending LLM tasks: .md files directly in llm-tasks/ that are neither
# DONE- nor IGNORE-. Matches the filing conventions in the using-llm-tasks
# skill (pending files stay in llm-tasks/ root; DONE- get archived into
# completed/batch-N/; IGNORE- are drafts).
count_pending() {
  [[ -d llm-tasks ]] || { echo 0; return; }
  find llm-tasks -maxdepth 1 -type f -name '*.md' \
    ! -name 'DONE-*' ! -name 'IGNORE-*' 2>/dev/null \
    | wc -l | tr -d ' '
}

# Wait up to $1 seconds, honoring stop.txt and q/s/h keystrokes. Returns 1 if
# the user asked to quit.
wait_for_next_loop() {
  local remaining=$1
  local label="$2"
  local key=''
  while (( remaining > 0 )); do
    if [[ -f "$TASK_LOOP_STOP_FILE" ]]; then
      printf '\nstop file detected, ending loop\n'
      return 1
    fi
    if (( remaining % 10 == 0 )); then
      local mins=$(( remaining / 60 ))
      local secs=$(( remaining % 60 ))
      if (( secs == 0 )); then
        printf '\r%s %dm...       ' "$label" "$mins"
      else
        printf '\r%s %dm%02ds...   ' "$label" "$mins" "$secs"
      fi
    fi
    key=''
    IFS= read -rsn1 -t 1 key || true
    case "$key" in
      q|s|h)
        printf '\n%q detected, ending loop\n' "$key"
        return 1
        ;;
    esac
    remaining=$(( remaining - 1 ))
  done
  printf '\n'
  return 0
}

iteration=0
prev_log_file=""
loop_start_ts=$(date +%s)

while true; do
  if [[ -f "$TASK_LOOP_STOP_FILE" ]]; then
    echo "stop file detected, ending loop"
    break
  fi

  pending=$(count_pending)
  pending=${pending//[[:space:]]/}
  pending=${pending:-0}

  if (( pending == 0 )); then
    printf '\n\033[1;42;30m === no pending tasks (iteration %d total runtime %s) === \033[0m\n' \
      "$iteration" "$(format_duration $(( $(date +%s) - loop_start_ts )))"
    if [[ "$TASK_LOOP_EXIT_WHEN_DONE" == "1" ]]; then
      echo "all tasks done; exiting (TASK_LOOP_EXIT_WHEN_DONE=1)"
      break
    fi
    wait_for_next_loop "$TASK_LOOP_IDLE_WAIT" "idle, re-check in" || break
    continue
  fi

  iteration=$(( iteration + 1 ))
  ts=$(date '+%Y%m%d-%H%M%S')
  log_file="$TASK_LOOP_LOG_DIR/task-$ts.log"

  printf '\n\033[1;44;97m === iteration %d :: pending=%d :: %s :: log=%s === \033[0m\n' \
    "$iteration" "$pending" "$ts" "$log_file"

  start_ts=$(date +%s)
  # Shared marker with improvement/wrap-up-hook.sh (see above).
  mkdir -p improvement 2>/dev/null || true
  echo "$start_ts" > improvement/.iteration-start
  rm -f improvement/.wrap-up-fired

  # Signal context to the nested Claude via env vars. The prompt below tells
  # Claude how to use them.
  export CLAUDE_RUN_BY="task-loop.sh"
  export TASK_LOOP_ITERATION="$iteration"
  export TASK_LOOP_LOG_FILE="$log_file"
  export TASK_LOOP_PREV_LOG_FILE="$prev_log_file"

  # Inline prompt (heredoc) — tells Claude it's running under the harness and
  # how to recover. Heredoc stays legible here instead of being smuggled
  # through shell escapes.
  read -r -d '' loop_prompt <<PROMPT || true
You are running inside \`task-loop.sh\`, a harness that restarts you after stalls or crashes so no LLM task is left half-done. This is iteration ${iteration}.

**Context signals** (all set in your process env):
- \`CLAUDE_RUN_BY=task-loop.sh\` — you are in the loop.
- \`TASK_LOOP_ITERATION=${iteration}\` — the counter.
- \`TASK_LOOP_LOG_FILE=${log_file}\` — your output is tee'd here.
- \`TASK_LOOP_PREV_LOG_FILE=${prev_log_file}\` — previous iteration's log (empty on iteration 1).

If iteration ≥ 2, \`tail -n 400 "\$TASK_LOOP_PREV_LOG_FILE"\` shows what the previous iteration was doing before it died. Use it to resume — don't redo completed work.

**Workflow:** invoke the \`using-llm-tasks\` skill and follow its "work the next task" flow. Concretely:
1. List pending tasks (the skill will use \`llm-tasks.sh list\`).
2. Pick the first pending one and work it through the four-section lifecycle (Initial Understanding → Tentative Plan → Implementation → Completion Notes).
3. Mark it DONE via the skill (renames to \`DONE-<name>.md\`).
4. After all pending tasks are done, archive the DONE-* files via the skill's archive flow (\`llm-tasks.sh archive\` → moves them to \`llm-tasks/completed/batch-N/\`).
5. Run the project's test command between tasks to catch regressions.
6. Do **not** commit unless the user explicitly authorized it for this session (default: no auto-commits).

**Loop-termination signals:**
- If you finish everything, \`touch improvement/.task-loop-done\` and exit. The harness treats that as loop-complete and stops.
- If the same task repeatedly kills the iteration (≥ 3 restarts mid-task), rename its file with an \`IGNORE-\` prefix, note the blocker in the task's notes, and move on.
PROMPT

  claude -p \
      --model "claude-opus-4-7[1m]" \
      --effort max \
      --dangerously-skip-permissions \
      --output-format stream-json \
      --verbose \
      --include-partial-messages \
      "$loop_prompt" \
      < /dev/null \
      > >(tee "$log_file" | jq --unbuffered -rj -f improvement/stream.jq | bun improvement/render.ts) &
  claude_pid=$!

  # Watchdog: SIGTERM then SIGKILL if the iteration exceeds TASK_LOOP_MAX_RUN.
  (
    sleep "$TASK_LOOP_MAX_RUN"
    if kill -0 "$claude_pid" 2>/dev/null; then
      printf '\niteration exceeded %ds — sending SIGTERM to %d\n' \
        "$TASK_LOOP_MAX_RUN" "$claude_pid" >&2
      kill -TERM "$claude_pid" 2>/dev/null || true
      sleep 10
      kill -KILL "$claude_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  # Runtime ticker every 60s while claude is running.
  (
    while kill -0 "$claude_pid" 2>/dev/null; do
      sleep 60
      if kill -0 "$claude_pid" 2>/dev/null; then
        elapsed=$(( $(date +%s) - start_ts ))
        printf '\n\033[45;97m ⏱ iter=%d elapsed=%s \033[0m\n' \
          "$iteration" "$(format_duration "$elapsed")"
      fi
    done
  ) &
  ticker_pid=$!

  # Quit-key listener.
  quit_flag="$TASK_LOOP_LOG_DIR/.quit-requested"
  rm -f "$quit_flag"
  (
    while kill -0 "$claude_pid" 2>/dev/null; do
      IFS= read -rsn1 -t 1 key 2>/dev/null || continue
      case "$key" in
        q|s|h)
          printf '\n\033[1;43;30m %s pressed — will stop after this iteration finishes \033[0m\n' "$key"
          touch "$quit_flag"
          break
          ;;
      esac
    done
  ) &
  keylistener_pid=$!

  # Result watcher — short grace after the first `result` event.
  (
    while kill -0 "$claude_pid" 2>/dev/null; do
      if grep -qm1 '"type":"result"' "$log_file" 2>/dev/null; then
        sleep "$TASK_LOOP_RESULT_GRACE"
        if kill -0 "$claude_pid" 2>/dev/null; then
          printf '\n\033[33m[task-loop] result emitted %ss ago but claude still running — SIGTERM\033[0m\n' \
            "$TASK_LOOP_RESULT_GRACE" >&2
          kill -TERM "$claude_pid" 2>/dev/null || true
          sleep 5
          kill -KILL "$claude_pid" 2>/dev/null || true
        fi
        break
      fi
      sleep 1
    done
  ) &
  result_watcher_pid=$!

  claude_rc=0
  wait "$claude_pid" || claude_rc=$?

  kill "$watchdog_pid" "$ticker_pid" "$keylistener_pid" "$result_watcher_pid" 2>/dev/null || true
  wait "$watchdog_pid" "$ticker_pid" "$keylistener_pid" "$result_watcher_pid" 2>/dev/null || true

  end_ts=$(date +%s)
  duration=$(( end_ts - start_ts ))
  rm -f improvement/.iteration-start improvement/.wrap-up-fired 2>/dev/null || true

  if (( claude_rc == 0 )); then
    end_color='\033[1;42;30m'; status_label="status=ok"
  else
    end_color='\033[1;41;97m'; status_label="status=fail"
  fi
  printf "\n${end_color} === iteration %d done :: %s :: %s === \033[0m\n" \
    "$iteration" "$status_label" "$(format_duration "$duration")"

  prev_log_file="$log_file"

  if [[ -f "improvement/.task-loop-done" ]]; then
    echo "improvement/.task-loop-done detected — all work finished, exiting"
    rm -f improvement/.task-loop-done
    break
  fi

  if [[ -f "$quit_flag" ]]; then
    rm -f "$quit_flag"
    printf 'quit requested during iteration, ending loop\n'
    break
  fi

  if (( claude_rc != 0 )) || (( duration < TASK_LOOP_MIN_RUN )); then
    printf 'iteration failed (exit=%d, duration=%ds); waiting %ds before retry\n' \
      "$claude_rc" "$duration" "$TASK_LOOP_FAIL_WAIT"
    wait_for_next_loop "$TASK_LOOP_FAIL_WAIT" "retry in" || break
  else
    wait_for_next_loop "$TASK_LOOP_WAIT" "next iteration in" || break
  fi
done
