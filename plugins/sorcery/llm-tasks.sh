#!/usr/bin/env bash
# llm-tasks — manage a repo's `llm-tasks/` directory (list / new / done / clump).
#
# Usage:
#   llm-tasks.sh list                    # print pending task paths (not DONE-, not IGNORE-)
#   llm-tasks.sh new <name>              # create llm-tasks/<name>.md; stdin = body (optional)
#   llm-tasks.sh done <name>             # rename llm-tasks/<name>.md -> DONE-<name>.md
#   llm-tasks.sh clump                   # archive DONE-*.md into llm-tasks/completed/batch-N/
#
# Content for `new` comes in over stdin — avoids shell-escaping headaches with
# backticks, $vars, quotes, etc. Default template is used when stdin is a tty.
#
#   cat <<'EOF' | llm-tasks.sh new install-observability
#   # Install observability stack
#   ...
#   EOF
#
# Paths: `llm-tasks/` lives at the git toplevel (or $PWD outside a repo).
# Batch numbers: auto-assigned. All pending tasks share the currently-open
# batch; a new batch opens only after the previous one is fully clumped.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASKS_DIR="$PROJECT_ROOT/llm-tasks"
COMPLETED_DIR="$TASKS_DIR/completed"

die() { echo "[llm-tasks] $*" >&2; exit 1; }

# Highest batch number found among `llm-tasks/completed/batch-*/` directories.
# Prints 0 if no completed batches exist yet.
max_completed_batch() {
  local max=0
  if [[ -d "$COMPLETED_DIR" ]]; then
    for d in "$COMPLETED_DIR"/batch-*/; do
      [[ -d "$d" ]] || continue
      local n="${d%/}"
      n="${n##*batch-}"
      if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then
        max=$n
      fi
    done
  fi
  echo "$max"
}

# Highest `batch: N` value among .md files currently in `llm-tasks/` root
# (pending + DONE-, ignoring IGNORE-). Prints 0 if none.
max_local_batch() {
  local max=0
  [[ -d "$TASKS_DIR" ]] || { echo 0; return; }
  # Preserve the caller's nullglob setting so we don't leak state.
  local prev_nullglob
  prev_nullglob="$(shopt -p nullglob)"
  shopt -s nullglob
  for f in "$TASKS_DIR"/*.md; do
    local base
    base="$(basename "$f")"
    [[ "$base" == IGNORE-* ]] && continue
    local b
    b="$(grep '^batch:' "$f" | head -1 | sed 's/^batch:[[:space:]]*//' | tr -d '[:space:]' || true)"
    if [[ "$b" =~ ^[0-9]+$ ]] && (( b > max )); then
      max=$b
    fi
  done
  eval "$prev_nullglob"
  echo "$max"
}

# Batch number to stamp on a newly-created task. Stays at the open batch until
# all tasks from it are clumped; then advances to max_completed + 1.
current_batch() {
  local local_max completed_max
  local_max="$(max_local_batch)"
  if (( local_max > 0 )); then
    echo "$local_max"
    return
  fi
  completed_max="$(max_completed_batch)"
  echo $((completed_max + 1))
}

# Kept in sync with the "four-section lifecycle" in
# skills/using-llm-tasks/SKILL.md — the skill is the source of truth.
default_template() {
  cat <<'TEMPLATE'
# <task title>

## Initial Understanding

<Your interpretation of what needs to change and why — written *before* reading code.>

## Tentative Plan

<After investigating, the specific files / functions / approach.>

## Implementation

<What you actually did. Update if the approach changes.>

## Completion Notes

<Before/after comparison. Logs that helped. Logging added. Anything future-you would want to know.>
TEMPLATE
}

cmd="${1:-}"
[[ -n "$cmd" ]] || die "usage: llm-tasks.sh <list|new|done|clump> [args]"
shift || true

