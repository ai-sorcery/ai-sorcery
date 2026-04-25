---
name: learning-new-tech
description: Use when the user wants to learn a new programming language, framework, or platform via a hands-on, one-lesson-at-a-time curriculum — phrasings like "I want to learn Rust", "set up a learning plan for SwiftUI", "build a curriculum for Postgres", "help me learn Bun", "let's start a learning track for Elixir". Also fires when the user reports lesson completion ("lesson 03 done", "I finished the variables lesson") or asks for the next lesson in an existing `learning/` track ("what's next in my learning track", "ready for lesson 04").
---

# Learning New Tech

A coaching workflow for learning a programming language, framework, or platform by doing. The user types the code; Claude builds the curriculum one lesson at a time, reviews work after each lesson, and adapts what comes next based on what actually happened.

The shape is deliberately small: a `learning/` directory at the user's repo root, with a top-level outline, a cross-session notes file, and one numbered subdir per lesson — each lesson self-contained, with its own `start.sh` and `score.sh`.

## Why this shape

- **Outline first, lessons one at a time.** The outline is a flexible map; each next lesson is generated against the latest outline, the latest notes, and the user's most recent feedback. Generating all lessons upfront freezes the plan before any contact with the learner.
- **Zero-padded numbering for fast `cd`.** `cd learning/01<TAB>` autocompletes; `ls` sorts naturally; lesson identity is stable in NOTES.md references.
- **No dependencies between lessons.** Each lesson's `start.sh` builds initial state from scratch. The user can drop into any lesson cold without setting up state from earlier ones.
- **NOTES.md is the cross-session memory.** Sessions end. The user comes back days later in a fresh Claude. NOTES.md is the only thing a new session needs to read to pick up where the last one left off.

## What to do — first invocation

Triggered by phrasings like "I want to learn Rust" or "set up a learning plan for SwiftUI."

If the user's repo already has a `learning/` directory with a different topic, ask whether to use a new subdir (`learning-<tech>/`) or replace the existing track. Default to a new subdir — preserving prior tracks is cheap.

In a single message, do all of this:

1. **Read the room.** Ask one or two short questions about prior experience: "Have you used a similar tech before?" / "Any specific goal — a side project you want to ship?" Skip if context is already clear from earlier turns.
2. **Build the outline.** Write `learning/OUTLINE.md` with 10-15 milestones from "hello world" to a small real project. The outline names ideas, not lesson files — it's a map, not a manifest. Mark it "Subject to revision."
3. **Seed NOTES.md.** Write `learning/NOTES.md` with what the user told you they already know, the start date, and an empty "Lessons completed" section.
4. **Create lesson 01 only.** Build `learning/01-<short-kebab-topic>/` with `README.md`, `start.sh` (executable), and `score.sh` (executable). The lesson covers the first outline milestone, scaled to the user's stated experience. Lesson directory numbers are always two-digit zero-padded — `01` through `09`, then `10`, `11`, …, `99`.
5. **Hand off.** Tell the user to type `cd learning/01` then press Tab to autocomplete the topic suffix, then `./start.sh`. `./score.sh` self-checks the work, but tell the user to return to Claude when they're done either way — passing the self-check isn't a substitute for the thorough review and next-lesson generation that the runbook does in-conversation.

## What to do — subsequent invocations

Two cases:

### "Lesson N done" / "I finished N" / "ready for the next"

In what follows, use `<NN>` for the two-digit padded current lesson number (read it from NOTES.md or `ls learning/`) and `<NN+1>` for the next.

1. **Re-orient.** Read `learning/OUTLINE.md` and `learning/NOTES.md` in full — Claude sessions don't carry over.
2. **Inspect the work.** `ls learning/<NN>-*/` and read the files the user touched. Run `bash learning/<NN>-*/score.sh` and capture the output.
3. **Thorough review.** Look at the code, not just the score. Note: idiomatic vs. fighting the language; shortcuts taken; concepts the user appears solid on; concepts that look shaky. The score check is necessary but not sufficient.
4. **Ask for feedback.** One short prompt: "Before I plan the next lesson — anything to note? Too easy / too hard / want to detour somewhere / skip something coming up?" Wait for the user.
5. **Update NOTES.md.** Append a section for lesson `<NN>` with: completion date, score result, your review observations, the user's feedback verbatim. This is the file a future fresh session will read.
6. **Update OUTLINE.md if feedback warrants.** If the user said "I already know X," cross out the X milestone with a strikethrough and a note. If they want a detour, insert a new milestone. Don't rewrite the whole outline — preserve the original ordering as much as possible so progress stays legible.
7. **Create the next lesson.** Build `learning/<NN+1>-<topic>/` against the updated outline and the user's feedback. Same three files: `README.md`, `start.sh`, `score.sh`. Pad to two digits — lesson 9 is followed by `10-`, not `010-`.
8. **Hand off again.** Tell the user to `cd learning/<NN+1>` and press Tab, then `./start.sh`.

