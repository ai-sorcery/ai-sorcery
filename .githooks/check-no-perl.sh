#!/usr/bin/env bash
# check-no-perl.sh — block Perl in staged changes.
#
# Per AGENTS.md axiom 3: Perl ships with stock macOS, but adding another
# language to the mix is noise — one more runtime, one more set of
# conventions and error modes. Use Bun TypeScript instead (which ships its
# own HTMLRewriter and a real JS engine, and is already a dependency
# elsewhere in this repo).
#
# Detects:
#   - any staged file with a .pl or .pm extension
#   - any staged file with a Perl shebang on the first line
#   - any perl token in a staged .sh / .bash / .zsh file
#
# Documentation files (e.g., AGENTS.md) are not flagged: the body check
# is restricted to shell scripts. This script exempts itself from the
# .sh body check (it naturally contains the patterns it's looking for).

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

staged=$(git diff --cached --name-only --diff-filter=AM)
[ -z "$staged" ] && exit 0

self_path=".githooks/check-no-perl.sh"
violations=()

while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    *.pl|*.pm)
      violations+=("$path: Perl source file (use Bun TypeScript instead)")
      continue
      ;;
  esac
  [ -f "$path" ] || continue
  if head -n1 "$path" 2>/dev/null | grep -qE '^#!.*\bperl\b'; then
    violations+=("$path:1: Perl shebang (use Bun TypeScript instead)")
  fi
  case "$path" in
    *.sh|*.bash|*.zsh)
      [ "$path" = "$self_path" ] && continue
      while IFS= read -r hit; do
        violations+=("$path:$hit")
      done < <(grep -nE '\bperl\b' "$path" 2>/dev/null || true)
      ;;
  esac
done <<< "$staged"

if [ "${#violations[@]}" -gt 0 ]; then
  echo "check-no-perl: ${#violations[@]} Perl reference(s) in staged changes:" >&2
  for v in "${violations[@]}"; do
    echo "  $v" >&2
  done
  echo "" >&2
  echo "Per AGENTS.md axiom 3, use Bun TypeScript instead of Perl." >&2
  exit 1
fi
exit 0
