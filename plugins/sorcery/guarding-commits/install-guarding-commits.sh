#!/usr/bin/env bash
#
# install-guarding-commits.sh — install the guarding-commits pre-commit
# check into the repo whose working directory this is invoked from.
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

# --- wire into pre-commit --------------------------------------------------
hook="$hooks_dir/pre-commit"
marker="# guarding-commits-check"
invocation='./.githooks/check-disallowed-terms.sh || exit 1  '"$marker"

if [ ! -f "$hook" ]; then
    cat > "$hook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

./.githooks/check-disallowed-terms.sh || exit 1  # guarding-commits-check
EOF
    chmod +x "$hook"
    echo "install: created $hook"
elif grep -q -F -e "$marker" "$hook"; then
    echo "install: pre-commit already wired — no change"
else
    # Prepend the invocation after the shebang/set- prologue so it runs before
    # any later 'exec' replaces the shell. We insert after the first run of
    # consecutive shebang + `set` lines.
    tmp="$(mktemp)"
    awk -v inv="$invocation" '
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
fi

cat <<EOF

install: done.

Next steps:

  1. Edit $terms_file to add the strings you actually want to block.
  2. Teammates cloning this repo need to activate the hooks directory
     (core.hooksPath is per-clone local config — not inherited). Pick one:
       - add 'git config core.hooksPath $(git -C "$repo_root" config --local --get core.hooksPath)' to a CONTRIBUTING.md / README onboarding section, OR
       - commit a scripts/setup.sh that runs the above line and reference it
         in onboarding docs, OR
       - use ecosystem tooling that auto-activates (Husky / Lefthook via a
         package.json prepare script; pre-commit for Python projects).

  3. Test end-to-end: stage a line containing one of your terms and try to
     commit — the hook should refuse it.
EOF
