---
name: launching-claude
description: Use when the user wants Claude Code to launch with privacy-friendly defaults (hidden account email/org, --rc, --effort max, --model claude-opus-4-7) for a specific repo. Creates an executable `claude.sh` at the repo root so the user runs `./claude.sh` locally — no shell aliases, no symlinks, no $PATH changes.
---

# Launching Claude

Drops an executable `./claude.sh` at the root of the user's current repo. They run it with `./claude.sh` from that repo.

## What to do

Run the plugin's installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/install-launcher.sh"
```

That copies `${CLAUDE_PLUGIN_ROOT}/claude.sh` to `./claude.sh` and marks it executable. It refuses to overwrite an existing `./claude.sh` — if one is already there, confirm with the user that replacing it is intended, then `rm ./claude.sh` before re-running.

Prefer a single invocation of `install-launcher.sh` over an inline `cp && chmod` composite: a single scripted path is easier for the user's permission allowlist to match.

## What the launcher does

```bash
exec env IS_DEMO=1 claude --rc --effort max --model claude-opus-4-7 "$@"
```

- **`IS_DEMO=1`** — undocumented Anthropic env var that hides the account email and organization from the welcome banner. Confirmed live in v2.1.116. Side effect: skips first-run onboarding prompts.
- **`--rc`** — hidden CLI flag.
- **`--effort max`** — deepest reasoning level.
- **`--model claude-opus-4-7`** — pins to Opus 4.7.

Extra arguments pass through, so the launcher is a drop-in for `claude`: `./claude.sh -c`, `./claude.sh "do the thing"`, `./claude.sh --worktree`, etc.

## Plugin auto-update

The launcher refreshes marketplace-installed plugins before exec'ing claude, throttled to at most once per hour via `~/.claude/.last-plugin-update`. Updates run *before* the `exec`, so they take effect on this same launch (the exec is the "restart required to apply" the `claude plugin update` help text mentions).

Coverage:

- **User-scope plugins** (the default install scope) — always updated.
- **Project-scope plugins** for the project the launcher was invoked from — updated only when `jq` is installed (used to filter out other projects' installs from `claude plugin list`). Without `jq`, the launcher silently falls back to user-scope-only via the human-readable list parser.
- **`--plugin-dir` locals are NOT touched.** Claude Code reads those from disk at every launch, so they're current with whatever the filesystem holds. Refresh them via `git pull` in your normal flow, or use `/reload-plugins` mid-session.

Force a refresh on the next launch:

```bash
rm ~/.claude/.last-plugin-update
```

To change the throttle window, edit `THROTTLE_SECONDS` in the installed `./claude.sh` (default: `$((60 * 60))`).

## Caveats

- `IS_DEMO` is undocumented. A future Claude Code release could rename or remove it, and the launcher will silently stop hiding the banner until the script is updated.
- `--rc` is a hidden flag; Anthropic may change it without notice.
- `--effort max` is token-expensive — for routine work on a metered plan, prefer `high`.
- Do not run `./claude.sh` from inside an active Claude Code session; nesting `claude` is not supported.
- The repo-local copy does **not** auto-update when the plugin's canonical launcher changes. If the template gets updated, re-run the skill to re-copy.
- The plugin auto-update is best-effort and silent on failure (network blip, marketplace unreachable, scope mismatch). Watch the launcher's stderr if you suspect an update isn't landing.
- Project-scope coverage requires `jq`. The fallback updates user-scope plugins only.
