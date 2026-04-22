#!/usr/bin/env bash
#
# install-task-loop — scaffold the task-loop harness in the current repo.
# Drops task-loop.sh + prompt-task-loop.sh at the repo root, installs the
# wrap-up and sideload hooks into improvement/ (creating it if missing),
# and wires the hooks into .claude/settings.json via dot-claude.sh.
#
# The improvement/ directory is shared with the improvement-loop skill:
# running this installer without the improvement-loop scaffolded creates a
# minimal improvement/ just for the wrap-up marker files. Running both
# installers is safe — each is idempotent on its own paths.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "install-task-loop: jq is required (brew install jq)" >&2
    exit 1
fi

# bun is a runtime dependency of the loop (helpers.ts + render.ts used by
# the jq | bun pipeline in task-loop.sh). Fail install-time rather than at
# first iteration when the check is less obvious.
if ! command -v bun >/dev/null 2>&1; then
    echo "install-task-loop: bun is required (brew install oven-sh/bun/bun)" >&2
    exit 1
fi

plugin_loop_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$plugin_loop_dir/.." && pwd)"
dot_claude="$plugin_root/dot-claude.sh"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
improvement_dir="$project_root/improvement"

mkdir -p "$improvement_dir" "$project_root/data/task-loop-inbox" "$project_root/data/task-loop-logs"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  local label="$3"
  if [[ -e "$dst" ]]; then
    echo "  skip (exists): $label"
    return 1
  fi
  cp "$src" "$dst"
  case "$dst" in
    *.sh) chmod +x "$dst" ;;
  esac
  echo "  copy: $label"
  return 0
}

# Root-level scripts.
copy_if_missing "$plugin_loop_dir/task-loop.sh" "$project_root/task-loop.sh" "task-loop.sh" || true
copy_if_missing "$plugin_loop_dir/prompt-task-loop.sh" "$project_root/prompt-task-loop.sh" "prompt-task-loop.sh" || true

# Hooks inside improvement/. wrap-up-hook is shared with the improvement
# loop — skip if it's already there, don't clobber.
copy_if_missing "$plugin_loop_dir/wrap-up-hook.sh" "$improvement_dir/wrap-up-hook.sh" "improvement/wrap-up-hook.sh" || true

# Sideload hook — task-loop-specific, but placed alongside the wrap-up
# hook for consistency (both are PostToolUse scripts related to the loops).
copy_if_missing "$plugin_loop_dir/task-loop-sideload-hook.sh" \
  "$improvement_dir/task-loop-sideload-hook.sh" \
  "improvement/task-loop-sideload-hook.sh" || true

# Also need helpers.ts + stream.jq + render.ts because task-loop.sh
# pipes through them. If improvement-loop was already installed they're
# already here; copy only if missing.
for f in helpers.ts stream.jq render.ts; do
  copy_if_missing "$plugin_loop_dir/$f" "$improvement_dir/$f" "improvement/$f" || true
done

# Wire both hooks into .claude/settings.json PostToolUse (match "*").
settings="$project_root/.claude/settings.json"
wrapup_cmd="bash $improvement_dir/wrap-up-hook.sh"
sideload_cmd="bash $improvement_dir/task-loop-sideload-hook.sh"

if [[ -f "$settings" ]]; then
  existing="$(cat "$settings")"
else
  existing='{}'
fi

has_wrapup=0
has_sideload=0
if printf '%s' "$existing" | jq -e --arg cmd "$wrapup_cmd" '
  [(.hooks.PostToolUse? // [])[]?.hooks[]?.command] | any(. == $cmd)
' >/dev/null 2>&1; then
  has_wrapup=1
fi
if printf '%s' "$existing" | jq -e --arg cmd "$sideload_cmd" '
  [(.hooks.PostToolUse? // [])[]?.hooks[]?.command] | any(. == $cmd)
' >/dev/null 2>&1; then
  has_sideload=1
fi

if (( has_wrapup && has_sideload )); then
  echo "  hooks already present in $settings — leaving settings.json alone"
else
  # Build the list of new command objects we still need to add.
  new_commands='[]'
  if (( !has_wrapup )); then
    new_commands="$(jq --arg cmd "$wrapup_cmd" \
      '. + [{ type: "command", command: $cmd, timeout: 5000 }]' <<< "$new_commands")"
  fi
  if (( !has_sideload )); then
    new_commands="$(jq --arg cmd "$sideload_cmd" \
      '. + [{ type: "command", command: $cmd, timeout: 3000 }]' <<< "$new_commands")"
  fi

  # Prefer appending into an existing `matcher: "*"` group rather than
  # creating a parallel sibling — keeps settings.json idiomatic.
  merged="$(printf '%s' "$existing" | jq --argjson cmds "$new_commands" '
    .hooks = (.hooks // {}) |
    .hooks.PostToolUse = (.hooks.PostToolUse // []) |
    if any(.hooks.PostToolUse[]; .matcher == "*") then
      .hooks.PostToolUse = [
        .hooks.PostToolUse[] |
        if .matcher == "*"
          then .hooks = ((.hooks // []) + $cmds)
          else .
        end
      ]
    else
      .hooks.PostToolUse = .hooks.PostToolUse + [{ matcher: "*", hooks: $cmds }]
    end
  ')"

  printf '%s\n' "$merged" | "$dot_claude" write .claude/settings.json
  (( !has_wrapup )) && echo "  hook: wired wrap-up-hook.sh into $settings"
  (( !has_sideload )) && echo "  hook: wired task-loop-sideload-hook.sh into $settings"
fi

echo
echo "[install-task-loop] done."
echo "Next: ensure llm-tasks/ has pending tasks (use the using-llm-tasks skill)."
echo "Then: ./task-loop.sh   (prompt while running: ./prompt-task-loop.sh 'message')"
