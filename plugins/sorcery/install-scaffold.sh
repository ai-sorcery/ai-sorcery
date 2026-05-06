#!/usr/bin/env bash
#
# install-scaffold.sh — scaffold the current repo with the sorcery day-one
# essentials in one shot. Calls each sibling installer in a sensible order;
# every step is idempotent, so re-runs only fill in what's missing.
#
# Bundle (commit-time guards first so a mid-bundle failure still leaves the
# repo with the most load-bearing protection — the user is likely to run
# `git commit` shortly after scaffolding):
#   1. conventional-commits     (guarding-commits)
#   2. commit-message style     (writing-commit-messages)
#   3. disallowed-terms guard   (guarding-commits)
#   4. periodic-upgrades hook   (enforcing-periodic-upgrades)
#   5. ./claude.sh              (launching-claude)
#   6. ./me.sh                  (claiming-authorship)
#   7. session summaries        (summarizing-sessions)
#
# Anything outside this bundle (LLM tasks workflow, improvement loop, VM,
# learning tracks, fixture capture) is opt-in via its own skill and not
# included here — the scaffold is the universal baseline, not the kitchen
# sink.

set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "install-scaffold: not inside a git repository — run 'git init' first" >&2
    exit 1
fi

cd "$repo_root"

# Pre-flight dependency check. Sub-installers fail fast on their own, but a
# mid-bundle failure would leave a half-applied state (e.g., commit guards
# wired but the SessionEnd hook never reached). Catch missing tools up front
# so the wrapper's "one shot, idempotent" promise holds even on first run.
missing=()
command -v jq  >/dev/null 2>&1 || missing+=(jq)
command -v bun >/dev/null 2>&1 || missing+=(bun)
if (( ${#missing[@]} > 0 )); then
    echo "install-scaffold: missing required tool(s): ${missing[*]}" >&2
    echo "install-scaffold: install them first (e.g. 'brew install ${missing[*]}')." >&2
    echo "install-scaffold: aborting before any sub-installer runs." >&2
    exit 1
fi

step() {
    printf '\n=== %s ===\n' "$1"
}

# --- 1. conventional-commits guard (guarding-commits) ----------------------
step "guarding-commits / conventional-commits"
"$plugin_dir/guarding-commits/install-conventional-commits.sh"

# --- 2. commit-message style (writing-commit-messages) ---------------------
step "writing-commit-messages"
"$plugin_dir/install-commit-style-hook.sh"

# --- 3. disallowed-terms guard (guarding-commits) --------------------------
step "guarding-commits / disallowed-terms"
"$plugin_dir/guarding-commits/install-guarding-commits.sh"

# --- 4. periodic-upgrades (enforcing-periodic-upgrades) --------------------
step "enforcing-periodic-upgrades"
"$plugin_dir/install-periodic-upgrades.sh"

# --- 5. ./claude.sh (launching-claude) -------------------------------------
step "launching-claude"
if [[ -e ./claude.sh ]]; then
    echo "install-scaffold: ./claude.sh already exists — skipping"
else
    "$plugin_dir/install-launcher.sh"
fi

# --- 6. ./me.sh (claiming-authorship) --------------------------------------
step "claiming-authorship"
if [[ -e ./me.sh ]]; then
    echo "install-scaffold: ./me.sh already exists — skipping"
else
    cp "$plugin_dir/me.sh" ./me.sh
    chmod +x ./me.sh
    echo "install-scaffold: installed ./me.sh"
fi

# --- 7. session summaries (summarizing-sessions) ---------------------------
step "summarizing-sessions"
"$plugin_dir/install-summary-hook.sh"

cat <<'EOF'

=== install-scaffold: done ===

Installed (or already present):
  - ./claude.sh             — launch Claude Code with privacy-friendly defaults
  - ./me.sh                 — re-author recent commits to the current git user
  - .githooks/commit-msg    — conventional-commits + style + disallowed-terms
  - .githooks/pre-commit    — disallowed-terms diff scan + lockfile staleness
  - .claude/settings.json   — SessionEnd summary hook

Next steps:

  1. Activate hooks for teammates. core.hooksPath is per-clone — bake the
     activation into the project's setup flow so a fresh clone isn't a silent
     trap. The 'guarding-commits' skill documents the choices in detail.

  2. Edit commit-disallowed-terms.txt at the repo root. It's git-ignored, so
     each contributor keeps their own list. The sibling tracked file
     disallowed-commit-messages.txt (read by the writing-commit-messages
     hook) lets you forbid generic commit subjects shared across the team —
     create it if you want that policy.

  3. Invoke 'following-best-practices' to scan for any remaining day-one gaps
     beyond what this bundle installs (README, starter scripts, observability,
     persisted test output, committed progress state, structured task workflow,
     wall-clock test ceiling, automated version bumps).
EOF
