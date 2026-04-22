#!/usr/bin/env bash
# write-llm-summary — save a markdown summary to ~/LLM_Summaries/YYYY-MM-DD/.
#
# Usage:
#   printf '%s\n' "$body" | write-llm-summary.sh "Short Title"
#
# Output path: "$HOME/LLM_Summaries/YYYY-MM-DD/YYYY-MM-DD@HH-MMAM Short Title.md"
# (local time, AM/PM uppercase). The full date prefix is kept inside the
# filename as well so each file stays self-identifying if moved out of its
# parent folder. Titles longer than 80 chars are truncated (filesystems cap at
# 255 bytes; the timestamp, extension, and dedup suffix eat ~25 bytes combined,
# leaving comfortable headroom).

set -euo pipefail

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 \"Short Title\"" >&2
  echo "Reads markdown content from stdin." >&2
  exit 1
fi

title="$1"
dir="$HOME/LLM_Summaries"

# Strip filesystem-hostile characters, flatten whitespace (incl. embedded newlines).
safe_title="$(printf '%s' "$title" | tr -d ':/\\?*<>|"' | tr '\n\r\t' '   ' | tr -s ' ')"
safe_title="${safe_title# }"
safe_title="${safe_title% }"

if [ -z "$safe_title" ]; then
  echo "Error: title was empty after sanitisation." >&2
  exit 1
fi

if [ "${#safe_title}" -gt 80 ]; then
  safe_title="${safe_title:0:77}..."
fi

# macOS `date`: %I = 01-12 hour, %M = minute, %p = AM/PM (uppercase matches spec).
# Derive date_subdir from stamp (same string) so a midnight-crossing run
# can't put a 2026-04-18 file under 2026-04-17/ (or vice versa).
stamp="$(date +"%Y-%m-%d@%I-%M%p")"
date_subdir="${stamp%%@*}"

target_dir="${dir}/${date_subdir}"
mkdir -p "$target_dir"

filename="${stamp} ${safe_title}.md"
path="${target_dir}/${filename}"

# Refuse to clobber an existing summary (two summaries in the same minute with the same title).
if [ -e "$path" ]; then
  suffix=2
  while [ -e "${target_dir}/${stamp} ${safe_title} (${suffix}).md" ]; do
    suffix=$((suffix + 1))
  done
  path="${target_dir}/${stamp} ${safe_title} (${suffix}).md"
fi

cat > "$path"

# Reject empty summaries so we don't silently pile up zero-byte files.
if [ ! -s "$path" ]; then
  rm -f "$path"
  echo "Error: no content on stdin; nothing written." >&2
  exit 1
fi

echo "Saved: $path"
