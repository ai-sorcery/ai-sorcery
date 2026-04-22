#!/usr/bin/env bash
#
# install-improvement-loop — scaffold the improvement loop in the current
# repo. Copies the plugin's canonical loop scripts into ./improvement/,
# seeds empty changelogs, and wires the wrap-up hook into
# .claude/settings.json via dot-claude.sh.
#
# Idempotent: re-running skips files that are already in place and leaves
# the settings.json alone if the hook entry is already present.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "install-improvement-loop: jq is required (brew install jq)" >&2
    exit 1
fi

# bun is a runtime dependency of the loop (helpers.ts + render.ts). Fail
# install-time rather than at first iteration when the check is less obvious.
if ! command -v bun >/dev/null 2>&1; then
    echo "install-improvement-loop: bun is required (brew install oven-sh/bun/bun)" >&2
    exit 1
fi

plugin_loop_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$plugin_loop_dir/.." && pwd)"
dot_claude="$plugin_root/dot-claude.sh"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
improvement_dir="$project_root/improvement"

mkdir -p "$improvement_dir"

# Canonical scripts + data files to copy. The key is the source file in the
# plugin; the value is the destination filename inside improvement/.
declare -a files=(
  "loop.sh"
  "start.sh"
  "finish.sh"
  "progress.sh"
  "timestamp.sh"
  "time-check.sh"
  "wrap-up-hook.sh"
  "helpers.ts"
  "stream.jq"
  "render.ts"
  "LOOP.md"
  "default-personas.json:personas.json"
)

copied=0
skipped=0
for entry in "${files[@]}"; do
  src_name="${entry%%:*}"
  dst_name="${entry##*:}"
  [[ "$dst_name" == "$src_name" ]] || true
  if [[ "$entry" != *":"* ]]; then
    dst_name="$src_name"
  fi

  src="$plugin_loop_dir/$src_name"
  dst="$improvement_dir/$dst_name"

  if [[ -e "$dst" ]]; then
    echo "  skip (exists): improvement/$dst_name"
    skipped=$(( skipped + 1 ))
    continue
  fi

  cp "$src" "$dst"
  # Preserve executable bit on shell scripts.
  case "$dst_name" in
    *.sh) chmod +x "$dst" ;;
  esac
  echo "  copy: improvement/$dst_name"
  copied=$(( copied + 1 ))
done

# Seed empty changelogs with the marker the helper inserts after.
succinct="$improvement_dir/SUCCINCT-CHANGELOG.md"
if [[ ! -e "$succinct" ]]; then
  cat > "$succinct" <<'EOF'
# Succinct Changelog

One-line entries per iteration. Newest at the bottom. Auto-written by
improvement/finish.sh — do not edit by hand.

| Iter | Persona | Started | Duration | Summary |
|------|---------|---------|----------|---------|
EOF
  echo "  seed: improvement/SUCCINCT-CHANGELOG.md"
  copied=$(( copied + 1 ))
fi

verbose="$improvement_dir/VERBOSE-CHANGELOG.md"
if [[ ! -e "$verbose" ]]; then
  cat > "$verbose" <<'EOF'
# Verbose Changelog

Detailed per-iteration entries. Auto-written by improvement/finish.sh — do
not edit by hand.

<!-- New entries go here, most recent first -->
EOF
  echo "  seed: improvement/VERBOSE-CHANGELOG.md"
  copied=$(( copied + 1 ))
fi

# Wire the wrap-up hook into .claude/settings.json (PostToolUse, match "*").
# The hook path is the installed copy (improvement/wrap-up-hook.sh), not the
# plugin's — so the hook keeps working even if the plugin is uninstalled.
hook_script="$improvement_dir/wrap-up-hook.sh"
hook_cmd="bash $hook_script"
settings="$project_root/.claude/settings.json"

if [[ -f "$settings" ]]; then
  existing="$(cat "$settings")"
else
  existing='{}'
fi

already_installed=0
if printf '%s' "$existing" | jq -e --arg cmd "$hook_cmd" '
  [(.hooks.PostToolUse? // [])[]?.hooks[]?.command] | any(. == $cmd)
' >/dev/null 2>&1; then
  already_installed=1
fi

if (( already_installed )); then
  echo "  hook already present in $settings — leaving settings.json alone"
else
  # Prefer appending into an existing `matcher: "*"` group rather than
  # creating a parallel sibling — keeps settings.json idiomatic.
  new_cmd="$(jq -n --arg cmd "$hook_cmd" \
    '{ type: "command", command: $cmd, timeout: 5000 }')"

  merged="$(printf '%s' "$existing" | jq --argjson cmd "$new_cmd" '
    .hooks = (.hooks // {}) |
    .hooks.PostToolUse = (.hooks.PostToolUse // []) |
    if any(.hooks.PostToolUse[]; .matcher == "*") then
      .hooks.PostToolUse = [
        .hooks.PostToolUse[] |
        if .matcher == "*"
          then .hooks = ((.hooks // []) + [$cmd])
          else .
        end
      ]
    else
      .hooks.PostToolUse = .hooks.PostToolUse + [{ matcher: "*", hooks: [$cmd] }]
    end
  ')"

  printf '%s\n' "$merged" | "$dot_claude" write .claude/settings.json
  echo "  hook: wired wrap-up-hook.sh into $settings"
fi

echo
echo "[install-improvement-loop] done — $copied file(s) copied/seeded, $skipped already present."
echo "Next: review improvement/personas.json (and tune for this repo), then run ./improvement/loop.sh."
