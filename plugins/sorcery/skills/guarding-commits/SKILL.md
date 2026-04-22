---
name: guarding-commits
description: Use when the user wants to block commits that add lines containing strings from a git-ignored allow/block list — e.g., personal emails, API key prefixes, "DO NOT COMMIT" markers. Installs a self-contained pre-commit hook into the current repo and seeds a `commit-disallowed-terms.txt` file (which stays out of version control) with commented examples the user can turn on.
---

# Guarding Commits

Installs a pre-commit hook that refuses any commit whose staged diff adds a line containing one of the strings in `commit-disallowed-terms.txt` at the repo root. The terms file is git-ignored so each dev keeps their own list.

## What to do

Run the installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/guarding-commits/install-guarding-commits.sh"
```

It is idempotent. Re-running picks up an updated `check-disallowed-terms.sh` but leaves any existing `commit-disallowed-terms.txt` alone.

The installer:

1. Sets `core.hooksPath=.githooks` for the current clone if it is unset. If `core.hooksPath` is already pointed somewhere non-default, it uses that existing directory instead of forcing its own choice.
2. Copies `check-disallowed-terms.sh` into `.githooks/` so the hook is **self-contained** — no path inside it resolves outside the repo, so teammates who don't have the sorcery plugin can still run the hook.
3. Seeds `commit-disallowed-terms.txt` at the repo root from the bundled `example-commit-disallowed-terms.txt` (all entries commented out). If the file already exists, it is left as-is.
4. Adds `commit-disallowed-terms.txt` to `.gitignore` if absent.
5. Creates or extends `.githooks/pre-commit` — a fresh hook if none exists, otherwise a prepended call guarded by a `# guarding-commits-check` marker so repeated installs don't duplicate lines. The call is prepended (not appended) because a trailing `exec` in the existing hook would otherwise short-circuit the check.

When the installer finishes it prints an onboarding blurb the user should copy into README / CONTRIBUTING (see the *Activating for teammates* section below).

## Getting the user started on their term list

After the installer runs, the user typically wants help populating `commit-disallowed-terms.txt`. Pull candidate terms from the sibling skill `following-best-practices` if it covers the project type, and suggest starting small: one or two terms that would catch real past mistakes for this user is better than a long list that trains people to `--no-verify`. Sensible starter categories:

- **Personal identifiers** the user doesn't want leaking into a shared repo — personal email, phone, home address.
- **Obvious secret prefixes** *when the project isn't already covered by a dedicated secret scanner* — `sk-proj-`, `ghp_`, `AKIA`, `xoxb-`, `-----BEGIN PRIVATE KEY-----`.
- **"Don't ship this" markers** — `DO NOT COMMIT`, `TODO:remove`, debug `console.log(` patterns the user routinely adds while working.

The bundled `example-commit-disallowed-terms.txt` has these already written out (commented) as a starting point.

## Activating for teammates

Per the sibling skill `following-best-practices` (git-hooks activation guidance), `core.hooksPath` is per-clone local git config — **it is not inherited on clone**. A committed hook directory is a silent trap without an activation step. The installer handles the current clone; teammates need one of:

- An onboarding line in README / CONTRIBUTING: `After cloning: git config core.hooksPath .githooks`.
- A committed `scripts/setup.sh` that runs the same command, referenced in onboarding docs.
- Ecosystem tooling that auto-activates on install — Husky or Lefthook via a `package.json` `prepare` script for JS/TS projects; the `pre-commit` framework for Python.

Offer to add the onboarding line to the repo's README / CONTRIBUTING as a follow-up; the installer itself doesn't touch those files.

## How the check works internally

`check-disallowed-terms.sh` is a pure-bash script that:

1. Reads `commit-disallowed-terms.txt`. Strips `#`-prefixed comments and blank lines, trims leading/trailing whitespace. No config file or empty config → exit 0 silently (the hook is a no-op until the user opts in).
2. Runs `git diff --cached --unified=0 --no-renames --diff-filter=ACM` to get the staged diff with only added context. `--no-renames` ensures a file moving into the repo is rescanned as new content, not skipped as a rename.
3. Walks the diff, tracking the current file via `+++ b/<path>` headers, then for each `+<content>` line runs each term through `grep -F` (fixed-string). A term with spaces, regex metacharacters, or leading symbols works verbatim — no escaping required.
4. On any match, prints `guarding-commits: disallowed term 'X' found in <file>` to stderr and exits 1 at the end. Multiple violations in one commit are all listed before the exit.

The scan is **added lines only**, not whole-file. Legacy content already in a file that the commit happens to touch doesn't block unrelated work. A newly-added file is naturally covered because every line of it appears as added content in the diff.

## Caveats

- **Terms can't start with `#`.** `#` at the start of a line is treated as a comment. If the user genuinely wants to block a `#`-prefixed string, they have to change the match logic or the term format — document this if it comes up.
- **Plain-string match, not regex.** Intentional: keeps the config format safe for strings containing spaces, slashes, quotes, etc. If the user asks for regex, note that it requires a rewrite (and that false positives get people running `--no-verify` fast).
- **`core.hooksPath` is per-clone, not per-repo.** Per the *Activating for teammates* section — a fresh clone silently skips the hook until a dev runs `git config core.hooksPath .githooks` (or an equivalent auto-activator). The installer prints this in its final message; the user still has to decide how to surface it to teammates.
- **The hook is bypassable with `--no-verify`.** Inherent to all client-side git hooks. If the threat model needs server-side enforcement, this skill isn't the answer — direct the user to a pre-receive hook or CI-side scan.
- **Very large diffs are scanned in full.** No size cap. For monorepos doing occasional massive reformats, the check could noticeably slow a commit. Acceptable trade-off for now; if it bites, add a size guard.
- **Does not scan existing file content on rename.** `--no-renames` rewrites renames to add+delete, which means a rename WITHIN the repo (already-tracked file moving paths) reappears as added content and IS rescanned. A plain path-only rename of untouched content will therefore block if the existing content already contained a disallowed term — surprising but arguably correct.

## Related skills

- `following-best-practices` — the source of the git-hooks activation guidance baked into this skill's *Activating for teammates* section.
- `using-dot-claude` — sibling installer pattern for hooks that live under `.claude/`. Not used here because git hooks are under `.githooks/`, not `.claude/`.
