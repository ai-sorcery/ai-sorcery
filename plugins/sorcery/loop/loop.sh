#!/usr/bin/env bash
# loop.sh — self-improvement loop harness.
#
# Runs Claude Code repeatedly, one iteration at a time, with a four-subprocess
# watchdog (wall-clock timeout, runtime ticker, quit-key listener, result-event
# grace period). Each iteration reads improvement/LOOP.md for its instructions.
#
# Expected to live at improvement/loop.sh in the target repo — it cds one level
# up so all paths below resolve against the repo root.
#
# See improvement/LOOP.md for what happens inside an iteration.

set -euo pipefail

# Run from repo root regardless of the CWD the script was invoked from.
cd "$(dirname "$0")/.."

# Force OAuth auth; prevents silent fallback to a stale API key that may not
# match the account you expect this loop to bill against.
unset ANTHROPIC_API_KEY

: "${LOOP_WAIT:=300}"           # seconds between successful iterations
: "${LOOP_FAIL_WAIT:=3600}"     # 60-minute penalty after a failed iteration
: "${LOOP_MIN_RUN:=10}"         # runs shorter than this count as failures
: "${LOOP_MAX_RUN:=5400}"       # runs longer than this are force-killed (90 min)
: "${LOOP_RESULT_GRACE:=15}"    # seconds to wait after first `result` before SIGTERM
: "${LOOP_LOG_DIR:=improvement/logs}"
: "${LOOP_STOP_FILE:=stop.txt}" # sentinel file that terminates the loop

mkdir -p "$LOOP_LOG_DIR"

# Clean up any stale iteration marker from a previous crashed/killed run.
rm -f improvement/.iteration-start improvement/.wrap-up-fired

loop_start_ts=$(date +%s)

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

# Wait up to $1 seconds, prefixing the countdown with $2. Returns 1 if the
# user asked to stop (q/s/h or stop.txt).
wait_for_next_loop() {
  local remaining=$1
  local label="$2"
  local key=''

  while (( remaining > 0 )); do
    if [[ -f "$LOOP_STOP_FILE" ]]; then
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
while true; do
  if [[ -f "$LOOP_STOP_FILE" ]]; then
    echo "stop file detected, ending loop"
    break
  fi

  iteration=$(( iteration + 1 ))
  ts=$(date '+%Y%m%d-%H%M%S')
  log_file="$LOOP_LOG_DIR/loop-$ts.log"

  printf '\n\033[1;44;97m === iteration %d :: %s :: log=%s === \033[0m\n' \
    "$iteration" "$ts" "$log_file"

  start_ts=$(date +%s)
  # Marker file consumed by improvement/wrap-up-hook.sh to compute elapsed time.
  # Cleaned up at iteration end; surviving marker = previous run crashed.
  echo "$start_ts" > improvement/.iteration-start
  rm -f improvement/.wrap-up-fired

  # Process substitution (not a pipeline) so `wait` sees claude's real exit
  # code. `< /dev/null` so the background key listener below can own stdin
  # without claude grabbing keystrokes first.
  claude -p \
      --model "claude-opus-4-7[1m]" \
      --effort max \
      --dangerously-skip-permissions \
      --output-format stream-json \
      --verbose \
      --include-partial-messages \
      "Look at improvement/LOOP.md" \
      < /dev/null \
      > >(tee "$log_file" | jq --unbuffered -rj -f improvement/stream.jq | bun improvement/render.ts) &
  claude_pid=$!

  # Watchdog: SIGTERM then SIGKILL if the iteration exceeds LOOP_MAX_RUN.
  (
    sleep "$LOOP_MAX_RUN"
    if kill -0 "$claude_pid" 2>/dev/null; then
      printf '\niteration exceeded %ds — sending SIGTERM to %d\n' \
        "$LOOP_MAX_RUN" "$claude_pid" >&2
      kill -TERM "$claude_pid" 2>/dev/null || true
      sleep 10
      kill -KILL "$claude_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  # Runtime ticker: total loop runtime every 60s while claude is running.
  (
    while kill -0 "$claude_pid" 2>/dev/null; do
      sleep 60
      if kill -0 "$claude_pid" 2>/dev/null; then
        elapsed=$(( $(date +%s) - loop_start_ts ))
        printf '\n\033[45;97m ⏱ Total Runtime: %s \033[0m\n' "$(format_duration "$elapsed")"
      fi
    done
  ) &
  ticker_pid=$!

  # Key listener: detect q/s/h during the iteration so the current one
  # finishes cleanly before the loop exits.
  quit_flag="$LOOP_LOG_DIR/.quit-requested"
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

  # Result watcher: once claude emits its first `"type":"result"` event, wait
  # a short grace period for natural exit, then SIGTERM stubborn processes.
  # Without this, outstanding Monitor/ScheduleWakeup tasks can keep claude
  # alive for minutes after the iteration's real work is done.
  (
    while kill -0 "$claude_pid" 2>/dev/null; do
      if grep -qm1 '"type":"result"' "$log_file" 2>/dev/null; then
        sleep "$LOOP_RESULT_GRACE"
        if kill -0 "$claude_pid" 2>/dev/null; then
          printf '\n\033[33m[loop] result emitted %ss ago but claude still running — SIGTERM\033[0m\n' \
            "$LOOP_RESULT_GRACE" >&2
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

  # `wait` returns claude's real exit code; `|| claude_rc=$?` keeps us moving
  # to the cleanup step even when claude exited non-zero (otherwise `set -e`
  # would abort the loop mid-iteration and leak the watchdog subprocesses).
  claude_rc=0
  wait "$claude_pid" || claude_rc=$?

  # Retire the watchdog, ticker, key listener, and result watcher.
  kill "$watchdog_pid" "$ticker_pid" "$keylistener_pid" "$result_watcher_pid" 2>/dev/null || true
  wait "$watchdog_pid" "$ticker_pid" "$keylistener_pid" "$result_watcher_pid" 2>/dev/null || true

  end_ts=$(date +%s)
  duration=$(( end_ts - start_ts ))
  rm -f improvement/.iteration-start improvement/.wrap-up-fired

  if (( claude_rc == 0 )); then status_label="status=ok"; else status_label="status=fail"; fi
  if (( claude_rc == 0 )); then end_color='\033[1;42;30m'; else end_color='\033[1;41;97m'; fi
  printf "\n${end_color} === iteration %d done :: %s :: Iteration Runtime: %s === \033[0m\n" \
    "$iteration" "$status_label" "$(format_duration "$duration")"

  if [[ -f "$quit_flag" ]]; then
    rm -f "$quit_flag"
    printf 'quit requested during iteration, ending loop\n'
    break
  fi

  echo "Press q/s/h (or touch stop.txt) to end the loop."
  if (( claude_rc != 0 )) || (( duration < LOOP_MIN_RUN )); then
    printf 'iteration failed (exit=%d, duration=%ds); waiting %ds before retry\n' \
      "$claude_rc" "$duration" "$LOOP_FAIL_WAIT"
    wait_for_next_loop "$LOOP_FAIL_WAIT" "retry in" || break
  else
    wait_for_next_loop "$LOOP_WAIT" "next iteration in" || break
  fi
done
