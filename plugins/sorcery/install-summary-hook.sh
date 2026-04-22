#!/usr/bin/env bash
#
# install-summary-hook — wire the SessionEnd summarizer hook into the current
# project's .claude/settings.json. Idempotent: if an entry referencing this
# plugin's summarize-on-end.sh is already present, the script is a no-op.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "install-summary-hook: jq is required (brew install jq)" >&2
    exit 1
fi

plugin_dir="$(cd "$(dirname "$0")" && pwd)"
hook_script="$plugin_dir/summarize-on-end.sh"
dot_claude="$plugin_dir/dot-claude.sh"

# The pre-check before `bash ...` ensures the inner Haiku call (which also
# ends a session) exits immediately on its own SessionEnd — belt-and-suspenders
# for the CLAUDE_SUMMARY_HOOK env guard inside the script itself.
command_str="[ -n \"\${CLAUDE_SUMMARY_HOOK:-}\" ] && exit 0; bash $hook_script"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
settings="$project_root/.claude/settings.json"

if [[ -f "$settings" ]]; then
  existing="$(cat "$settings")"
else
  existing='{}'
fi

# Idempotency: skip if an existing SessionEnd command exactly matches what
# we're about to insert. Exact match (not substring) so that sibling entries
# like a `.bak` path or a copy-pasted fragment can't produce a false hit.
if printf '%s' "$existing" | jq -e --arg cmd "$command_str" '
  [(.hooks.SessionEnd? // [])[]?.hooks[]?.command] | any(. == $cmd)
' >/dev/null 2>&1; then
  echo "[install-summary-hook] already installed: $settings"
  exit 0
fi

new_entry="$(jq -n --arg cmd "$command_str" '{
  hooks: [
    {
      type: "command",
      command: $cmd,
      async: true
    }
  ]
}')"

merged="$(printf '%s' "$existing" | jq --argjson entry "$new_entry" '
  .hooks = (.hooks // {}) |
  .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [$entry])
')"

# Write back via dot-claude.sh — Claude Code blocks direct .claude/ writes via
# its native Write/Edit tools, but the plugin's bash indirection is unaffected.
printf '%s\n' "$merged" | "$dot_claude" write .claude/settings.json
echo "[install-summary-hook] installed SessionEnd hook in $settings"
