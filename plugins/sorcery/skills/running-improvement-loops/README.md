# running-improvement-loops

Installs an autonomous improvement loop into the current repo. `./improvement/loop.sh` runs Claude Code repeatedly — one iteration at a time, with a four-subprocess watchdog (wall-clock SIGTERM + runtime ticker + quit-key listener + result-event grace period) — driven by a rotating set of personas (test-strengthener, code-improver, checkin, wildcard by default).

Pairs with `using-llm-tasks` — if that skill is also installed, `./task-loop.sh` (scaffolded separately) drains pending tasks under the same watchdog pattern.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
