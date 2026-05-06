---
name: scaffolding-repos
description: Use when the user wants to set up a new repo with the sorcery day-one essentials in one shot — phrasings like "scaffold this repo", "bootstrap this repo", "initialize this repo with sorcery defaults", "set up the basics in this repo", "install everything". Bundles the universal-baseline installers behind one entry point and hands off to `following-best-practices` for any remaining gaps.
---

# Scaffolding Repos

Bundles the universal-baseline sibling-skill installers behind one entry point. Every step is idempotent; running the scaffold twice leaves the second run as a no-op.

The bundle is the universal baseline — what every repo wants on day one. Specialized workflows (LLM tasks, improvement loop, VM, learning tracks, fixture capture) are intentionally excluded; install those via their own skills when the project actually needs them.

## What's in the bundle

In install order. Commit-time guards lead so that, even if a later sub-installer fails partway, the user has the most load-bearing protection wired before they run their next `git commit` (and they typically run one shortly after scaffolding):

1. **Conventional-commits hook** — sibling skill `guarding-commits`. Wires `.githooks/commit-msg` to reject malformed subjects.
2. **Commit-message style hook** — sibling skill `writing-commit-messages`. Wires `.githooks/commit-msg` to enforce density and style (≤3 bullets, ≤20 words/bullet, no em dashes, no file paths).
3. **Disallowed-terms guard** — sibling skill `guarding-commits`. Wires `.githooks/pre-commit` and `.githooks/commit-msg` to scan diffs and messages against `commit-disallowed-terms.txt` (git-ignored).
4. **Periodic-upgrades hook** — sibling skill `enforcing-periodic-upgrades`. Wires `.githooks/pre-commit` to refuse commits when a recognised lockfile is older than `STALE_DAYS` (default 7).
5. **`./claude.sh`** — sibling skill `launching-claude`. Drops the launcher at the repo root.
6. **`./me.sh`** — sibling skill `claiming-authorship`. Drops the re-author script at the repo root.
7. **SessionEnd summary hook** — sibling skill `summarizing-sessions`. Wires `.claude/settings.json` to summarize each Claude Code session into `~/LLM_Summaries/<date>/...`.

Steps 5 and 6 skip if the target file already exists, so a customized `./claude.sh` or `./me.sh` is never clobbered. Steps 1–4 and 7 are idempotent on their own — the sub-installers detect existing wiring and no-op.

## What to do

Run the bundled installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/install-scaffold.sh"
```

It bails with a clear message if the working directory is not inside a git repository — `git init` first if that's the case.

After the bundle finishes, scan for remaining day-one gaps that aren't part of the universal baseline (README, starter scripts, observability, persisted test output, committed progress state, structured task workflow, wall-clock test ceiling, automated version bumps). Invoke the sibling skill `following-best-practices` for that scan; it walks the catalog top to bottom and surfaces the first one or two genuine gaps to propose as next steps.

When reporting completion to the user, mention:

- That `core.hooksPath` is per-clone — fresh clones need an activation step (lifecycle hook, `scripts/setup.sh`, or `pre-commit install`). The sibling skill `guarding-commits` documents the choices in *Activating for teammates*.
- That `commit-disallowed-terms.txt` was seeded with commented-out examples — they'll want to edit it to add the strings they actually want blocked.
- That `disallowed-commit-messages.txt` (a tracked sibling file the `writing-commit-messages` hook reads to forbid generic commit subjects across the team) is *not* created by the bundle — flag it as an opt-in if the project wants that policy.
- The `following-best-practices` scan results, if any gaps surfaced.

## What to do for partial scaffolds

If the user wants only a subset (e.g., "set up the launcher and the commit hooks but skip the SessionEnd summary"), don't run the bundled installer. Run the relevant sub-installers directly — each is documented in its own sibling skill's SKILL.md. The bundle is a convenience, not a contract.

If the user wants help deciding *which* subset, invoke the sibling skill `following-best-practices` first — it scans the repo and surfaces the actual gaps, so the partial scaffold targets what's missing rather than re-installing what's already there.

## How it works internally

`install-scaffold.sh` is a thin shell wrapper. It:

1. Resolves the git toplevel via `git rev-parse --show-toplevel` and `cd`s there. Bails with a clear error if the cwd isn't in a git repo.
2. For `./claude.sh` and `./me.sh`: checks for an existing file and skips if present. Otherwise calls the sibling installer (or inline `cp + chmod` for `me.sh`).
3. For each hook installer: calls the sibling installer unconditionally. Each one is independently idempotent — they detect existing wiring via marker comments (`# guarding-commits-check`, `# conventional-commit-check`, `# writing-commit-messages-check`, `# periodic-upgrades-check`) and skip duplicates.
4. For the SessionEnd hook: calls `install-summary-hook.sh`, which uses exact command-string match on `.claude/settings.json` to skip duplicates.
5. Prints a final summary listing what's installed and the three next-step nudges.

Everything is run sequentially, not in parallel — multiple installers touch the same `.githooks/pre-commit` and `.githooks/commit-msg` files, and parallel writes would race. The wrapper exits non-zero on the first sub-installer failure so the user sees the real error and can re-run after fixing.

## Caveats

- **`core.hooksPath` is per-clone, not per-repo.** Per *Activating for teammates* in `guarding-commits` — a fresh clone silently skips every hook the bundle installs until activation runs. The bundle handles the current clone; teammates need the activation baked into a setup script.
- **The bundle is opinionated about scope.** Specialized workflows (`using-llm-tasks`, `running-improvement-loops`, `running-claude-in-a-vm`, `learning-new-tech`, `capturing-test-fixtures`, `using-sf-symbols`) are deliberately excluded — invoke those skills directly when the project needs them. Adding everything would land scaffolding on repos that don't want it (LLM-task overhead on a one-off script, VM scaffolding on a Linux-only repo).
- **`./claude.sh` and `./me.sh` skip if the target file exists.** A customized launcher or claim script in the repo is preserved. To force a re-copy, delete the file first and re-run.
- **The SessionEnd summary hook is per-repo, not user-global.** It only fires on Claude Code sessions started inside the current repo. If the user wants summaries for every repo, they need to run the scaffold (or just `install-summary-hook.sh`) in each one.
- **No backwards-uninstall.** The bundle installs; it doesn't uninstall. To remove a step, follow the per-skill uninstall guidance in that sibling skill's SKILL.md (most are "delete the marker line from `.githooks/<hook>` or the entry from `.claude/settings.json`").

## Related skills

- `launching-claude`, `claiming-authorship`, `guarding-commits`, `writing-commit-messages`, `enforcing-periodic-upgrades`, `summarizing-sessions` — the sibling skills this bundle composes. Each one documents its own installer, what gets installed, and the per-skill caveats. Read those SKILL.md files when the user wants to understand or customize a single step.
- `following-best-practices` — invoked after the bundle finishes to scan for remaining day-one gaps that aren't part of the universal baseline.
- `using-dot-claude` — the SessionEnd hook installer routes its `.claude/settings.json` write through `dot-claude.sh`. The bundle inherits that plumbing transparently.
