#!/usr/bin/env bash
# check-no-python.sh — block Python in staged changes.
#
# Per AGENTS.md axiom 3: this repo's scripts target macOS guests inside
# Tart VMs, where /usr/bin/python3 sits behind the Command Line Tools
# install — first invocation can prompt to install CLT, breaking the
# "vm-setup.sh is idempotent" contract. Use JXA (osascript -l JavaScript)
# instead, which ships in /usr/bin/osascript on every macOS install.
#
# Detects:
#   - any staged file with a .py extension
#   - any staged file with a Python shebang on the first line
#   - any python / python3 token in a staged .sh / .bash / .zsh file
#
# Documentation files (e.g., AGENTS.md) are not flagged: the body check
# is restricted to shell scripts. This script exempts itself from the
# .sh body check (it naturally contains the patterns it's looking for).

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

staged=$(git diff --cached --name-only --diff-filter=AM)
[ -z "$staged" ] && exit 0

self_path=".githooks/check-no-python.sh"
violations=()

while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    *.py)
      violations+=("$path: .py file (use JXA via osascript -l JavaScript)")
      continue
      ;;
  esac
  [ -f "$path" ] || continue
  if head -n1 "$path" 2>/dev/null | grep -qE '^#!.*\bpython[0-9.]*\b'; then
    violations+=("$path:1: Python shebang (use JXA via osascript -l JavaScript)")
  fi
  case "$path" in
    *.sh|*.bash|*.zsh)
      [ "$path" = "$self_path" ] && continue
      while IFS= read -r hit; do
        violations+=("$path:$hit")
      done < <(grep -nE '\bpython[0-9]*\b' "$path" 2>/dev/null || true)
      ;;
  esac
done <<< "$staged"

if [ "${#violations[@]}" -gt 0 ]; then
  echo "check-no-python: ${#violations[@]} Python reference(s) in staged changes:" >&2
  for v in "${violations[@]}"; do
    echo "  $v" >&2
  done
  echo "" >&2
  echo "Per AGENTS.md axiom 3, use JXA (osascript -l JavaScript) instead of Python." >&2
  exit 1
fi
exit 0
