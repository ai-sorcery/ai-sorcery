#!/usr/bin/env bash
# conventional-commit-check — validate a commit message against the
# conventional-commits spec. Intended for use from a git `commit-msg`
# hook, but runs fine from the command line for debugging.
#
# Usage:
#   conventional-commit-check.sh <commit-msg-file>
#
# Rules enforced:
#   - Subject matches `type(scope): subject` (scope optional).
#   - If a body is present, the second line must be blank.
#   - Merge / revert / fixup! / squash! subjects get a pass because git
#     auto-generates them.
#
# Configure the accepted type list via the CONVENTIONAL_TYPES env var
# (comma-separated). Default is a superset of the common conventional
# types so the script is useful out of the box.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: conventional-commit-check.sh <commit-msg-file>" >&2
  exit 64
fi

commit_msg_file="$1"
if [[ ! -r "$commit_msg_file" ]]; then
  echo "conventional-commit-check: not readable: $commit_msg_file" >&2
  exit 66
fi

# Strip git's instructional comment lines ("# Please enter the commit
# message...") and trailing whitespace so inspection sees the real message.
msg="$(git stripspace --strip-comments <"$commit_msg_file")"
first_line="$(printf '%s\n' "$msg" | head -n 1)"

# Auto-generated subjects from merge / revert / fixup / squash don't
# follow the conventional format — let them through.
if [[ "$first_line" =~ ^(Merge|Revert|fixup!|squash!) ]]; then
  exit 0
fi

types="${CONVENTIONAL_TYPES:-feat,fix,refactor,docs,chore,test,perf,build,ci,style}"
# Convert the comma-separated list into a regex alternation.
alt="$(printf '%s' "$types" | tr ',' '|' | tr -d '[:space:]')"
subject_pattern="^(${alt})(\([a-z0-9-]+\))?: .+"

if ! [[ "$first_line" =~ $subject_pattern ]]; then
  cat >&2 <<EOF
Error: commit subject does not follow conventional commits.

  Expected: type(scope): subject   (scope optional)
  Types:    $(printf '%s' "$types" | tr ',' ' ')
  Got:      $first_line
EOF
  exit 1
fi

# When a body is present, line 2 must be blank so the subject is clearly
# separated. sed -n '2p' prints line 2 or nothing for a single-line
# message; either way the check is correct.
second_line="$(printf '%s\n' "$msg" | sed -n '2p')"
if [[ -n "$second_line" ]]; then
  echo "Error: separate commit body from subject with a blank line." >&2
  exit 1
fi
