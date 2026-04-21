---
name: launching-claude
description: Use when the user wants Claude Code to launch with privacy-friendly defaults (hidden account email/org, --rc, --effort max, --model claude-opus-4-7) for a specific repo. Creates an executable `claude.sh` at the repo root so the user runs `./claude.sh` locally — no shell aliases, no symlinks, no $PATH changes.
---

# Launching Claude

Drops an executable `./claude.sh` at the root of the user's current repo. They run it with `./claude.sh` from that repo.

## What to do

Copy the plugin's canonical launcher into the target repo and mark it executable:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/claude.sh" ./claude.sh
chmod +x ./claude.sh
```

If `./claude.sh` already exists in the repo, confirm with the user before overwriting.

## What the launcher does

```bash
exec env IS_DEMO=1 claude --rc --effort max --model claude-opus-4-7 "$@"
```

- **`IS_DEMO=1`** — undocumented Anthropic env var that hides the account email and organization from the welcome banner. Confirmed live in v2.1.116. Side effect: skips first-run onboarding prompts.
- **`--rc`** — hidden CLI flag.
- **`--effort max`** — deepest reasoning level.
- **`--model claude-opus-4-7`** — pins to Opus 4.7.

Extra arguments pass through, so the launcher is a drop-in for `claude`: `./claude.sh -c`, `./claude.sh "do the thing"`, `./claude.sh --worktree`, etc.

## Caveats

- `IS_DEMO` is undocumented. A future Claude Code release could rename or remove it, and the launcher will silently stop hiding the banner until the script is updated.
- `--rc` is a hidden flag; Anthropic may change it without notice.
- `--effort max` is token-expensive — for routine work on a metered plan, prefer `high`.
- Do not run `./claude.sh` from inside an active Claude Code session; nesting `claude` is not supported.
- The repo-local copy does **not** auto-update when the plugin's canonical launcher changes. If the template gets updated, re-run the skill to re-copy.
