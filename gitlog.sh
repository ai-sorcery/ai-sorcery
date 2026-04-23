#!/usr/bin/env bash
#
# gitlog.sh — show recent commit messages with no pager.
# Usage: gitlog.sh [-<N> | <N>]   # default: 10 commits

set -euo pipefail

count="${1:--10}"
case "$count" in
  -*) ;;
  *) count="-$count" ;;
esac

git --no-pager log "$count"
