---
name: running-improvement-loops
description: Use when the user wants to install an autonomous improvement loop into the current repo — a harness that launches Claude Code repeatedly (one iteration at a time) with rotating personas to find and fix issues unattended. The harness ships with a four-subprocess watchdog, a soft-deadline wrap-up hook, and changelogs that persist learning across iterations.
---

# Running Improvement Loops

Scaffolds an `improvement/` directory at the root of the current repo with the scripts that turn Claude Code into an autonomous improvement agent. Each iteration is driven by a persona (test-strengthener, code-improver, checkin, wildcard by default); the harness rotates through them.

## What to do

> ⚠️ Read the **Caveats** below before installing — this skill runs Claude unattended with `--dangerously-skip-permissions`, auto-approving every tool call.

Run the plugin's installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/loop/install-improvement-loop.sh"
```

That copies the canonical loop scripts into `./improvement/`, seeds empty `SUCCINCT-CHANGELOG.md` and `VERBOSE-CHANGELOG.md` files, and wires a PostToolUse wrap-up hook into `.claude/settings.json` via `dot-claude.sh`. Safe to run twice — the installer skips files that already exist and leaves `.claude/settings.json` alone if the hook entry is already present.

After the installer runs, **adapt the scaffolded `improvement/personas.json` to the specific repo**. The default set is four general-purpose personas; the ideal set varies by project:

- If the repo has a UI and Playwright is configured, add an `e2e-verifier` persona that drives the app in a real browser.
- If the repo has an obvious domain focus (scoring pipeline, data ingestion, etc.), add a domain-specialist persona.
- Strike a balance between variety and rotation speed. More personas means iterations stay fresh — each persona sees the repo in a different state, and `wildcard`'s "don't repeat the last N iterations" constraint has more elbow room. Fewer personas means meta-review personas (`checkin`) come around sooner. As a rule of thumb, 4-6 personas balances both; below 3 the rotation feels repetitive, above 8 `checkin` fires too rarely to catch drift.

Read the repo's manifest (`package.json`, `pyproject.toml`, etc.), the full `README.md`, and a shallow directory scan to infer shape; then suggest concrete persona edits and apply them to `improvement/personas.json` if the user agrees.

After editing, sanity-check the persona list — `personas.json` is a flat array, so the line numbers don't show persona names and an off-by-one in the array index can quietly drop the new entry into the wrong slot:

```bash
jq '.[] | .name' improvement/personas.json
```

## How a loop iteration works

`improvement/loop.sh` runs forever. Each iteration:

1. Writes the current Unix timestamp to `improvement/.iteration-start` (consumed by the wrap-up hook to compute elapsed time).
2. Launches `claude -p ... "Look at improvement/LOOP.md"` — Claude reads `LOOP.md`, runs `start.sh` to get a persona, does the work, runs `finish.sh` to append the iteration to both changelogs, and exits.
3. Four subprocesses run in parallel alongside Claude:
   - **Watchdog** — `SIGTERM` after `LOOP_MAX_RUN` seconds (default 90m), `SIGKILL` 10s later.
   - **Runtime ticker** — prints total loop runtime every 60s.
   - **Quit-key listener** — q/s/h pressed during an iteration sets a flag; the loop exits cleanly after the iteration finishes (does not kill the current iteration).
   - **Result watcher** — once Claude emits its first `"type":"result"` stream event, waits `LOOP_RESULT_GRACE` (default 15s) for natural exit, then SIGTERMs. This is the fix for Monitor/ScheduleWakeup tasks that otherwise keep Claude alive for minutes past the iteration's real end.
4. Sleeps `LOOP_WAIT` seconds (default 5m) before the next iteration. A failed iteration (exit≠0 or runtime<`LOOP_MIN_RUN`) triggers a `LOOP_FAIL_WAIT` penalty (default 60m) instead.

Stop the loop: press `q`, `s`, or `h` (takes effect at the end of the current iteration), or `touch stop.txt`.

Skip the inter-iteration wait: press `c` or `n` during the `LOOP_WAIT` countdown to start the next iteration immediately. Has no effect during an iteration — the keys are only read by `wait_for_next_loop`, which only runs between iterations.

## How the personas rotate

`improvement/counter.txt` holds a monotonically increasing integer. `start.sh` picks persona `counter % len(personas)` from `improvement/personas.json`, writes `.state.json` with the assignment, and bumps the counter. Claude reads the persona's instructions from stdout and acts on them. `finish.sh` clears the state and appends to the changelogs.

Adding a persona mid-loop is fine: edit `personas.json` and the next iteration picks up the new list. Removing one renumbers the cycle.

Optional persona field `showGlobalHistory: N` injects a summary of the last N iterations across all personas into that persona's prompt, under the heading "Last N Iterations (All Personas)". Set it on personas whose instructions reference the recent global history — e.g. the default `wildcard` uses 20 to enforce its "don't repeat the last 20 iterations" rule. Omit the field to skip the injection.

## The wrap-up hook

`improvement/wrap-up-hook.sh` fires on every PostToolUse event. If the iteration has been running past `LOOP_WRAPUP_THRESHOLD` (default 60m) but is still within the 90m hard deadline, it emits a system-reminder telling Claude to finalize: run tests, call `finish.sh`, commit. Fires at most once per iteration via a `.wrap-up-fired` sentinel file.

This exists so an iteration that's drifting doesn't get cut off mid-commit by the hard-kill SIGTERM — Claude gets ~30 minutes of warning to land what's done.

## Configuration knobs (env vars)

Override any of these before running `./improvement/loop.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `LOOP_WAIT` | 300 | seconds between successful iterations |
| `LOOP_FAIL_WAIT` | 3600 | seconds to wait after a failed iteration |
| `LOOP_MIN_RUN` | 10 | runs shorter than this count as failures |
| `LOOP_MAX_RUN` | 5400 | wall-clock ceiling per iteration (SIGTERM after) |
| `LOOP_RESULT_GRACE` | 15 | seconds to let Claude exit after first result event |
| `LOOP_LOG_DIR` | `improvement/logs` | where per-iteration logs go |
| `LOOP_STOP_FILE` | `stop.txt` | sentinel path that stops the loop |
| `LOOP_WRAPUP_THRESHOLD` | 3600 | wrap-up hook threshold (seconds) |

