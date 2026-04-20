#!/usr/bin/env bash
#
# me.sh — claim authorship on the last N commits.
#
# Rewrites the last `claim_count` commits on the current branch so their
# author field becomes the current git user. Useful for taking ownership
# of commits originally made by an AI agent or other tool. If the branch
# has fewer commits than `claim_count`, every commit on the branch is
# rewritten instead.

set -euo pipefail

# Number of commits back from HEAD to rewrite.
claim_count=5
target_ancestor="HEAD~$claim_count"

# HEAD~N is invalid when the branch has fewer than N ancestors, which
# makes a bare `git rebase HEAD~N` fail. Fall back to --root so the
# rebase still covers every commit.
if git rev-parse --verify "$target_ancestor" >/dev/null 2>&1; then
    upstream="$target_ancestor"
else
    upstream="--root"
fi

# --exec runs after each pick. --reset-author rewrites the author field
# to the current git user; --no-edit keeps the commit message as-is.
git rebase "$upstream" --exec "git commit --amend --reset-author --no-edit"
