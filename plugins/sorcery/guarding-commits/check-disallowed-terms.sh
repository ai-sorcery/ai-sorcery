#!/usr/bin/env bash
#
# check-disallowed-terms — block commits whose staged diff or commit message
# contains any string listed in $repo_root/commit-disallowed-terms.txt.
#
# Usage:
#   check-disallowed-terms.sh                # scan staged diff (pre-commit mode)
#   check-disallowed-terms.sh --message FILE # scan commit message (commit-msg mode)
#
# Reads the terms file, strips comments and blank lines, then scans either the
# ADDED lines of the staged diff or the non-comment lines of the given message
# file for literal, case-insensitive matches. Nothing outside the repository is
# referenced, so the hook works for any dev who activates it — no dependency
# on the sorcery plugin being installed.

set -euo pipefail

mode="diff"
message_file=""
case "${1:-}" in
    --message)
        mode="message"
        message_file="${2:-}"
        if [ -z "$message_file" ]; then
            echo "check-disallowed-terms: --message requires a file path" >&2
            exit 2
        fi
        ;;
    "") ;;
    *)
        echo "check-disallowed-terms: unknown argument '$1'" >&2
        echo "usage: $0 [--message <file>]" >&2
        exit 2
        ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
terms_file="$repo_root/commit-disallowed-terms.txt"

if [ ! -f "$terms_file" ]; then
    exit 0
fi

# Parse terms: strip comments and blank lines, trim leading/trailing whitespace.
# Terms are matched literally (fixed strings) and case-insensitively, so spaces
# and regex metacharacters are fine and a casing slip won't let a term through.
# A term of exactly '#' is not expressible — use a different string.
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

violations=0
check_line() {
    local content="$1"
    local location="$2"
    local term
    for term in "${terms[@]}"; do
        if printf '%s' "$content" | grep -q -F -i -e "$term"; then
            printf "guarding-commits: disallowed term '%s' found in %s\n" \
                "$term" "$location" >&2
            violations=1
        fi
    done
}

if [ "$mode" = "message" ]; then
    # git stripspace drops comment lines (git's own '#'-prefixed lines that
    # won't land in the final message) so we only check content that ships.
    stripped="$(git stripspace --strip-comments < "$message_file")"
    while IFS= read -r line || [ -n "$line" ]; do
        check_line "$line" "commit message"
    done <<< "$stripped"

    if [ "$violations" -ne 0 ]; then
        printf '\nguarding-commits: edit the commit message or update %s, then retry.\n' \
            "$terms_file" >&2
        exit 1
    fi
    exit 0
fi

# diff mode: --no-renames makes a rename show up as add+delete, so a file
# moving into the repo with a disallowed term is still scanned as added
# content.
diff_output="$(git diff --cached --no-color --unified=0 --no-renames --diff-filter=ACM)"

current_file=""
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
            check_line "${line#+}" "${current_file:-<unknown>}"
            ;;
    esac
done <<< "$diff_output"

if [ "$violations" -ne 0 ]; then
    printf '\nguarding-commits: edit the offending files or update %s, then retry.\n' \
        "$terms_file" >&2
    exit 1
fi
exit 0
