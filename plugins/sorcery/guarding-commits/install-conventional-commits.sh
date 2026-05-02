#!/usr/bin/env bash
#
# install-conventional-commits.sh — install the conventional-commits
# subject validator into the repo whose working directory this is invoked from.
#
# Idempotent. Safe to re-run to pick up an updated conventional-commit-check.sh.

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

# --- copy the validator (self-contained; no paths outside the repo) --------
cp "$src_dir/conventional-commit-check.sh" "$hooks_dir/conventional-commit-check.sh"
chmod +x "$hooks_dir/conventional-commit-check.sh"
echo "install: wrote $hooks_dir/conventional-commit-check.sh"

# --- wire commit-msg --------------------------------------------------------
# Creates a fresh hook with a shebang + `set` + the invocation if absent;
# otherwise prepends the invocation guarded by a marker comment so repeated
# installs don't duplicate. Prepend (not append) because a trailing `exec`
# in the existing hook would otherwise short-circuit the check.
marker="# conventional-commit-check"
invocation="./${hooks_rel}/conventional-commit-check.sh \"\$1\" || exit 1"
full_invocation="$invocation  $marker"
hook="$hooks_dir/commit-msg"

if [ ! -f "$hook" ]; then
    cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail

$full_invocation
EOF
    chmod +x "$hook"
    echo "install: created $hook"
elif grep -q -F -e "$marker" "$hook"; then
    echo "install: commit-msg already wired — no change"
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
    echo "install: prepended conventional-commit-check to existing $hook"
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

  2. Verify end-to-end. Stage a trivial change, then:
       git commit -m "bogus"           # must reject
       git commit -m "chore: verify"   # must accept
     Invoking the script directly on a crafted message file isn't sufficient
     — it misses activation-path, execute-bit, and wrong-directory mistakes.

  3. Optionally tighten the accepted type list with the CONVENTIONAL_TYPES
     env var (comma-separated). Default:
       feat,fix,refactor,docs,chore,test,perf,build,ci,style
     Only narrow the list when the project's release tooling actually keys
     off specific types — false rejects condition devs to --no-verify.
EOF
