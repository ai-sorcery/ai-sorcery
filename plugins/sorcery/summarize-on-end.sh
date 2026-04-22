#!/usr/bin/env bash
# summarize-on-end — SessionEnd hook body.
#
# Receives Claude Code's SessionEnd JSON on stdin, derives the transcript path,
# forks a detached `claude -p` with Haiku + a forced JSON schema, and writes a
# markdown summary to ~/LLM_Summaries/YYYY-MM-DD/.
#
# Recursion is prevented by setting CLAUDE_SUMMARY_HOOK=1 when spawning the
# inner claude. The SessionEnd hook command pre-check in settings.json also
# exits early if that var is set.
#
# The script self-forks at startup so the inner `claude -p` (which can take
# 5-15s) survives Claude Code exiting and the controlling terminal closing.

set -uo pipefail

# Recursion guard.
if [ -n "${CLAUDE_SUMMARY_HOOK:-}" ]; then
  exit 0
fi

# Self-fork into a detached background process so we survive the user exiting
# Claude Code (and even the terminal closing).
if [ -z "${SUMMARIZE_DETACHED:-}" ]; then
  tmp="$(mktemp -t summarize-on-end-input.XXXXXX)"
  cat > "$tmp"
  SUMMARIZE_DETACHED=1 SUMMARIZE_INPUT_FILE="$tmp" \
    nohup bash "$0" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  exit 0
fi

# === Detached path ===

log_dir="$HOME/LLM_Summaries"
mkdir -p "$log_dir" 2>/dev/null || true
log="$log_dir/.summarize-on-end.log"

script_dir="$(cd "$(dirname "$0")" && pwd)"
writer="$script_dir/write-llm-summary.sh"

input="$(cat "${SUMMARIZE_INPUT_FILE:-/dev/null}" 2>/dev/null || echo "")"
rm -f "${SUMMARIZE_INPUT_FILE:-}" 2>/dev/null || true

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")"

# Derive transcript path from session_id + cwd if payload didn't carry it.
if [ -z "$transcript_path" ] && [ -n "$session_id" ] && [ -n "$cwd" ]; then
  sanitized="${cwd//\//-}"
  transcript_path="$HOME/.claude/projects/${sanitized}/${session_id}.jsonl"
fi

if [ -z "${transcript_path:-}" ] || [ ! -f "$transcript_path" ]; then
  echo "$(date '+%F %T') skip: no transcript (session=$session_id derived=$transcript_path)" >> "$log"
  exit 0
fi

