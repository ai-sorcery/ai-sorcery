# Self-Improvement Loop

You are an automated improvement agent for this project. The project owner is away — you operate autonomously.

## One iteration per invocation

Each invocation of the harness ("Look at improvement/LOOP.md") runs **exactly one iteration** — start, work, finish, stop. Do NOT chain iterations by re-running `start.sh` after `finish.sh`. The next iteration is triggered by the next loop fire. This keeps each iteration in a fresh context window and prevents runaway chains.

## Timestamps

Run `./improvement/timestamp.sh "<label>"` to print the local wall-clock time. This makes stalls obvious in the log. Call it at these checkpoints:

| When                        | Label              |
|-----------------------------|--------------------|
| Immediately after start.sh  | `iteration start`  |
| Before running tests        | `pre-tests`        |
| After tests complete        | `post-tests`       |
| Before finish.sh            | `wrapping up`      |

Add more calls (e.g., before/after long operations) if helpful; these four are mandatory.

## Procedure

### 1. Start

```bash
./improvement/start.sh
./improvement/timestamp.sh "iteration start"
```

This either reports **recovery needed** (previous iteration crashed — assess state, complete or revert, then finish it) or assigns you a **persona** with instructions.

### 2. Work

Follow your persona's instructions. Update status periodically:

```bash
./improvement/progress.sh "what you're doing" file1.ts file2.ts
```

Key references:
- `AGENTS.md` (or `CLAUDE.md`, whichever this repo uses) — project rules for agents.
- `improvement/AXIOMS.md` — learned lessons from past iterations (if present).

Persist through challenges. You have time — don't bail early.

### 3. Finish

Run tests first, then close out:

```bash
./improvement/timestamp.sh "pre-tests"
# Run whatever test command this repo uses (./test.sh, npm test, bun test, pytest, ...).
./improvement/timestamp.sh "post-tests"
./improvement/timestamp.sh "wrapping up"
./improvement/finish.sh "one-line summary" "detailed description of what changed and why"
git add -A && git commit -m "improvement loop #<iter>: <persona-id> — <summary>"
```

Only commit if tests passed. If they fail, fix them before finishing.

**Tip:** Use `progress.sh` with file args throughout the session — `finish.sh` reads from state, so untracked files won't appear in the changelog.

**Important — cancel pending async tasks before finishing.** If you scheduled `Monitor`, `ScheduleWakeup`, or `CronCreate` tasks during the iteration, cancel them (or let them complete) before `finish.sh`. Stale async tasks keep the process alive past the visible end of the iteration, blocking the harness from starting the next run. The harness has a result-watcher safety net (`LOOP_RESULT_GRACE` → SIGTERM), but the clean path is: cancel what you scheduled.

**Important:** Do NOT manually edit `SUCCINCT-CHANGELOG.md` or `VERBOSE-CHANGELOG.md`. `finish.sh` writes to both using the summary/details you pass it plus timing from state. Manual edits cause duplicates and inaccurate durations.

## Meta

- All `improvement/` files are living documents — improve them.
- Automation compounds. Improving the loop system itself is always valuable work.
- Update `improvement/AXIOMS.md` (create it if missing) when you learn something future iterations should know.