case "$cmd" in
  list)
    [[ -d "$TASKS_DIR" ]] || die "no llm-tasks/ directory at $PROJECT_ROOT"
    # Pending = .md files directly in llm-tasks/ that are not DONE- or IGNORE-.
    # Output: `<relative-path> (batch N)` — relative to cwd so an agent can
    # hand the path straight back to Read/Edit tools.
    # Normalize cwd to its physical path so tmpdir-style symlinks on macOS
    # (`/tmp` → `/private/tmp`) don't defeat the prefix strip below.
    cwd_phys="$(pwd -P)"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      b="$(grep '^batch:' "$f" | head -1 | sed 's/^batch:[[:space:]]*//' | tr -d '[:space:]' || true)"
      [[ -n "$b" ]] || b="?"
      rel="${f#"$cwd_phys"/}"
      printf '%s (batch %s)\n' "$rel" "$b"
    done < <(
      find "$TASKS_DIR" -maxdepth 1 -type f -name '*.md' \
        ! -name 'DONE-*' ! -name 'IGNORE-*' \
        -print | sort
    )
    ;;

  new)
    name="${1:-}"
    [[ -n "$name" ]] || die "usage: llm-tasks.sh new <name>"
    name="${name%.md}"
    mkdir -p "$TASKS_DIR"
    file="$TASKS_DIR/$name.md"
    [[ -e "$file" ]] && die "exists: $file"
    n="$(current_batch)"
    {
      printf 'batch: %d\n\n' "$n"
      if [[ -t 0 ]]; then
        default_template
      else
        # Read stdin once; if empty (e.g., invoked from a no-tty agent without
        # a piped body), fall back to the template instead of an empty file.
        # The `; printf X` / `${body%X}` pair preserves trailing newlines that
        # $(...) would otherwise strip.
        body="$(cat; printf X)"
        body="${body%X}"
        if [[ -z "$body" ]]; then
          default_template
        else
          printf '%s' "$body"
        fi
      fi
    } > "$file"
    echo "$file"
    ;;

  done)
    name="${1:-}"
    [[ -n "$name" ]] || die "usage: llm-tasks.sh done <name>"
    name="${name%.md}"
    # Accept either "foo" or "DONE-foo" — normalize to the pending form.
    name="${name#DONE-}"
    # IGNORE-* files are drafts; refusing to rename one keeps them out of
    # the DONE- / clump flow (matches the contract in using-llm-tasks).
    [[ "$name" == IGNORE-* ]] && die "refusing to 'done' an IGNORE- file: $name"
    src="$TASKS_DIR/$name.md"
    dst="$TASKS_DIR/DONE-$name.md"
    [[ -f "$src" ]] || die "not found: $src"
    mv "$src" "$dst"
    echo "$dst"
    ;;

  clump)
    [[ -d "$TASKS_DIR" ]] || die "no llm-tasks/ directory at $PROJECT_ROOT"
    # Fallback batch for DONE- files missing a `batch:` line: the highest
    # existing batch number anywhere (local or completed), or 1 if none.
    fallback="$(max_local_batch)"
    completed_max="$(max_completed_batch)"
    (( completed_max > fallback )) && fallback=$completed_max
    (( fallback == 0 )) && fallback=1
    shopt -s nullglob
    moved=0
    for f in "$TASKS_DIR"/DONE-*.md; do
      [[ -f "$f" ]] || continue
      b="$(grep '^batch:' "$f" | head -1 | sed 's/^batch:[[:space:]]*//' | tr -d '[:space:]' || true)"
      [[ "$b" =~ ^[0-9]+$ ]] || b="$fallback"
      target="$COMPLETED_DIR/batch-$b"
      mkdir -p "$target"
      mv "$f" "$target/"
      moved=$((moved + 1))
    done
    shopt -u nullglob
    echo "[llm-tasks] clumped $moved file(s)"
    ;;

  *)
    die "unknown command: $cmd (use list|new|done|clump)"
    ;;
esac