# Skip sub-agent sessions — only the top-level session should produce a summary.
# Claude Code stores sub-agent transcripts under `<session>/subagents/agent-*.jsonl`.
# Without this guard, a single iteration that spawns N sub-agents ends up with
# N+1 summary files all stamped within the same minute.
if [[ "$transcript_path" == */subagents/* ]]; then
  echo "$(date '+%F %T') skip: subagent transcript ($transcript_path) session=$session_id" >> "$log"
  exit 0
fi

# Defensive fallback: if the transcript's first messages carry isSidechain=true,
# treat it as a sub-agent even when the path heuristic fails.
if head -n 50 "$transcript_path" 2>/dev/null | grep -q '"isSidechain":[[:space:]]*true'; then
  echo "$(date '+%F %T') skip: isSidechain transcript ($transcript_path) session=$session_id" >> "$log"
  exit 0
fi

# Extract clean dialogue: user messages, assistant text, and tool-call markers.
# Skips thinking blocks, raw tool results, attachments, internal bookkeeping.
dialogue="$(jq -r '
  select(.type == "user" or .type == "assistant") |
  .message.content as $c |
  if ($c | type) == "string" then
    "[\(.type | ascii_upcase)]: \($c)"
  elif ($c | type) == "array" then
    (
      [$c[]? |
        if .type == "text" then .text
        elif .type == "tool_use" then "[→ tool: \(.name)]"
        else empty
        end
      ] | map(select(. != null and . != "")) | join("\n\n")
    ) as $txt |
    if $txt == "" then empty
    else "[\(.type | ascii_upcase)]: \($txt)"
    end
  else empty
  end
' "$transcript_path" 2>/dev/null | head -c 150000)"

if [ -z "$dialogue" ]; then
  echo "$(date '+%F %T') skip: could not extract dialogue from transcript ($transcript_path)" >> "$log"
  exit 0
fi

schema='{"type":"object","properties":{"skip":{"type":"boolean","description":"true iff session was trivial (single question, no real work)"},"title":{"type":"string","description":"3-6 words, 15-60 chars, captures the session theme, no trailing punctuation"},"body":{"type":"string","description":"3-7 markdown bullet lines summarizing what happened, with concrete identifiers (paths, symbols, SHAs, error messages) over vague prose"}},"required":["skip","title","body"]}'

system_prompt='You are a summarization tool for Claude Code session transcripts. You observe and summarize sessions from the outside — you never continue them, acknowledge them, or respond conversationally. Always output a single JSON object matching the requested schema.'

user_prompt="Summarize the Claude Code session whose transcript appears below.

Set skip=true only when the session was genuinely trivial (e.g., a single question
with no real work, or just a few exchanges that produced nothing worth remembering).
Otherwise set skip=false and fill in title and body with concrete, greppable content.

=== TRANSCRIPT START ===
$dialogue
=== TRANSCRIPT END ==="

# Call Haiku with forced JSON-schema output. `--system-prompt` replaces the default
# Claude Code system prompt so Haiku doesn't try to respond as a CC assistant.
full_output="$(CLAUDE_SUMMARY_HOOK=1 claude -p "$user_prompt" \
  --model claude-haiku-4-5-20251001 \
  --system-prompt "$system_prompt" \
  --json-schema "$schema" \
  --output-format json \
  --no-session-persistence 2>>"$log")" || {
  echo "$(date '+%F %T') error: claude -p failed (exit=$?) for session=$session_id" >> "$log"
  exit 0
}

is_error="$(printf '%s' "$full_output" | jq -r '.is_error // false' 2>/dev/null || echo "true")"
if [ "$is_error" = "true" ]; then
  reason="$(printf '%s' "$full_output" | jq -r '.api_error_status // .error // "unknown"' 2>/dev/null)"
  echo "$(date '+%F %T') error: claude reported is_error for session=$session_id reason=$reason" >> "$log"
  exit 0
fi

# With --json-schema, the model's schema-conformant output lands under
# `.structured_output`, not the top-level `content` field that plain -p uses.
skip="$(printf '%s' "$full_output" | jq -r '.structured_output.skip // false' 2>/dev/null)"
title="$(printf '%s' "$full_output" | jq -r '.structured_output.title // empty' 2>/dev/null)"
body="$(printf '%s' "$full_output" | jq -r '.structured_output.body // empty' 2>/dev/null)"
cost="$(printf '%s' "$full_output" | jq -r '.total_cost_usd // 0' 2>/dev/null)"

if [ "$skip" = "true" ]; then
  echo "$(date '+%F %T') skip: model marked trivial for session=$session_id (cost=\$$cost)" >> "$log"
  exit 0
fi

if [ -z "$title" ] || [ -z "$body" ]; then
  snippet="$(printf '%s' "$full_output" | jq -c '.structured_output // {note: "no structured_output"}' 2>/dev/null | head -c 300)"
  echo "$(date '+%F %T') skip: missing title/body for session=$session_id; structured=$snippet" >> "$log"
  exit 0
fi

# Belt-and-suspenders title cap (write-llm-summary.sh also caps).
if [ "${#title}" -gt 80 ]; then
  title="${title:0:77}..."
fi

if printf '%s\n' "$body" | bash "$writer" "$title" >> "$log" 2>&1; then
  echo "$(date '+%F %T') saved summary for session=$session_id title=\"$title\" cost=\$$cost" >> "$log"
else
  echo "$(date '+%F %T') error: write-llm-summary.sh failed for session=$session_id title=\"$title\"" >> "$log"
fi
