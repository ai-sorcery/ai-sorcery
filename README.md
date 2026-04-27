AI Sorcery is a Claude Code plugin with skills that handle setup and continuous improvement of AI-heavy code bases.

It will get you set up with a macOS VM, help you follow software engineering best practices, and keep Claude running reliably.

# Install & Update

```
/plugin marketplace add ai-sorcery/ai-sorcery
/plugin install sorcery@ai-sorcery
/plugin marketplace update ai-sorcery
```

And then use AI Sorcery.

![AI Sorcery hero illustration](assets/images/ai-sorcery-banner.webp)

# Examples

<!-- toc:begin -->
- [`claiming-authorship`](#claiming-authorship)
- [`following-best-practices`](#following-best-practices)
- [`guarding-commits`](#guarding-commits)
- [`launching-claude`](#launching-claude)
- [`learning-new-tech`](#learning-new-tech)
- [`running-claude-in-a-vm`](#running-claude-in-a-vm)
- [`running-improvement-loops`](#running-improvement-loops)
- [`summarizing-sessions`](#summarizing-sessions)
- [`using-dot-claude`](#using-dot-claude)
- [`using-llm-tasks`](#using-llm-tasks)
- [`writing-commit-messages`](#writing-commit-messages)
<!-- toc:end -->

## `claiming-authorship`

Drops `./me.sh` at your repo root. Ask:

> Install `me.sh` in this repo.

Running `./me.sh` rewrites the last 5 commits so their author field is the current git user, preserving each commit's original author date. Commits already attributed to the user aren't changed.

## `following-best-practices`

A catalog of language-agnostic practices that compound if installed day one. Ask:

> What's the low-hanging fruit in this repo?

Claude scans against the list (README, starter scripts, observability, persisted test output, committed progress state, structured task workflow, wall-clock test ceiling, automated version bumps, conventional-commit enforcement, parse-don't-validate, transient-vs-permanent errors, cheap-before-expensive) and surfaces concrete gaps.

## `guarding-commits`

Installs a self-contained pre-commit hook that blocks any commit whose staged diff adds a line containing a string from a git-ignored `commit-disallowed-terms.txt`. Ask:

> Set up a disallowed-terms commit guard in this repo.

Useful for personal emails, obvious secret prefixes, and `DO NOT COMMIT` markers.

## `launching-claude`

Drops a `claude.sh` at your repo root. Ask:

> Set up `claude.sh` in this repo.

Run it with `./claude.sh`. It sets:

- `IS_DEMO=1`
- `--rc`
- `--effort max`
- `--model claude-opus-4-7`

## `learning-new-tech`

A coaching workflow for learning a programming language, framework, or platform by doing. Ask:

> I want to learn Rust.

Claude scaffolds `learning/` with a flexible 10-15 milestone `OUTLINE.md`, a cross-session `NOTES.md`, and only the first lesson — `learning/01-<topic>/` with `README.md`, `start.sh`, and `score.sh`. The user types the code; subsequent invocations review the work, capture feedback, adapt the outline, and generate the next numbered lesson. Lessons are self-contained — no cross-lesson dependencies — and zero-padded for fast `cd 0<TAB>`.

## `running-claude-in-a-vm`

Scaffolds a Tart-based macOS VM into the current repo with Claude Code and a small set of utilities preinstalled. Ask:

> Set up Claude in a macOS VM here.

After you answer some setup questions, it copies scripts into `./claude-vm/`. Run `./setup.sh` once to install Tart and clone the macOS image, then `./run.sh` to boot the VM and open Screen Sharing. Apple Silicon only.

## `running-improvement-loops`

Installs an autonomous improvement loop under `./improvement/`. Ask:

> Set up the improvement loop in this repo.

Running `./improvement/loop.sh` launches Claude repeatedly — one iteration at a time — under a four-subprocess watchdog (wall-clock SIGTERM + runtime ticker + quit-key listener + result-event grace period), rotating through personas (test-strengthener, code-improver, checkin, wildcard by default). Each iteration reads `LOOP.md`, picks up a persona, does the work, appends to the changelogs, and exits. Stop with `q`/`s`/`h` or `touch stop.txt`.

The `using-llm-tasks` skill has a companion mode (`./task-loop.sh`) that drains the `llm-tasks/` queue under the same watchdog — ask "set up the task loop" to install it.

## `summarizing-sessions`

Wires a SessionEnd hook that drops a dated markdown summary of each session into `~/LLM_Summaries/YYYY-MM-DD/`. Ask:

> Set up session summaries for this repo.

The hook self-forks into the background, skips subagent transcripts, and calls Haiku with a forced JSON schema so each summary is a parseable `{title, body}` pair. Point an Obsidian vault at `~/LLM_Summaries/` to read back the daily log with no extra tooling.

## `using-dot-claude`

Claude Code blocks writes under `.claude/` by default. With this skill installed, just ask:

> Write `.claude/hooks/example.sh` so it echoes "hello".

The write gets routed through a bundled bash script and lands in place.

## `using-llm-tasks`

A markdown-driven task workflow. Ask:

> Set up an LLM task workflow for this repo.

Claude scaffolds `llm-tasks/`, consults `following-best-practices` for a seed task, and drives the four-section lifecycle (Initial Understanding → Tentative Plan → Implementation → Completion Notes). Subsequent invocations handle `new`, `done`, and `clump` through a bundled script.

## `writing-commit-messages`

A ruleset for tight commit messages plus a `commit-msg` hook that enforces it. Ask:

> Set up commit-message style enforcement for this repo.

The hook blocks bodies over 3 bullets, bullets over 20 words, file paths or basenames in the body, and em dashes anywhere. The rule is "subject-only by default. If a fact deserves elaboration, it usually belongs as a code comment near the affected code."

# Contributing

`sorcery-dev` is a repo-internal companion plugin. The `adding-skills` skill is the checklist Claude walks when a contributor asks to "add a sorcery skill." The `demoing-sorcery-skills` skill is a screen-recordable runbook that exercises every public-facing sorcery skill end-to-end by building a small CLI from scratch. Both are installed alongside `sorcery` when you add this marketplace, but fire only on contributor intents — outside this repo, neither has reason to trigger.

After cloning, run `bun install` once to activate the repo's git hooks (sets `core.hooksPath=.githooks`).

Running `./claude.sh` inside this repo activates the local `sorcery` and `sorcery-dev` plugins, so you're always using your latest changes to the plugins.

If the LLM makes a commit, here's how to lie and take credit instead:

```
./me.sh
```

# License

[MIT](LICENSE) © Nicholas Westby