### "What's next?" / "Where did we leave off?"

The user is returning after time away. Read OUTLINE.md and NOTES.md, then compare the latest entry in NOTES.md against `ls learning/` — if the most recent lesson directory has no matching review section in NOTES.md, the user finished it in a prior session and never came back; treat it as "Lesson N done" and run the inspect-and-review path. Otherwise summarize where they are, and confirm whether to continue from the next pending lesson or revisit a recent one.

## Lesson file shapes

Each lesson directory has exactly three files. Make them succinct — the user has to read every one.

### `README.md`

Three sections. No more.

```markdown
# Lesson 03 — Pattern matching

## Goal
Read a list of `Result<i32, String>` values and print only the successes.

## Background
`match` lets you destructure enums by variant. Rust's `Result` has two variants — `Ok(T)` and `Err(E)`. The compiler enforces that you handle both.

## Instructions
1. `./start.sh` creates `src/main.rs` with the input list pre-filled.
2. Fill in the `match` block where marked `// TODO: match here`.
3. `cargo run` should print `42` and `7`.
4. `./score.sh` to self-check. Tell me when you're done.
```

Keep instructions imperative and numbered. The user reads top-to-bottom and types as they go. No long prose; no exposition that could be a link instead.

### `start.sh`

Sets up just enough initial state for the user to start typing. Idempotent — re-running on a dirty tree warns but doesn't clobber user changes.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -e src/main.rs ]]; then
  echo "start.sh: src/main.rs already exists — leaving it alone."
  echo "start.sh: delete it first if you want a fresh start."
  exit 0
fi

mkdir -p src
cat > Cargo.toml <<'EOF'
[package]
name = "lesson-03"
version = "0.1.0"
edition = "2021"
EOF

cat > src/main.rs <<'EOF'
fn main() {
    let results: Vec<Result<i32, String>> = vec![
        Ok(42),
        Err("nope".to_string()),
        Ok(7),
    ];

    for r in results {
        // TODO: match here — print the inner i32 only on Ok
    }
}
EOF

echo "start.sh: ready. Edit src/main.rs and run \`cargo run\`."
```

The user types the meat. `start.sh` writes only the scaffolding and the `// TODO` markers.

### `score.sh`

Mechanical pass/fail checks. Print one line per criterion as `[PASS]` or `[FAIL]`. Exit 0 if every check passes, 1 otherwise. Run actual program behavior where possible — file presence is weaker than `cargo run`'s output matching expectations.

```bash
#!/usr/bin/env bash
# No -e: every check must run to accumulate fails. -u and pipefail still apply.
set -uo pipefail

cd "$(dirname "$0")"
fails=0

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] $label"
  else
    echo "[FAIL] $label"
    fails=$((fails + 1))
  fi
}

check "src/main.rs exists" test -f src/main.rs

# Run the program once and reuse its output for every behavior check.
output="$(cargo run --quiet 2>/dev/null)" && cargo_ok=1 || cargo_ok=0
check "cargo run succeeds" test "$cargo_ok" = "1"
check "output contains 42" grep -q 42 <<<"$output"
check "output contains 7"  grep -q 7 <<<"$output"
check "no Err leaked through" sh -c '! grep -q nope <<<"$1"' _ "$output"

if (( fails > 0 )); then
  echo
  echo "score.sh: $fails check(s) failed."
  exit 1
fi
echo
echo "score.sh: all checks passed."
```

Behavior matters more than syntax. Avoid `grep -q 'match' src/main.rs`-style keyword-presence checks against the user's source — they false-positive on comments (including the `// TODO: match here` left by `start.sh`) and false-negative on idiomatic alternatives (`if let`, helper methods). Verify what the program *does*, not what it *contains*.

For lessons whose outcome can't be machine-verified (UI work, design decisions, learning-by-reading), `score.sh` becomes a checklist printer that the user self-attests against — print each criterion and ask the user to run `./score.sh --confirm` after they've checked each one. Every lesson has a `score.sh`; the checklist-printer pattern covers the cases where mechanical verification doesn't apply.

