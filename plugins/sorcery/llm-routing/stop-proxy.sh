#!/usr/bin/env bash
#
# stop-proxy.sh — terminate the LiteLLM proxy started by start-proxy.sh.
# Reads ./logs/litellm.pid for the PID; falls back to pkill-style search
# if the pidfile is stale.

set -euo pipefail

cd "$(dirname "$0")"

pid_file="logs/litellm.pid"

if [[ -f "$pid_file" ]]; then
  pid="$(cat "$pid_file")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "stop-proxy: sending SIGTERM to PID $pid"
    kill "$pid"
    # Give it up to 5s to exit cleanly, then SIGKILL.
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "stop-proxy: still alive — sending SIGKILL"
      kill -9 "$pid" || true
    fi
    rm -f "$pid_file"
    echo "stop-proxy: stopped."
    exit 0
  fi
  echo "stop-proxy: $pid_file points at dead PID $pid — cleaning up"
  rm -f "$pid_file"
fi

# Fallback: try to find a litellm process bound to our config. start-proxy.sh
# invokes litellm with the relative path `litellm.config.yaml`, so the pgrep
# pattern matches that — anchoring on $(pwd) would never hit.
if pid=$(pgrep -f "litellm --config litellm.config.yaml" 2>/dev/null | head -n1); then
  if [[ -n "$pid" ]]; then
    echo "stop-proxy: found stray PID $pid bound to our config — terminating"
    kill "$pid" || true
    exit 0
  fi
fi

echo "stop-proxy: nothing to stop (no pidfile, no matching process)."
