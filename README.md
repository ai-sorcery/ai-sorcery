AI Sorcery - be a magician with Claude Code.

# Install

```
/plugin marketplace add ai-sorcery/ai-sorcery
/plugin install sorcery@ai-sorcery
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

# Contributing

If the LLM makes a commit, here's how to lie and take credit instead:

```
./me.sh
```

# License

[MIT](LICENSE) © Nicholas Westby
