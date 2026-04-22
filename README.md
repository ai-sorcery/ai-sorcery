AI Sorcery - be a magician with Claude Code.

# Install & Update

```
/plugin marketplace add ai-sorcery/ai-sorcery
/plugin install sorcery@ai-sorcery
/plugin marketplace update ai-sorcery
```

# Examples

## `using-dot-claude`

Claude Code blocks writes under `.claude/` by default. With this skill installed, just ask:

> Write `.claude/hooks/example.sh` so it echoes "hello".

The write gets routed through a bundled bash script and lands in place.

## `launching-claude`

Drops a `claude.sh` at your repo root. Ask:

> Set up `claude.sh` in this repo.

Run it with `./claude.sh`. It sets:

- `IS_DEMO=1`
- `--rc`
- `--effort max`
- `--model claude-opus-4-7`

## `following-best-practices`

A catalog of language-agnostic practices that compound if installed day one. Ask:

> What's the low-hanging fruit in this repo?

Claude scans against the list (README, starter scripts, observability, persisted test output, committed progress state, structured task workflow, wall-clock test ceiling, automated version bumps, conventional-commit enforcement, parse-don't-validate, transient-vs-permanent errors, cheap-before-expensive) and surfaces concrete gaps.

## `using-llm-tasks`

A markdown-driven task workflow. Ask:

> Set up an LLM task workflow for this repo.

Claude scaffolds `llm-tasks/`, consults `following-best-practices` for a seed task, and drives the four-section lifecycle (Initial Understanding → Tentative Plan → Implementation → Completion Notes). Subsequent invocations handle `new`, `done`, and `clump` through a bundled script.

## `summarizing-sessions`

Wires a SessionEnd hook that drops a dated markdown summary of each session into `~/LLM_Summaries/YYYY-MM-DD/`. Ask:

> Set up session summaries for this repo.

The hook self-forks into the background, skips subagent transcripts, and calls Haiku with a forced JSON schema so each summary is a parseable `{title, body}` pair. Point an Obsidian vault at `~/LLM_Summaries/` to read back the daily log with no extra tooling.

## `claiming-authorship`

Drops `./me.sh` at your repo root. Ask:

> Install `me.sh` in this repo.

Running `./me.sh` rewrites the last 5 commits so their author field is the current git user, preserving each commit's original author date. Commits already attributed to the user are no-ops, so re-runs are idempotent.

## `guarding-commits`

Installs a self-contained pre-commit hook that blocks any commit whose staged diff adds a line containing a string from a git-ignored `commit-disallowed-terms.txt`. Ask:

> Set up a disallowed-terms commit guard in this repo.

Useful for personal emails, obvious secret prefixes, and `DO NOT COMMIT` markers. Matching is plain-string so spaces and regex metacharacters are fine. The hook scans added lines only, so legacy content doesn't block unrelated commits. `core.hooksPath` is per-clone local config — the installer prints an onboarding line to copy into README / CONTRIBUTING so teammates activate it after cloning.

## `running-improvement-loops`

Installs an autonomous improvement loop under `./improvement/`. Ask:

> Set up the improvement loop in this repo.

Running `./improvement/loop.sh` launches Claude repeatedly — one iteration at a time — under a four-subprocess watchdog (wall-clock SIGTERM + runtime ticker + quit-key listener + result-event grace period), rotating through personas (test-strengthener, code-improver, checkin, wildcard by default). Each iteration reads `LOOP.md`, picks up a persona, does the work, appends to the changelogs, and exits. Stop with `q`/`s`/`h` or `touch stop.txt`.

The `using-llm-tasks` skill has a companion mode (`./task-loop.sh`) that drains the `llm-tasks/` queue under the same watchdog — ask "set up the task loop" to install it.

# Contributing

`sorcery-dev` is a repo-internal companion plugin. Its single skill `adding-skills` is the checklist Claude walks when a contributor asks to "add a sorcery skill." It's installed alongside `sorcery` when you add this marketplace, but fires only on contributor intents — outside this repo it has no reason to trigger.

Running `./claude.sh` inside this repo activates the local `sorcery` and `sorcery-dev` plugins, so you're always using your latest changes to the plugins.

If the LLM makes a commit, here's how to lie and take credit instead:

```
./me.sh
```

# License

[MIT](LICENSE) © Nicholas Westby
