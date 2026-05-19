#!/usr/bin/env bash
#
# llm.sh — one-shot entrypoint that boots the LiteLLM proxy (if it
# isn't already running) and drops you into a Swival session pointed at
# it. Lives at the repo root next to llm-routing/.
#
# Usage:
#   ./llm.sh                  # uses $LLM_PROFILE or 'frontier'
#   ./llm.sh frontier         # tier name (frontier/balanced/cheap/claude)
#   ./llm.sh --some-swival-flag …    # forwards to swival
#
# Cross-project use: cd into the target repo, then run
#   /path/to/this-repo/llm.sh
# from there. Swival picks the named profile from swival.toml (which
# defines provider, base_url, model, and max_context_tokens per tier).
# Because swival reads swival.toml from cwd, llm.sh stages this repo's
# copy at $PWD for the session and removes it on exit. If $PWD already
# has a different swival.toml the script aborts rather than clobber.
# Swival's --base-dir auto-detects from cwd, so the target repo is
# still the agent's primary workspace. To grant access to additional
# directories (e.g. a sibling repo you want the agent to read or
# edit), set SWIVAL_ADD_DIRS in .env — colon-separated absolute paths.
# llm.sh lists the current access set on launch and offers to add more.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
routing_dir="$script_dir/llm-routing"

if [[ ! -d "$routing_dir" ]]; then
  echo "llm.sh: llm-routing/ not found next to this script" >&2
  echo "        expected: $routing_dir" >&2
  exit 1
fi

# --- Source .env files ---------------------------------------------------
# Two layers:
#   1. $script_dir/.env  — provider API keys (lives with the routing setup).
#   2. $PWD/.env         — per-project overrides like SWIVAL_ADD_DIRS.
# The second layer wins on conflict (sourced after the first). When the
# user launches from $script_dir these collapse to a single file.
load_env_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$path"
  set +a
}
load_env_file "$script_dir/.env"
if [[ "$PWD" != "$script_dir" ]]; then
  load_env_file "$PWD/.env"
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

# --- Show access set and (optionally) prompt for additional dirs ---------
# Swival's --base-dir auto-detects from cwd. SWIVAL_ADD_DIRS supplies any
# extra dirs the agent should reach into (sibling repos, shared assets).
# The guard makes this a no-op on the post-re-exec second pass — without
# it the prompt would fire twice.
persist_swival_add_dirs() {
  local env_path="$1"
  local value="$2"

  if [[ -e "$env_path" ]] && grep -q '^SWIVAL_ADD_DIRS=' "$env_path"; then
    # Rewrite the existing line via a tmp file (portable across BSD/GNU sed).
    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == SWIVAL_ADD_DIRS=* ]]; then
        echo "SWIVAL_ADD_DIRS=$value"
      else
        echo "$line"
      fi
    done < "$env_path" > "$tmp"
    mv "$tmp" "$env_path"
  else
    [[ -s "$env_path" ]] && echo "" >> "$env_path"
    cat >> "$env_path" <<EOF
# Extra dirs granted to the agent via swival --add-dir. Colon-separated
# absolute paths. Added interactively by llm.sh; edit by hand any time.
SWIVAL_ADD_DIRS=$value
EOF
  fi
}

