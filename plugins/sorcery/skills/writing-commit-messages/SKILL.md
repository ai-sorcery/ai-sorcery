---
name: writing-commit-messages
description: Use when authoring a commit message (Claude is about to run `git commit`), or when the user wants to install commit-message style enforcement in a repo (phrasings like "set up commit-message style enforcement", "block bloated commit messages", "enforce concise commits"). Encodes a tight style — subject-only by default, hyphen-bullet bodies focused on concepts rather than files, hard caps on bullet count and bullet length, no em dashes anywhere. Ships a `commit-msg` hook that enforces the same rules.
---

# Writing Commit Messages

Most readers don't read commit message bodies. Aim subject-only by default. If a fact is worth elaborating, it usually belongs as a code comment near the affected code, not in the commit log.

This skill is two halves:

- A ruleset Claude follows when authoring commit messages.
- A `commit-msg` hook (`${CLAUDE_PLUGIN_ROOT}/check-commit-message.ts`) that enforces the same rules, with an installer (`${CLAUDE_PLUGIN_ROOT}/install-commit-style-hook.sh`) for new repos.

## Rules

### Subject

- Conventional-commits format: `type(scope)?: subject`. The sibling skill `guarding-commits` enforces the format itself; this skill defers to it.
- 72 characters or less.
- No trailing period.
- First word after `type:` is lowercase.
- Imperative mood: "add X", not "added X" or "adds X". Guideline only; the hook does not enforce.

### Body

The body is **optional**. Don't write one when the subject already says everything. When you do:

- Blank line separates subject and body.
- Hyphen bullets only. No prose paragraphs.
- 3 bullets or fewer. If you need more, the change probably wants to be split into separate commits.
- Each bullet 20 words or fewer.

Bullets explain non-obvious WHY or HOW. A bullet that just paraphrases the diff is dead weight; either the subject covers it, or the WHY belongs as a code comment.

### Both subject and body

- **No em dashes anywhere.** Em dashes encourage chained sub-clauses that bloat bullets and make subjects hard to scan in `git log --oneline`. Use a period and start a new sentence, or break the bullet into two bullets.
- **No file paths.** Any token containing a slash with no whitespace on either side counts. The diff already shows what changed; describe the concept.
- **No basenames of changed files.** "Add cat action to `dot-claude.sh`" is wrong. Name the concept ("dot-claude wrapper", "claim script", etc.), not the file.
- **No strings listed in `disallowed-commit-messages.txt`** at the repo root. Use this file to forbid overly-generic conventional-commits scopes (e.g., a top-level plugin name) that don't communicate which area of the codebase the commit touches. Format: one string per line, `#` for comments, case-insensitive substring match. The file is tracked (not git-ignored) so the policy is shared across contributors.

## What to do

### Authoring a commit message

Draft the subject first. Ask: does this need a body? If subject + diff tell the story, ship subject-only.

If you reach for a body, ask: could this fact be a code comment near the affected code? Usually yes; do that instead.

When a body is genuinely needed (cross-cutting decision, rationale that doesn't fit any single file), follow the rules above.

### Installing the hook in a new repo

Run the installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/install-commit-style-hook.sh"
```

The installer:

1. Sets `core.hooksPath=.githooks` for the current clone if it is unset.
2. Creates `.githooks/commit-msg` if missing, or appends a check line to it if it exists, guarded by a `# writing-commit-messages-check` marker so repeated installs don't duplicate lines.
3. The check line invokes `check-commit-message.ts` at the plugin's install path. When the plugin updates, re-run the installer to pick up the new path.

The hook fires on every `git commit` and blocks any commit that violates the rules, listing each violation with reason.

After installing, **verify end-to-end**:

```bash
git commit -m "feat: bad — subject"   # rejects (em dash)
git commit -m "feat: ok subject"      # accepts
```

Per the *Activating for teammates* section in the sibling skill `guarding-commits`, `core.hooksPath` is per-clone and not inherited on clone — bake the activation into a setup script for teammates.

## How it works internally

- The validator at `${CLAUDE_PLUGIN_ROOT}/check-commit-message.ts` receives the commit-message file path from git's `commit-msg` contract, strips comment lines and trailer blocks, then applies the rules.
- Staged file basenames come from `git diff --cached --name-only`. By the time `commit-msg` fires, `pre-commit` has already modified the index (e.g., auto-bumped plugin versions), so the basename set matches what the user will see in `git show`.
- Path-token detection uses a single regex, `(?<!\s)\/(?!\s)`, that flags any slash whose left and right neighbours are both non-whitespace (or string boundary). "X / Y" passes; "foo/bar" fails.
- Basename detection only considers basenames that include an extension OR are 6 characters or longer bare, so short generic names like `me` (from `me.sh`) or `loop` (from `loop/`) don't false-positive on common English.
- Em dash detection runs against the full stripped message text (subject + body), not per bullet.

## Caveats

- Requires `bun`. The validator and the installer both fail fast if it is missing.
- The hook validates only the first line of each bullet. Multi-line wrapped bullets are rare given the 20-word cap; if you wrap one, the subsequent lines escape word-count and basename checks.
- The hook reports — it does not auto-fix. The bad message stays in the local buffer for you to edit.
- The hook bakes an absolute path to the validator into `.githooks/commit-msg`. When the sorcery plugin updates to a new version, that path becomes stale until the installer is re-run.

## Related skills

- `guarding-commits` — sibling concern. It enforces conventional-commits format and term blocking; this skill enforces density and style. Install both for the full set.
- `following-best-practices` — home for new language-agnostic practices. The "concise commit messages" idea generalizes; if a future contributor wants to catalog it there too, that's compatible.