## OUTLINE.md and NOTES.md

### `OUTLINE.md`

```markdown
# Learning Rust

A general curriculum from "hello world" to a small CLI project. ~12 milestones. Subject to revision based on feedback after each lesson.

1. Hello world + `cargo init`
2. Primitive types and variables
3. Pattern matching with `match`
4. Ownership and borrowing
5. Error handling with `Result` and `?`
6. Iterators and closures
7. Collections (`Vec`, `HashMap`)
8. Modules and crates
9. Testing with `#[test]` and `cargo test`
10. A small CLI: argv parsing + file I/O
11. Async basics with `tokio`
12. Capstone: a CLI tool the user picks
```

Numbered list. Each item is one short noun phrase. The lesson's actual content is decided when the lesson is generated, not now — the outline names the destination, not the route.

### `NOTES.md`

```markdown
# Notes — learning Rust

Started: 2026-04-25

## What I already know
- C-family syntax (curly braces, semicolons)
- Memory management concepts (manual malloc/free in C)
- Functional basics from a year of Elixir

## Lessons completed

### 01 — hello-world (2026-04-25)
- Score: passed all checks
- Review: idiomatic; used `println!` correctly; understood the `!` macro indicator
- User feedback: "Easy. Skip the `cargo` deep-dive — I already use it for other things."
- Outline updated: removed planned cargo-internals milestone

### 02 — primitive-types (2026-04-26)
- Score: passed
- Review: tripped briefly on `i32` vs `usize` for indices — mention this again next time it comes up
- User feedback: none

## Open questions / things to revisit
- Lifetime annotations — flagged as "later" during ownership lesson
```

Bias toward terseness. Each lesson section is 3-5 lines. The "Open questions" section is the running list of things deferred.

## Adapting based on feedback

User feedback shapes both the next lesson and the rest of the outline:

- **"Too easy / I already know this."** Mark the relevant outline milestone done with a note ("user reports prior knowledge"); raise the difficulty of the next lesson by reducing scaffolding (less `// TODO` hand-holding, more "build it from scratch") or by combining two outline milestones into one denser lesson.
- **"Too hard."** Don't simplify the next milestone — split the failed lesson into two lessons. The first re-attacks the rough concept with a smaller scope; the second is the original target. Note the split in NOTES.md.
- **"I want to detour to X."** Insert a new milestone in OUTLINE.md before the next planned one. Build a lesson against the detour. Don't backtrack the numbering — the next lesson dir is still `0(N+1)`, just with the detour topic.
- **"Skip the next thing."** Strikethrough the next outline milestone and move on to the one after.
- **"Continue."** No outline change. Build the next lesson from the next pending milestone.

NOTES.md should record the verbatim feedback that drove each adjustment, not just the adjustment. Future-you (or a fresh Claude session) needs to know *why* an outline item was crossed out, not just that it was.

## Caveats

- **The user types the code.** This skill is hands-on. Don't write the lesson's solution code yourself when reviewing or coaching — describe, hint, point at idioms, let the user write. Writing it for them defeats the workflow.
- **Sessions don't persist.** Always re-read OUTLINE.md and NOTES.md before generating the next lesson — the in-context picture from a prior session is gone, and a stale assumption ("the user said X earlier") will produce a misaligned lesson. NOTES.md is the contract.
- **Score scripts are bash, not test frameworks.** Each lesson's `score.sh` is a small mechanical check, not a test suite. If a lesson genuinely needs a test framework, add it as part of the lesson content (e.g., a Rust lesson on testing builds toward `cargo test`) — don't pre-install one.
- **Lessons are self-contained, including dependencies.** If lesson 06 needs a crate that lesson 03 also used, lesson 06's `start.sh` adds it again. No "set up your environment" prerequisites that span lessons.
- **One track per directory.** If the user wants to learn two things in parallel (Rust and SwiftUI), use two top-level dirs (`learning-rust/`, `learning-swiftui/`). Don't try to interleave them in one tree — the numbering and outline assume one curriculum per directory.
- **Outline drift is expected.** After 5-6 lessons, the outline often looks meaningfully different from the original. That's working as intended — see *Adapting based on feedback* for how the edits should be made.

## Related skills

- `using-llm-tasks` — for project work where the user is shipping rather than learning.
- `following-best-practices` — for scanning a real project for day-one gaps.
