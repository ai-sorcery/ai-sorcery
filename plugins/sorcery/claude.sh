#!/usr/bin/env bash
# Launch Claude Code with privacy-friendly defaults; extra args pass through.
#
# Defaults applied to every launch:
#   --effort max             — deepest reasoning level
#   --model claude-opus-4-7  — pin to Opus 4.7
#   --rc                     — hidden CLI flag, on by default
#                              (opt out by setting SKIP_RC=1; see below)
#
# Env-var inputs (callers set these; the launcher reads them):
#   IS_DEMO=1                — hide email/org from the welcome banner
#                              (undocumented Anthropic env var, v2.1.116;
#                              also skips first-run onboarding prompts)
#   SKIP_RC=1                — omit --rc so the remote-control URL stays
#                              out of screen recordings. demo-claude.sh
#                              at the repo root is a wrapper that sets it.
#
# Auto-updates marketplace-installed plugins at most once per hour via a
# sentinel at ~/.claude/.last-plugin-update. Updates fire BEFORE the exec so
# they take effect on this launch ("restart required to apply" per `claude
# plugin update --help`; the upcoming exec is that restart).
#
# Coverage:
#   - Every user-scope plugin (default install scope).
#   - Every project-scope plugin whose projectPath matches the current cwd
#     (so launching from repo X doesn't try to update repo Y's plugins).
#   - --plugin-dir locals are NOT touched: Claude Code reads them from disk
#     at every launch, so they're already current with whatever the
#     filesystem holds; refresh those via `git pull` in your normal flow.
#
# Project-scope filtering needs jq. Without jq, the launcher falls back to
# updating user-scope only via the human-readable list parser.

set -euo pipefail

THROTTLE_SECONDS=$((60 * 60))
SENTINEL="$HOME/.claude/.last-plugin-update"

needs_update() {
  [[ ! -f "$SENTINEL" ]] && return 0
  local now mtime
  now=$(date +%s)
  mtime=$(stat -f %m "$SENTINEL" 2>/dev/null || echo 0)
  (( now - mtime >= THROTTLE_SECONDS ))
}

if needs_update; then
  echo "[claude.sh] auto-updating plugins (throttle: 60m)..." >&2

  claude plugin marketplace update >/dev/null 2>&1 || true

  if command -v jq >/dev/null 2>&1; then
    cwd="$(pwd)"
    while IFS=$'\t' read -r scope id; do
      [[ -z "$id" ]] && continue
      claude plugin update --scope "$scope" "$id" >/dev/null 2>&1 || true
    done < <(
      claude plugin list --json 2>/dev/null | jq -r --arg cwd "$cwd" '
        .[]
        | select(.scope == "user" or (.scope == "project" and .projectPath == $cwd))
        | "\(.scope)\t\(.id)"
      ' 2>/dev/null
    )
  else
    while IFS= read -r plugin_id; do
      [[ -z "$plugin_id" ]] && continue
      claude plugin update "$plugin_id" >/dev/null 2>&1 || true
    done < <(claude plugin list 2>/dev/null | grep -E '^[[:space:]]+❯' | awk '{print $2}')
  fi

  mkdir -p "$(dirname "$SENTINEL")"
  touch "$SENTINEL"
fi

if [[ "${SKIP_RC:-}" == "1" ]]; then
  exec env IS_DEMO=1 claude --effort max --model claude-opus-4-7 "$@"
else
  exec env IS_DEMO=1 claude --rc --effort max --model claude-opus-4-7 "$@"
fi
