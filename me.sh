#!/usr/bin/env bash
set -euo pipefail

git rebase HEAD~5 --exec "git commit --amend --reset-author --no-edit"
