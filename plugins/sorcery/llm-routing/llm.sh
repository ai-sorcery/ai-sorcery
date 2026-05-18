#!/usr/bin/env bash
#
# llm.sh — one-shot entrypoint that boots the LiteLLM proxy (if it
# isn't already running) and drops you into a Swival session pointed at
# it. Lives at the repo root next to llm-routing/.
#
# Usage:
#   ./llm.sh                  # uses $LLM_PROFILE or 'claude'
#   ./llm.sh claude           # tier name (claude/frontier/balanced/cheap)
#   ./llm.sh --some-swival-flag …    # forwards to swival
#
# Cross-project use: drop a one-line wrapper at the other repo's root —
#   exec /path/to/this-repo/llm.sh "$@"
# — and run it from there. Swival is invoked with explicit --provider /
# --base-url / --model / --api-key flags so cwd doesn't matter.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
routing_dir="$script_dir/llm-routing"

if [[ ! -d "$routing_dir" ]]; then
  echo "llm.sh: llm-routing/ not found next to this script" >&2
  echo "        expected: $routing_dir" >&2
  exit 1
fi

# --- Source .env if present ----------------------------------------------
# Keys end up in litellm via os.environ/<NAME> at proxy start time. The
# rest of the script (and start-proxy.sh, route.sh) inherit them.
if [[ -f "$script_dir/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$script_dir/.env"
  set +a
fi

# --- Re-exec inside the nix dev shell ------------------------------------
# IN_NIX_SHELL is set automatically by `nix develop`. If we're not in one,
# re-launch ourselves through it so litellm / bun / uv are on PATH.
if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  if ! command -v nix >/dev/null 2>&1; then
    echo "llm.sh: nix not on PATH. Run ./llm-routing/setup.sh first." >&2
    exit 1
  fi
  exec nix develop "$routing_dir" --command bash "$0" "$@"
fi

# --- Pick the profile (= LiteLLM tier alias) -----------------------------
# Accept either a bare tier name or pass-through swival flags. If the
# first arg starts with '-', treat the whole arg list as swival flags
# and use the default profile.
profile="${LLM_PROFILE:-claude}"
if [[ $# -gt 0 && "$1" != -* ]]; then
  profile="$1"
  shift
fi

# --- Start the proxy idempotently ----------------------------------------
proxy_url="http://127.0.0.1:4000"

is_proxy_up() {
  curl --silent --fail --max-time 1 "$proxy_url/health/readiness" >/dev/null 2>&1
}

if ! is_proxy_up; then
  echo "llm.sh: starting LiteLLM proxy in the background"
  ( cd "$routing_dir" && DETACH=1 bash start-proxy.sh )
  # Wait up to ~15s for /health/readiness to respond.
  for _ in $(seq 1 30); do
    if is_proxy_up; then break; fi
    sleep 0.5
  done
  if ! is_proxy_up; then
    echo "llm.sh: proxy did not become ready in time" >&2
    echo "        check $routing_dir/logs/litellm.log" >&2
    exit 1
  fi
else
  echo "llm.sh: LiteLLM proxy already up at $proxy_url"
fi

# --- Exec swival with explicit flags -------------------------------------
# Explicit flags mean we don't depend on cwd containing swival.toml — the
# script works from any project root that wraps llm.sh.
exec swival \
  --provider generic \
  --base-url "$proxy_url" \
  --model "$profile" \
  --api-key not-needed \
  "$@"
