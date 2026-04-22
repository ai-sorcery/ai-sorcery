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

Claude scans against the list (observability, persisted test output, committed progress state, structured task workflow, wall-clock test ceiling, automated version bumps, conventional-commit enforcement, parse-don't-validate, transient-vs-permanent errors, cheap-before-expensive) and surfaces concrete gaps.

## `using-llm-tasks`

A markdown-driven task workflow. Ask:

> Set up an LLM task workflow for this repo.

Claude scaffolds `llm-tasks/`, consults `following-best-practices` for a seed task, and drives the four-section lifecycle (Initial Understanding → Tentative Plan → Implementation → Completion Notes). Subsequent invocations handle `new`, `done`, and `clump` through a bundled script.

## `summarizing-sessions`

Wires a SessionEnd hook that drops a dated markdown summary of each session into `~/LLM_Summaries/YYYY-MM-DD/`. Ask:

> Set up session summaries for this repo.

The hook self-forks into the background, skips subagent transcripts, and calls Haiku with a forced JSON schema so each summary is a parseable `{title, body}` pair. Point an Obsidian vault at `~/LLM_Summaries/` to read back the daily log with no extra tooling.

# Contributing

If the LLM makes a commit, here's how to lie and take credit instead:

```
./me.sh
```

# License

[MIT](LICENSE) © Nicholas Westby
