#!/usr/bin/env bash
#
# me.sh — claim authorship on the last N commits.
#
# Rewrites the last `claim_count` commits on the current branch so their
# author field becomes the current git user, preserving each commit's
# original author date. Commits whose author email already matches the
# current user are left untouched, so re-running the script is a no-op
# on anything already attributed. If the branch has fewer commits than
# `claim_count`, every commit on the branch is considered.
#
# Usage: me.sh [-N]
#   -N: number of commits back from HEAD to consider (default: 5)

set -euo pipefail

# Number of commits back from HEAD to consider. Default 5; override with
# `-N` (e.g., `./me.sh -6` claims the last 6 commits).
claim_count=5
if [ $# -gt 1 ]; then
    echo "Usage: $(basename "$0") [-N]" >&2
    exit 64
fi
if [ $# -eq 1 ]; then
    if [[ "$1" =~ ^-[1-9][0-9]*$ ]]; then
        claim_count="${1#-}"
    else
        echo "Usage: $(basename "$0") [-N]" >&2
        echo "  N: number of commits back from HEAD (default: 5)" >&2
        exit 64
    fi
fi
target_ancestor="HEAD~$claim_count"

# HEAD~N is invalid when the branch has fewer than N ancestors, which
# makes a bare `git rebase HEAD~N` fail. Fall back to --root so the
# rebase still covers every commit.
if git rev-parse --verify "$target_ancestor" >/dev/null 2>&1; then
    upstream="$target_ancestor"
else
    upstream="--root"
fi

# Git's effective "who I am" — config if set, else auto-derived from
# login + hostname. `git var GIT_AUTHOR_IDENT` prints "Name <email> ts tz".
author_ident="$(git var GIT_AUTHOR_IDENT)"
claim_email="${author_ident#*<}"
claim_email="${claim_email%%>*}"

# Exported so the --exec subshell below can see it. Each --exec runs
# after its commit has been picked, with HEAD at that commit — so
# `git log -1` returns the commit currently under consideration.
export CLAIM_EMAIL="$claim_email"

# For commits not already under the current user, amend to reset the
# author identity while preserving the original author date so
# timestamps don't all collapse to "now". Commits already attributed
# to the current user skip the amend and pass through unchanged.
#
# The --exec body is one line because git rebase rejects newlines in
# exec commands; semicolons stand in for the if/then/fi separators.
git rebase "$upstream" --exec 'if [ "$(git log -1 --format=%ae)" != "$CLAIM_EMAIL" ]; then git commit --amend --reset-author --date="$(git log -1 --format=%aI)" --no-edit; fi'
