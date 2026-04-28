#!/usr/bin/env bash
#
# install-guarding-commits.sh — install the guarding-commits check into
# the repo whose working directory this is invoked from.
#
# Idempotent. Safe to re-run to pick up an updated check-disallowed-terms.sh.
# Never overwrites an existing commit-disallowed-terms.txt.

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
    hooks_dir="$repo_root/.githooks"
    echo "install: set core.hooksPath to .githooks for this clone"
elif [ "$current_hooks_path" = ".githooks" ]; then
    hooks_dir="$repo_root/.githooks"
else
    hooks_dir="$repo_root/$current_hooks_path"
    echo "install: using existing core.hooksPath=$current_hooks_path"
fi

mkdir -p "$hooks_dir"

# --- copy the check script (self-contained; no paths outside the repo) -----
cp "$src_dir/check-disallowed-terms.sh" "$hooks_dir/check-disallowed-terms.sh"
chmod +x "$hooks_dir/check-disallowed-terms.sh"
echo "install: wrote $hooks_dir/check-disallowed-terms.sh"

# --- seed the terms file (preserve any existing list) ----------------------
terms_file="$repo_root/commit-disallowed-terms.txt"
if [ ! -f "$terms_file" ]; then
    cp "$src_dir/example-commit-disallowed-terms.txt" "$terms_file"
    echo "install: seeded $terms_file (edit to add real terms)"
else
    echo "install: left existing $terms_file in place"
fi

# --- gitignore the terms file ----------------------------------------------
gitignore="$repo_root/.gitignore"
ignore_line="commit-disallowed-terms.txt"
if [ ! -f "$gitignore" ] || ! grep -q -x -F -e "$ignore_line" "$gitignore"; then
    # Preserve trailing newline; add one if the file exists without it.
    if [ -f "$gitignore" ] && [ -n "$(tail -c1 "$gitignore" 2>/dev/null)" ]; then
        printf '\n' >> "$gitignore"
    fi
    printf '%s\n' "$ignore_line" >> "$gitignore"
    echo "install: added $ignore_line to .gitignore"
fi

# --- wire hooks -------------------------------------------------------------
# wire_hook <hook_name> <invocation>
# Creates a fresh hook with a shebang + `set` + the invocation if the file is
# absent; otherwise prepends the invocation (after the shebang and any leading
# `set` lines) guarded by a marker comment so repeated installs don't duplicate.
# Prepend (not append) because a trailing `exec` in the existing hook would
# otherwise short-circuit the check.
marker="# guarding-commits-check"
wire_hook() {
    local hook_name="$1"
    local invocation="$2"
    local hook="$hooks_dir/$hook_name"
    local full_invocation="$invocation  $marker"

    if [ ! -f "$hook" ]; then
        cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail

$full_invocation
EOF
        chmod +x "$hook"
        echo "install: created $hook"
        return
    fi

    if grep -q -F -e "$marker" "$hook"; then
        echo "install: $hook_name already wired — no change"
        return
    fi

    local tmp
    tmp="$(mktemp)"
    awk -v inv="$full_invocation" '
        BEGIN { inserted = 0; in_prologue = 1 }
        {
            if (in_prologue && (NR == 1 && $0 ~ /^#!/)) {
                print; next
            }
            if (in_prologue && $0 ~ /^[[:space:]]*set[[:space:]]/) {
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
    echo "install: prepended guarding-commits-check to existing $hook"
}

wire_hook "pre-commit" './.githooks/check-disallowed-terms.sh || exit 1'
wire_hook "commit-msg" './.githooks/check-disallowed-terms.sh --message "$1" || exit 1'

active_hooks_path="$(git -C "$repo_root" config --local --get core.hooksPath)"

# Heads-up if the next commit will fall back to the host-autodetected identity.
# Git's own warning ("Your name and email address were configured automatically
# based on your username and hostname") fires per-commit; this fires once at
# install time so the dev knows before they hit the first hooked commit.
if ! git -C "$repo_root" config user.email >/dev/null 2>&1; then
    cat >&2 <<'NUDGE'

install: heads-up — git user.email is not set in this clone or globally.
         The first commit you make will fall back to the host-autodetected
         identity, producing a noisy git warning and attributing the commit
         to a hostname-based stranger. Set it before committing:

             git config user.email "you@example.com"
             git config user.name  "Your Name"

NUDGE
fi

cat <<EOF

install: done.

Next steps:

  1. Edit $terms_file to add the strings you actually want to block.
  2. Bake the hooks activation into a script so fresh clones aren't silently
     unguarded (core.hooksPath is per-clone local config — not inherited).
     In rough order of preference:

       - JS/TS projects: add a 'prepare' script to package.json so it runs
         on every install:
           "prepare": "git config --get core.hooksPath >/dev/null 2>&1 || git config core.hooksPath ${active_hooks_path}"

       - Python projects: invoke 'pre-commit install' as part of project
         setup (pyproject.toml dev extras, requirements-dev.txt, etc.).

       - Anything else: commit a scripts/setup.sh that runs:
           git config core.hooksPath ${active_hooks_path}
         and reference it once from the README.

     A bare "after cloning, run ..." line in CONTRIBUTING is the last resort
     and tends to drift.

  3. Test end-to-end: stage a line containing one of your terms and try to
     commit — the pre-commit hook should refuse it. Also try a clean change
     with a disallowed term in the commit message — the commit-msg hook
     should refuse that too.
EOF
