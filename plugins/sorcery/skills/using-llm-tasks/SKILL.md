---
name: using-llm-tasks
description: Use when the user wants to create a new task, work the next pending task, mark a task done, or archive finished tasks in a repo's `llm-tasks/` directory. Also use when the user wants to introduce this markdown-driven task workflow to a repo that doesn't have one yet ("set up an LLM task workflow", "let's track work as markdown files") — first invocation scaffolds `llm-tasks/` and seeds the first task from the `following-best-practices` skill. Also handles installing the `task-loop.sh` autonomous mode that drains the queue unattended.
---

# Using LLM Tasks

A tiny markdown-driven task workflow. Each task is a file under `llm-tasks/`; progress is appended to the file in four sections; completion is a filename change. All operations go through the bundled `llm-tasks.sh` script.

## The four-section lifecycle

Every task file is worked through these sections, in order. Append each one to the file *before* moving to the next — don't batch.

1. **Initial Understanding** — your interpretation of what needs to change and why, written *before* reading code.
2. **Tentative Plan** — after investigating, the specific files / functions / approach. Update as you learn more during implementation.
3. **Implementation** — what you actually did. If the approach changes, update this rather than rewriting the plan.
4. **Completion Notes** — before/after comparison, logs that helped, logging added. Anything future-you would want to know.

When all four sections are filled, mark the task done. The filename gets a `DONE-` prefix; the content stays intact.

## First invocation in a repo (scaffolding)

If `llm-tasks/` does not exist yet, this is a fresh install. Do all of the following:

1. Source the seed task first. Call the Skill tool with `skill: "following-best-practices"` to get the top-ranked day-one gap in this repo. If that skill isn't registered in the current environment, read `${CLAUDE_PLUGIN_ROOT}/skills/following-best-practices/SKILL.md` directly with the Read tool and follow its "How to use this list" section. Adapt the "Seed task shape" to this repo (concrete file paths, function names, specifics from the commit history).
2. Pick a kebab-case filename based on the practice you're addressing (e.g., `install-observability`, `add-test-output-tee`, `add-plan-md`).
3. Create the task file by piping the adapted seed-task body through `${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh new <filename>` — the script creates `llm-tasks/` if missing and stamps the `batch:` line.
4. Tell the user what was scaffolded, show them the seed-task path, and ask if they'd like to start on it now or edit it first.

If *every* practice is already in place, skip step 2 and instead create a placeholder `getting-started.md` with a short note explaining how to create the first real task, then tell the user the repo already follows the day-one practices.

## Subsequent invocations (existing `llm-tasks/`)

Pick the behavior from what the user is asking for:

| User intent                              | What to do                                                                                      |
|------------------------------------------|--------------------------------------------------------------------------------------------------|
| "work the next task" / "Go!" / "continue" | Run `list`; open the first pending task; work it through the four sections; `done`; offer to `clump`. |
| "add a task for X"                       | Call `new <name>` with a short kebab-case name; stub the four sections from what the user told you. |
| "I finished X"                           | Call `done <name>`. Don't clump automatically — the user may have more to mark done.            |
| "archive the finished ones"              | Call `clump`.                                                                                    |
| "run the task loop" / "drain the queue unattended" | Install `task-loop.sh` (see below); tell the user to run `./task-loop.sh` from the repo root. |

## Autonomous mode: `task-loop.sh`

When the user wants the queue drained unattended — "work through everything overnight," "set up a task loop," "drain the queue," etc. — install the harness that launches Claude Code repeatedly until every pending task is done.

Run the installer from the repo root:

```bash
"${CLAUDE_PLUGIN_ROOT}/loop/install-task-loop.sh"
```

That drops `task-loop.sh` + `prompt-task-loop.sh` at the repo root, creates `data/task-loop-inbox/` and `data/task-loop-logs/`, installs a wrap-up hook and a sideload hook under `improvement/`, and wires both hooks into `.claude/settings.json` via `dot-claude.sh`. Idempotent — re-running skips what's already present.

Afterwards:

- Run the loop: `./task-loop.sh`. It counts pending tasks (anything in `llm-tasks/` that isn't `DONE-*` or `IGNORE-*`), picks up the first, and works it via the four-section lifecycle above. On crash or timeout, the next iteration reads the previous log and resumes.
- Send a prompt to the running loop: `./prompt-task-loop.sh "reconsider the approach on task X"`. The sideload hook injects your message as additional context on the next PostToolUse event. This is how remote messages reach the loop in headless mode (`claude -p --rc` doesn't register a Remote Control bridge, so there's no iPhone-app session to talk to directly).
- Stop the loop: press `q`/`s`/`h` or `touch stop.txt`. The current iteration finishes before the loop exits.
- Exit when the queue empties: set `TASK_LOOP_EXIT_WHEN_DONE=1` before running (default is to idle-wait for new tasks).

For the broader open-ended improvement harness (rotating personas, changelogs, drift-detection), invoke the sibling skill `running-improvement-loops`. It shares the `improvement/` scaffolding and the four-subprocess watchdog pattern with `task-loop.sh`.

## Invoking the script

The script lives at `${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh` and uses stdin for task body content (same pattern as the sibling `dot-claude.sh`):

```bash
# list pending tasks
${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh list

# create a task with the default four-section template
${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh new install-observability

# create a task with a custom body
cat <<'EOF' | ${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh new install-observability
# Install observability

## Initial Understanding
...
EOF

# mark done and archive
${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh done install-observability
${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh clump
```

Paths resolve against the git toplevel (falling back to `$PWD` outside a repo). Task filenames are kebab-case; no `.md` extension needed on the command line. Prefix an in-progress draft with `IGNORE-` to keep it out of `list` and `clump` until you're ready.

## Batch numbering

All tasks currently in `llm-tasks/` — pending or `DONE-` — share the open batch number. `clump` archives each `DONE-*.md` into `llm-tasks/completed/batch-N/` by its stamp. A new batch opens only after the previous is fully clumped, so several `new` calls in a row land in the same batch and can be worked and clumped together.

## When not to use

- Trivial one-off changes that will be committed in the next few minutes. The lifecycle is overhead for work the user is about to finish anyway.
- Tasks that belong in an issue tracker with a broader audience (cross-team, customer-facing). This workflow is for solo/agent work on a single repo.

## Related

- `following-best-practices` — consulted on first invocation to source the seed task. Also useful any time the user asks "what should I work on next?" in a well-maintained repo.
