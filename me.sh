#!/usr/bin/env bash
set -euo pipefail

if git rev-parse --verify HEAD~5 >/dev/null 2>&1; then
    upstream="HEAD~5"
else
    upstream="--root"
fi

git rebase "$upstream" --exec "git commit --amend --reset-author --no-edit"
