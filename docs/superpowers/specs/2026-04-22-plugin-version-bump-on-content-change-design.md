# Plugin version bump on content change

## Problem

The `pre-commit` hook in `.githooks/pre-commit` bumps the patch version of
`plugins/sorcery/.claude-plugin/plugin.json` on every commit, regardless of
whether the plugin's contents changed. Two issues:

1. Touching anything in the repo (README, docs, other plugin) causes a
   no-op version bump for `sorcery`, producing a noisy version sequence.
2. The recently added `plugins/sorcery-dev` plugin isn't wired in at all —
   its version is frozen at `0.1.0`.

## Goal

Each plugin's patch version auto-increments **iff** something under that
plugin's directory actually changed in the commit. New plugins added under
`plugins/` are picked up automatically without editing the hook.

## Approach

Move the bump logic out of the bash pre-commit hook and into a reusable
bun + TypeScript script at `scripts/bump-plugin-versions.ts`. The hook
becomes a thin wrapper that invokes the script.

**Discovery**: glob `plugins/*/.claude-plugin/plugin.json`. No hardcoded
plugin list.

**Change detection**: use `git diff --cached --name-only --diff-filter=ACMRD`
to list staged paths. For each plugin directory, the plugin is considered
changed if any staged path is under `plugins/<name>/` **except** the plugin's
own `plugin.json` (so editing metadata like `description` does not
self-trigger a bump).

**Bump**: read the plugin's `plugin.json`, increment the patch component of
`version`, write it back with `version` as the only modified field (other
fields — including any concurrent manual edits in the same commit — are
preserved), then `git add` the file so the new version lands in the commit.

No content hashing, no new fields in `plugin.json`. The schema stays
exactly as it is today.

## Files

- `scripts/bump-plugin-versions.ts` — new. Bun shebang, executable. Does the
  discovery + detection + bump described above. Exits 0 on success (whether
  or not anything was bumped) and non-zero only on unexpected errors (e.g.,
  malformed `version` string, unreadable `plugin.json`).
- `.githooks/pre-commit` — rewritten. Becomes `exec bun "$root/scripts/bump-plugin-versions.ts"`
  with the repo root resolved via `git rev-parse --show-toplevel`. The
  existing `jq` dependency goes away; `bun` replaces it.

## Edge cases

- **Fresh repo clone without bun**: the hook fails loudly with a message
  pointing at the install. Acceptable — everyone developing in this repo
  already has bun per the project setup.
- **Commit that stages only `plugins/<name>/.claude-plugin/plugin.json`
  (manual metadata edit)**: no bump triggered. Correct — the user is
  choosing not to bump.
- **Commit that stages both `plugin.json` (manual edit) and a skill file**:
  the skill change triggers the bump; the script reads the current (staged)
  `plugin.json`, updates only `version`, writes back. The manual edits to
  other fields survive.
- **New plugin added**: its `plugin.json` is among the staged files, which
  the script sees. If only `plugin.json` is staged (empty plugin), no bump.
  If other files are also staged, version bumps from whatever was written
  in `plugin.json`.
- **Rename within a plugin**: `--diff-filter=ACMRD` includes renames; both
  old and new paths fall under the plugin dir, so the bump triggers.
- **Cross-plugin commit**: each plugin is evaluated independently. Both can
  bump in the same commit.

## Non-goals

- Bumping minor/major versions automatically.
- Detecting semantically-meaningful vs trivial changes (e.g., whitespace-only).
- Validating the `version` field against semver beyond `major.minor.patch`.
