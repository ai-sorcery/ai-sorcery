#!/usr/bin/env bash
#
# start-proxy.sh — launch the LiteLLM proxy with our config. Foreground
# by default; pass --detach (or set DETACH=1) to fork into the background
# with logs streamed to ./logs/litellm.log and the PID recorded in
# ./logs/litellm.pid for stop-proxy.sh.
#
# Idempotent: if a live proxy is already recorded in the pid file, this
# script reports the running PID and exits 0 instead of erroring.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

# Source .env at the repo root if present (idempotent — route.sh /
# llm.sh may already have done this in our parent shell).
if [[ -f "$project_root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$project_root/.env"
  set +a
fi

cd "$script_dir"

# Prefer the project-local venv litellm so the proxy uses the pinned
# Python 3.13 install set up by setup.sh. Fall back to PATH-discovered
# litellm if the venv isn't there yet (degraded mode — uvloop on Python
# 3.14+ will crash; setup.sh exists to prevent that).
if [[ -x "./.venv/bin/litellm" ]]; then
  litellm_bin="./.venv/bin/litellm"
elif command -v litellm >/dev/null 2>&1; then
  litellm_bin="$(command -v litellm)"
  echo "start-proxy: using PATH-discovered litellm at $litellm_bin"
  echo "             (run ./setup.sh to install a pinned copy in .venv/)"
else
  echo "start-proxy: litellm not on PATH and .venv/bin/litellm missing" >&2
  echo "             run ./setup.sh first" >&2
  exit 1
fi

config="litellm.config.yaml"
if [[ ! -f "$config" ]]; then
  echo "start-proxy: $config missing — re-run install-llm-routing.sh" >&2
  exit 1
fi

mkdir -p logs
log="logs/litellm.log"
pid_file="logs/litellm.pid"

# Idempotent: a live PID means the proxy is up — exit 0 instead of error.
if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  echo "start-proxy: already running, PID $(cat "$pid_file")"
  echo "             stop with ./stop-proxy.sh; restart by stop+start."
  exit 0
fi
# Stale pid file — clean up so the new start can record cleanly.
[[ -f "$pid_file" ]] && rm -f "$pid_file"

detach=0
for arg in "$@"; do
  [[ "$arg" == "--detach" ]] && detach=1
done
[[ "${DETACH:-0}" == "1" ]] && detach=1

if (( detach )); then
  echo "start-proxy: starting LiteLLM in the background, log: $log"
  nohup "$litellm_bin" --config "$config" --host 127.0.0.1 --port 4000 >>"$log" 2>&1 &
  pid=$!
  echo "$pid" > "$pid_file"
  disown "$pid" 2>/dev/null || true
  echo "start-proxy: PID $pid"
  echo "start-proxy: tail -f $log to watch startup"
  exit 0
fi

echo "start-proxy: starting LiteLLM in the foreground (Ctrl-C to stop)"
# Background + wait (not exec) so the EXIT trap survives and cleans up
# the pidfile on Ctrl-C. With exec, bash is replaced by litellm, the trap
# is dropped, and SIGINT-killed litellm leaves a stale pidfile that
# blocks the next start.
"$litellm_bin" --config "$config" --host 127.0.0.1 --port 4000 &
pid=$!
echo "$pid" > "$pid_file"
echo "start-proxy: PID $pid (recorded in $pid_file)"
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$pid_file"' EXIT INT TERM
wait "$pid"
