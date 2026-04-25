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
#
# Identity is normally read from `git var GIT_AUTHOR_IDENT` (the repo's
# user.email/user.name config, with git's login@hostname auto-derivation
# as the fallback). Override per-run with environment variables:
#   CLAIM_EMAIL=<email>   force the claim email
#   CLAIM_NAME=<name>     force the claim name (defaults to the local
#                         part of CLAIM_EMAIL if only the email is set)
# Useful when the local git config doesn't reflect the identity you want
# to claim under — fresh clones with no user.email set, scripted runs,
# scenarios where the env-var route is cleaner than mutating git config.

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

# Determine the identity to claim under. CLAIM_EMAIL / CLAIM_NAME env
# vars win over git's effective config; this lets the script work on a
# clone that has no user.email set, and lets a caller claim under an
# alternate identity per run without touching git config.
if [[ -n "${CLAIM_EMAIL:-}" ]]; then
    if [[ "$CLAIM_EMAIL" != *@* ]]; then
        echo "me.sh: CLAIM_EMAIL must contain '@' (got: $CLAIM_EMAIL)" >&2
        exit 64
    fi
    claim_email="$CLAIM_EMAIL"
    claim_name="${CLAIM_NAME:-${CLAIM_EMAIL%@*}}"
    # Set both author and committer identity for the rebase: --reset-author
    # inside the --exec body resets author = committer, so we need both
    # exported even when the caller only cares about author.
    export GIT_AUTHOR_NAME="$claim_name"
    export GIT_AUTHOR_EMAIL="$claim_email"
    export GIT_COMMITTER_NAME="$claim_name"
    export GIT_COMMITTER_EMAIL="$claim_email"
else
    # `git var GIT_AUTHOR_IDENT` prints "Name <email> ts tz".
    author_ident="$(git var GIT_AUTHOR_IDENT)"
    claim_email="${author_ident#*<}"
    claim_email="${claim_email%%>*}"
fi

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
