---
name: guarding-commits
description: Use when the user wants to block commits whose staged diff OR commit message contains strings from a git-ignored allow/block list — e.g., personal emails, API key prefixes, "DO NOT COMMIT" markers, code-name project strings. Installs self-contained pre-commit and commit-msg hooks into the current repo and seeds a `commit-disallowed-terms.txt` file (which stays out of version control) with commented examples the user can turn on.
---

# Guarding Commits

Installs pre-commit and commit-msg hooks that refuse any commit whose **staged diff** OR **commit message** contains one of the strings in `commit-disallowed-terms.txt` at the repo root. Covering both surfaces means a term can't leak through a commit message (e.g. "fixed bug with the abcdef password") even when the diff is clean. The terms file is git-ignored so each dev keeps their own list.

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
5. Creates or extends `.githooks/pre-commit` (scans the staged diff) and `.githooks/commit-msg` (scans the message) — a fresh hook if none exists, otherwise a prepended call guarded by a `# guarding-commits-check` marker so repeated installs don't duplicate lines. The call is prepended (not appended) because a trailing `exec` in the existing hook would otherwise short-circuit the check.

When the installer finishes it prints next-step guidance for baking the per-clone activation into a setup script (see the *Activating for teammates* section below).

## Getting the user started on their term list

After the installer runs, the user typically wants help populating `commit-disallowed-terms.txt`. Pull candidate terms from the sibling skill `following-best-practices` if it covers the project type, and suggest starting small: one or two terms that would catch real past mistakes for this user is better than a long list that trains people to `--no-verify`. Sensible starter categories:

- **Personal identifiers** the user doesn't want leaking into a shared repo — personal email, phone, home address.
- **Obvious secret prefixes** *when the project isn't already covered by a dedicated secret scanner* — `sk-proj-`, `ghp_`, `AKIA`, `xoxb-`, `-----BEGIN PRIVATE KEY-----`.
- **"Don't ship this" markers** — `DO NOT COMMIT`, `TODO:remove`, debug `console.log(` patterns the user routinely adds while working.

The bundled `example-commit-disallowed-terms.txt` has these already written out (commented) as a starting point.

## Activating for teammates

`core.hooksPath` is per-clone local git config — **it is not inherited on clone**. A committed hook directory is a silent trap without an activation step. The installer handles the current clone; teammates need the activation baked into a script per the sibling skill `following-best-practices` (the *Setup script, not setup instructions* practice). In rough order of preference:

1. **Ecosystem lifecycle hook** that runs on dependency install — strongest because no separate step for the next person.
   - JS/TS (`package.json` exists): add a `prepare` script — `"prepare": "git config --get core.hooksPath >/dev/null 2>&1 || git config core.hooksPath .githooks"` — fires on every `bun install` / `npm install` / `pnpm install`.
   - Python (`pyproject.toml` or `requirements*.txt` exists): use the `pre-commit` framework's `pre-commit install` step in the project's standard setup flow.
2. **A committed `scripts/setup.sh`** (or root-level `setup.sh`) that runs `git config core.hooksPath .githooks`, with the README pointing at it once instead of listing git commands.
3. **A prose onboarding line in README / CONTRIBUTING** as a last resort — instructions in prose drift, get skipped, or get done out of order.

When asked to apply, detect by manifest: `package.json` → `prepare` hook; `pyproject.toml` or `requirements*.txt` → `pre-commit install`; otherwise create or extend `scripts/setup.sh`. The installer itself doesn't touch any of these — leave it as a deliberate follow-up so the user reviews the change.

## How the check works internally

`check-disallowed-terms.sh` is a pure-bash script that runs in one of two modes depending on how it's called:

1. Reads `commit-disallowed-terms.txt`. Strips `#`-prefixed comments and blank lines, trims leading/trailing whitespace. No config file or empty config → exit 0 silently (the hook is a no-op until the user opts in).
2. Picks the input lines to scan:
   - **Diff mode** (no args; called from `pre-commit`): runs `git diff --cached --unified=0 --no-renames --diff-filter=ACM` and walks the added (`+`) lines, tracking the current file via `+++ b/<path>` headers. `--no-renames` ensures a file moving into the repo is rescanned as new content, not skipped as a rename. Each match is reported against the file path.
   - **Message mode** (`--message FILE`; called from `commit-msg`): runs `git stripspace --strip-comments` on the message file and scans the remaining lines. Git's own `#`-prefixed lines are dropped because they don't land in the final commit. Each match is reported as "in commit message".
3. For each input line, runs each term through `grep -F -i` (fixed-string, case-insensitive). A term with spaces, regex metacharacters, or leading symbols works verbatim — no escaping required.
4. On any match, prints `guarding-commits: disallowed term 'X' found in <location>` to stderr and exits 1 at the end. Multiple violations in one commit are all listed before the exit.

In diff mode the scan is **added lines only**, not whole-file — legacy content already in a file that the commit happens to touch doesn't block unrelated work, and a newly-added file is naturally covered because every line of it appears as added content. In message mode the scan is the whole (stripped) commit message — any author-written line containing a term blocks the commit, whether it's subject, body, or trailer.

## Caveats

- **Terms can't start with `#`.** `#` at the start of a line is treated as a comment. If the user genuinely wants to block a `#`-prefixed string, they have to change the match logic or the term format — document this if it comes up.
- **Plain-string match, case-insensitive, not regex.** Fixed-string matching keeps the config format safe for strings containing spaces, slashes, quotes, etc. `grep -F -i` means a single term like `MyProject` also blocks `myproject` and `MYPROJECT` — intentional, so a casing slip doesn't let a term through. If the user asks for regex or case-sensitive matching, note that it requires a rewrite (and that false positives get people running `--no-verify` fast).
- **`core.hooksPath` is per-clone, not per-repo.** Per the *Activating for teammates* section — a fresh clone silently skips the hook until activation runs (lifecycle hook, `scripts/setup.sh`, etc.). The installer prints next-step guidance; the user still has to decide which form fits their project.
- **The hook is bypassable with `--no-verify`.** Inherent to all client-side git hooks. If the threat model needs server-side enforcement, this skill isn't the answer — direct the user to a pre-receive hook or CI-side scan.
- **Very large diffs are scanned in full.** No size cap. For monorepos doing occasional massive reformats, the check could noticeably slow a commit. Acceptable trade-off for now; if it bites, add a size guard.
- **Does not scan existing file content on rename.** `--no-renames` rewrites renames to add+delete, which means a rename WITHIN the repo (already-tracked file moving paths) reappears as added content and IS rescanned. A plain path-only rename of untouched content will therefore block if the existing content already contained a disallowed term — surprising but arguably correct.

## Related skills

- `following-best-practices` — the source of the *Setup script, not setup instructions* practice referenced in *Activating for teammates*.
- `using-dot-claude` — sibling installer pattern for hooks that live under `.claude/`. Not used here because git hooks are under `.githooks/`, not `.claude/`.
