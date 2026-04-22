#!/usr/bin/env bash
#
# check-disallowed-terms — block commits that add lines containing any
# string listed in $repo_root/commit-disallowed-terms.txt.
#
# Runs as a pre-commit hook (or is called by one). Reads the terms file,
# strips comments and blank lines, then scans the ADDED lines of the
# staged diff for literal matches. Nothing outside the repository is
# referenced, so the hook works for any dev who activates it — no
# dependency on the sorcery plugin being installed.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
terms_file="$repo_root/commit-disallowed-terms.txt"

if [ ! -f "$terms_file" ]; then
    exit 0
fi

# Parse terms: strip comments and blank lines, trim leading/trailing whitespace.
# Terms are matched literally (fixed strings), so spaces and regex metacharacters
# are fine. A term of exactly '#' is not expressible — use a different string.
terms=()
while IFS= read -r raw || [ -n "$raw" ]; do
    trimmed="${raw#"${raw%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -z "$trimmed" ] && continue
    case "$trimmed" in \#*) continue ;; esac
    terms+=("$trimmed")
done < "$terms_file"

if [ "${#terms[@]}" -eq 0 ]; then
    exit 0
fi

# --no-renames makes a rename show up as add+delete, so a file that moves
# into the repo with a disallowed term is still scanned as added content.
diff_output="$(git diff --cached --no-color --unified=0 --no-renames --diff-filter=ACM)"

current_file=""
violations=0
while IFS= read -r line; do
    case "$line" in
        "+++ /dev/null")
            current_file=""
            ;;
        "+++ b/"*)
            current_file="${line#+++ b/}"
            ;;
        "+++"*)
            ;;
        "+"*)
            content="${line#+}"
            for term in "${terms[@]}"; do
                if printf '%s' "$content" | grep -q -F -e "$term"; then
                    printf "guarding-commits: disallowed term '%s' found in %s\n" \
                        "$term" "${current_file:-<unknown>}" >&2
                    violations=1
                fi
            done
            ;;
    esac
done <<< "$diff_output"

if [ "$violations" -ne 0 ]; then
    printf '\nguarding-commits: edit the offending files or update %s, then retry.\n' \
        "$terms_file" >&2
    exit 1
fi
exit 0
