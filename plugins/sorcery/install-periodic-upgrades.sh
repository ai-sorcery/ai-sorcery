#!/usr/bin/env bash
#
# install-periodic-upgrades.sh — install the dependency-staleness pre-commit
# check into the repo whose working directory this is invoked from.
#
# Idempotent. Safe to re-run to pick up an updated check-update-staleness.sh.

set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git rev-parse --show-toplevel)"

# --- core.hooksPath sanity --------------------------------------------------
# core.hooksPath is per-clone local config, not inherited on clone. If a repo
# already standardises on a hooks directory, we use it; otherwise we adopt
# .githooks (the repo-tracked convention) and set the config for this clone.
current_hooks_path="$(git -C "$repo_root" config --local --get core.hooksPath || true)"
if [ -z "$current_hooks_path" ]; then
    git -C "$repo_root" config --local core.hooksPath .githooks
    echo "install: set core.hooksPath to .githooks for this clone"
elif [ "$current_hooks_path" != ".githooks" ]; then
    echo "install: using existing core.hooksPath=$current_hooks_path"
fi
hooks_rel="$(git -C "$repo_root" config --local --get core.hooksPath)"
hooks_dir="$repo_root/$hooks_rel"

mkdir -p "$hooks_dir"

# --- copy the check (self-contained; no paths outside the repo) ------------
cp "$src_dir/check-update-staleness.sh" "$hooks_dir/check-update-staleness.sh"
chmod +x "$hooks_dir/check-update-staleness.sh"
echo "install: wrote $hooks_dir/check-update-staleness.sh"

# --- wire pre-commit --------------------------------------------------------
# Creates a fresh hook with a shebang + `set` + the invocation if absent;
# otherwise prepends the invocation guarded by a marker comment so repeated
# installs don't duplicate. Prepend (not append) because a trailing `exec`
# in the existing hook would otherwise short-circuit the check. The
# invocation path is derived from the active core.hooksPath rather than
# hardcoded — repos using a non-default hooks directory (e.g. husky) still
# get a working hook line.
marker="# periodic-upgrades-check"
invocation="./${hooks_rel}/check-update-staleness.sh || exit 1"
full_invocation="$invocation  $marker"
hook="$hooks_dir/pre-commit"

if [ ! -f "$hook" ]; then
    cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail

$full_invocation
EOF
    chmod +x "$hook"
    echo "install: created $hook"
elif grep -q -F -e "$marker" "$hook"; then
    echo "install: pre-commit already wired — no change"
else
    tmp="$(mktemp)"
    awk -v inv="$full_invocation" '
        BEGIN { inserted = 0; in_prologue = 1; saw_set = 0 }
        {
            # Treat the leading run as prologue: shebang, then any mix of
            # license/description comments and blank lines, then any set
            # lines. Once a set line has been seen, subsequent comment lines
            # are body content (e.g. a doc-comment above the function the
            # comment documents), and our injection lands before them.
            if (in_prologue && NR == 1 && $0 ~ /^#!/) {
                print; next
            }
            if (in_prologue && $0 ~ /^[[:space:]]*$/) {
                print; next
            }
            if (in_prologue && !saw_set && $0 ~ /^[[:space:]]*#/) {
                print; next
            }
            if (in_prologue && $0 ~ /^[[:space:]]*set[[:space:]]/) {
                saw_set = 1
                print; next
            }
            if (in_prologue && !inserted) {
                # First non-prologue line — insert our call just before it,
                # preceded by a blank line if the previous line had content.
                print ""
                print inv
                print ""
                inserted = 1
                in_prologue = 0
            }
            print
        }
        END {
            if (!inserted) {
                print ""
                print inv
            }
        }
    ' "$hook" > "$tmp"
    chmod --reference="$hook" "$tmp" 2>/dev/null || chmod +x "$tmp"
    mv "$tmp" "$hook"
    echo "install: prepended periodic-upgrades-check to existing $hook"
fi

cat <<EOF

install: done.

Next steps:

  1. Bake the hooks activation into a script so fresh clones aren't silently
     unguarded (core.hooksPath is per-clone local config — not inherited).
     In rough order of preference:

       - JS/TS projects: add a 'prepare' script to package.json so it runs
         on every install:
           "prepare": "git config --get core.hooksPath >/dev/null 2>&1 || git config core.hooksPath ${hooks_rel}"

       - Python projects: invoke 'pre-commit install' as part of project
         setup (pyproject.toml dev extras, requirements-dev.txt, etc.).

       - Anything else: commit a scripts/setup.sh that runs:
           git config core.hooksPath ${hooks_rel}
         and reference it once from the README.

     A bare "after cloning, run ..." line in CONTRIBUTING is the last resort
     and tends to drift.

  2. Verify end-to-end. Backdate a lockfile and try to commit:

       touch -t "\$(date -v-30d +%Y%m%d%H%M)" bun.lock 2>/dev/null \\
         || touch -d "30 days ago" bun.lock
       git commit --allow-empty -m "test: prove the staleness hook fires"

     The commit must reject. Then either run the package manager's update
     command, or 'touch <lockfile>' to mark fresh, and re-commit — it should
     accept. Direct invocation of the script doesn't catch activation-path,
     execute-bit, or wrong-directory mistakes that only surface under the
     real trigger.

  3. The default threshold is 7 days. Override per-commit with
     'STALE_DAYS=14 git commit ...', or set it permanently by exporting
     STALE_DAYS from a setup script.
EOF