if [[ -z "${__LLM_SH_PROMPTED:-}" ]]; then
  echo "llm.sh: agent will have read/write access to:"
  echo "  - $PWD  (cwd — swival auto-detects --base-dir from here)"
  if [[ -n "${SWIVAL_ADD_DIRS:-}" ]]; then
    while IFS= read -r d; do
      [[ -n "$d" ]] && echo "  - $d  (from SWIVAL_ADD_DIRS)"
    done < <(printf '%s\n' "$SWIVAL_ADD_DIRS" | tr ':' '\n')
  fi

  if [[ -t 0 && -t 1 ]]; then
    echo ""
    printf "Add more dirs? (colon-separated, Enter to skip): "
    extras=""
    read -r extras || true
    if [[ -n "${extras:-}" ]]; then
      resolved=""
      while IFS= read -r raw; do
        # Trim leading/trailing whitespace.
        d="${raw#"${raw%%[![:space:]]*}"}"
        d="${d%"${d##*[![:space:]]}"}"
        [[ -z "$d" ]] && continue
        # Expand a leading ~.
        d="${d/#\~/$HOME}"
        if [[ -d "$d" ]]; then
          abs="$(cd "$d" && pwd)"
          resolved="${resolved:+$resolved:}$abs"
        else
          echo "llm.sh: skipping '$raw' (not a directory)" >&2
        fi
      done < <(printf '%s\n' "$extras" | tr ':' '\n')

      if [[ -n "$resolved" ]]; then
        if [[ -n "${SWIVAL_ADD_DIRS:-}" ]]; then
          SWIVAL_ADD_DIRS="$SWIVAL_ADD_DIRS:$resolved"
        else
          SWIVAL_ADD_DIRS="$resolved"
        fi
        export SWIVAL_ADD_DIRS

        # Persist to the .env file that matches launch context. When the
        # user is in $script_dir there's only one .env; otherwise prefer
        # cwd/.env so per-project access stays per-project.
        if [[ "$PWD" == "$script_dir" ]]; then
          persist_env="$script_dir/.env"
        else
          persist_env="$PWD/.env"
        fi
        persist_swival_add_dirs "$persist_env" "$SWIVAL_ADD_DIRS"
        echo "llm.sh: appended to SWIVAL_ADD_DIRS in $persist_env"
      fi
    fi
  fi

  export __LLM_SH_PROMPTED=1
fi

# --- Pick the profile (= LiteLLM tier alias) -----------------------------
# Accept either a bare tier name or pass-through swival flags. If the
# first arg starts with '-', treat the whole arg list as swival flags
# and use the default profile.
profile="${LLM_PROFILE:-frontier}"
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

# --- Build --add-dir args from SWIVAL_ADD_DIRS ----------------------------
add_dir_args=()
if [[ -n "${SWIVAL_ADD_DIRS:-}" ]]; then
  while IFS= read -r d; do
    [[ -n "$d" ]] && add_dir_args+=("--add-dir" "$d")
  done < <(printf '%s\n' "$SWIVAL_ADD_DIRS" | tr ':' '\n')
fi

# --- Stage swival.toml in cwd for cross-project launches -----------------
# Swival reads project config from <base-dir>/swival.toml (cwd by
# default). When launched from outside $script_dir the file isn't
# there, so `swival --profile frontier` would fail. Copy ours into cwd
# for the session and remove on exit. Refuse to clobber a different
# pre-existing swival.toml; adopt one whose contents already match ours
# (likely leftover from a previous run killed before cleanup).
src_toml="$script_dir/swival.toml"
dst_toml="$PWD/swival.toml"
staged_toml=0
cleanup_staged_toml() {
  if [[ "$staged_toml" == "1" ]]; then
    rm -f "$dst_toml"
  fi
}
trap cleanup_staged_toml EXIT

if [[ "$PWD" != "$script_dir" ]]; then
  if [[ -e "$dst_toml" ]]; then
    if cmp -s "$src_toml" "$dst_toml"; then
      staged_toml=1
    else
      echo "llm.sh: $dst_toml already exists with different content; won't clobber." >&2
      echo "        Move or remove it first, or launch from $script_dir." >&2
      exit 1
    fi
  else
    cp "$src_toml" "$dst_toml"
    staged_toml=1
    echo "llm.sh: staged swival profile config in $PWD (removed on exit)"
  fi
fi

# --- Run swival via the named profile ------------------------------------
# --profile pulls provider, base_url, model, and max_context_tokens from
# the [profiles.$profile] block in swival.toml. --api-key stays on the
# CLI because we deliberately don't store it in the (git-tracked) toml.
# Not using `exec` so the EXIT trap above can fire and clean the
# staged toml when swival returns.
swival \
  --profile "$profile" \
  --api-key not-needed \
  ${add_dir_args[@]+"${add_dir_args[@]}"} \
  "$@"
