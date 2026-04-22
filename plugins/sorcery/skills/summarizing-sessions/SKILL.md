---
name: summarizing-sessions
description: Use when the user wants Claude Code to summarize each session into a dated markdown file under `~/LLM_Summaries/YYYY-MM-DD/` — triggered by a SessionEnd hook, written by a detached Haiku call with a forced JSON schema. Installs the hook into the current repo's `.claude/settings.json`.
---

# Summarizing Sessions

Wires a SessionEnd hook into the current repo that, on each session end, forks a background Haiku call to summarize the just-ended transcript and writes the result to `~/LLM_Summaries/<date>/<date>@<time> <title>.md`.

## What to do

Run the plugin's installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/install-summary-hook.sh"
```

That reads the existing `.claude/settings.json` (creating it if missing), appends a SessionEnd entry pointing at the plugin's `summarize-on-end.sh`, and writes the result back through `dot-claude.sh` (Claude Code blocks direct `.claude/` writes via its native Write/Edit tools). Safe to run twice — the installer no-ops when a matching entry already exists.

Prefer a single invocation of `install-summary-hook.sh` over inline `jq`/`cp` composites: a single scripted path is easier for the user's permission allowlist to match.

## How the hook works

On session end, `summarize-on-end.sh`:

1. Exits early if `CLAUDE_SUMMARY_HOOK` is set (recursion guard — the spawned Haiku call has the var set, so its own SessionEnd doesn't re-summarize).
2. Self-forks via `nohup ... & disown` so the 5-15s Haiku call survives Claude Code exiting and the terminal closing.
3. Skips subagent transcripts — path contains `/subagents/` OR the first 50 lines carry `"isSidechain": true`. Without this, a single iteration that spawns N subagents ends up producing N+1 summaries in the same minute.
4. Extracts clean dialogue from the JSONL transcript via `jq` (user messages, assistant text, tool-call markers — thinking blocks and raw tool results omitted), capped at 150KB.
5. Runs `claude -p` with:
   - `--model claude-haiku-4-5-20251001`
   - `--json-schema` — forces a `{skip, title, body}` JSON object
   - `--system-prompt` — replaces CC's default so Haiku acts as an observer, not a chat assistant
   - `--no-session-persistence` — keeps the session list clean
6. If `skip=true` (model judged the session trivial), writes nothing. Otherwise hands `title` + `body` to `write-llm-summary.sh`, which drops the file at `~/LLM_Summaries/<date>/<stamp> <title>.md`.

Logs live at `~/LLM_Summaries/.summarize-on-end.log`.

## Reading back the summaries

`~/LLM_Summaries/` is plain markdown with no tooling lock-in — each day is a folder, each session a note. If the user uses Obsidian, the simplest integration is to open `~/LLM_Summaries/` as a vault directly, or add it as an additional folder in an existing vault. No sync step needed.

## Uninstall

Invoke the `using-dot-claude` skill and remove the SessionEnd entry whose `command` references `summarize-on-end.sh` from `.claude/settings.json`. Optionally delete `~/LLM_Summaries/` and `~/LLM_Summaries/.summarize-on-end.log` to wipe prior summaries and the debug log.

## Caveats

- **Per-repo, not user-global.** The hook lives in the current repo's `.claude/settings.json`. Run the installer in each repo where summaries are wanted.
- **Requires `jq` at install time AND hook-fire time.** Both the installer and the hook parse JSON with `jq`. If `jq` is later uninstalled, summaries silently stop — check `~/LLM_Summaries/.summarize-on-end.log` for errors.
- **Cost is small but not zero.** Each non-trivial summary is a Haiku call on up to ~150KB of transcript — typically well under $0.01 per session. Trivial sessions are skipped via the model's `skip=true` path.
- **`--json-schema` and `--no-session-persistence` are stable Claude Code flags but not contract-guaranteed.** A future CC release could rename or drop them; the hook will silently start failing until updated. Check `~/LLM_Summaries/.summarize-on-end.log` for errors.
- **Hook fires on every session end in the repo**, including short `-p` one-shots and interrupted sessions. Most of these get filtered by the subagent guard or the `skip=true` path, but expect occasional zero-value summaries in the daily folder.
