# running-improvement-loops

Installs an autonomous improvement loop into the current repo. `./improvement/loop.sh` runs Claude Code repeatedly — one iteration at a time, with a four-subprocess watchdog (wall-clock SIGTERM + runtime ticker + quit-key listener + result-event grace period) — driven by a rotating set of personas (test-strengthener, code-improver, checkin, wildcard by default).

Pairs with `using-llm-tasks` — if that skill is also installed, `./task-loop.sh` (scaffolded separately) drains pending tasks under the same watchdog pattern.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.

## Example

Asking Claude to set up an autonomous improvement loop in a repo:

![The running-improvement-loops skill in action: Claude receives "I want to create a self improvement loop the AI can run by itself.", loads the skill, runs install-improvement-loop.sh in parallel with reading PLAN.md and the default personas, and reports the scaffolding is in improvement/ with a PostToolUse wrap-up hook wired into .claude/settings.json. It then proposes a 5-persona set tailored to the repo (skill-exerciser, harness-verifier, skill-feedback, checkin, wildcard) — dropping test-strengthener and code-improver as a poor fit — and asks whether to apply. The user replies "I don't think we need: harness-verifier, but the rest look good." and Claude proceeds to rewrite improvement/personas.json.](example.png)
