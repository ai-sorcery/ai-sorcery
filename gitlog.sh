#!/usr/bin/env bash
#
# gitlog.sh — show the 10 most recent commit messages.

set -euo pipefail

git log -n 10