## Caveats

- **⚠️ Runs Claude unattended with `--dangerously-skip-permissions`.** Every tool call is auto-approved — every file edit, every shell command, every git operation, no prompt. Only install in repos where that level of autonomy is acceptable. Stop the loop (q/s/h or `touch stop.txt`) before doing anything that assumes the loop isn't running concurrently.
- **Requires `bun`** (`brew install oven-sh/bun/bun`). `helpers.ts` and `render.ts` run under Bun. The installer fails fast if it's missing.
- **Requires `jq`** (`brew install jq`). Used by both the installer and the runtime stream filter.
- **Pins to `claude-opus-4-7[1m]`.** Edit `improvement/loop.sh` if a different model is wanted. The `[1m]` suffix enables the 1M-token context window — drop it for repos that don't need it.
- **Scripts are copies, not symlinks.** Edits to the installed scripts in `improvement/` are local to the repo; they don't propagate to other installs. If the plugin's canonical scripts change, re-run the installer and let it overwrite (remove the old file first).
- **Not coordinated with `task-loop.sh`.** Only one loop harness should run at a time per repo — they share the `improvement/.iteration-start` marker. Running both concurrently produces nonsense wrap-up signals. `task-loop.sh` is installed by the sibling skill `using-llm-tasks` (autonomous mode section).
- **The hook-script location is `improvement/`, not `.claude/hooks/`.** Unconventional but deliberate: settings.json references the hook by absolute path, and editing files under `.claude/` requires routing through `dot-claude.sh`. Keeping them under `improvement/` means normal editing works.
