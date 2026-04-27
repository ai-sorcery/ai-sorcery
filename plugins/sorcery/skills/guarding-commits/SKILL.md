---
name: guarding-commits
description: Use when the user wants to install a git-hook guard on commits — either (a) blocking strings from a git-ignored allow/block list (personal emails, API key prefixes, "DO NOT COMMIT" markers, code-name project strings) or (b) enforcing conventional commits (`type(scope): subject`; phrasings like "set up conventional commits", "enforce commit message format", "add a commit-msg hook for `feat:`/`fix:`/`chore:` prefixes"). Installs self-contained hooks under `.githooks/`; each guard has its own installer so users can opt into one or both.
---

# Guarding Commits

Two self-contained git-hook checks that block bad commits at write time:

- **Disallowed-terms guard** — refuses any commit whose **staged diff** OR **commit message** contains a string listed in `commit-disallowed-terms.txt` at the repo root. Covering both surfaces means a term can't leak through a commit message (e.g. "fixed bug with the abcdef password") even when the diff is clean. The terms file is git-ignored so each dev keeps their own list.
- **Conventional-commits guard** — refuses any commit whose subject doesn't match `type(scope): subject`. Keeps the log scannable, makes `git log --grep` reliable, and unlocks release tooling that keys off the prefix (semantic-release, release-please, changesets).

The two are independent: install one, the other, or both. They share the same `core.hooksPath` plumbing and the same activation rules for teammates (see *Activating for teammates*).

## Installing the disallowed-terms guard

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

When the installer finishes it prints next-step guidance for baking the per-clone activation into a setup script (see *Activating for teammates*).

### Getting the user started on their term list

After the installer runs, the user typically wants help populating `commit-disallowed-terms.txt`. Pull candidate terms from the sibling skill `following-best-practices` if it covers the project type, and suggest starting small: one or two terms that would catch real past mistakes for this user is better than a long list that trains people to `--no-verify`. Sensible starter categories:

- **Personal identifiers** the user doesn't want leaking into a shared repo — personal email, phone, home address.
- **Obvious secret prefixes** *when the project isn't already covered by a dedicated secret scanner* — `sk-proj-`, `ghp_`, `AKIA`, `xoxb-`, `-----BEGIN PRIVATE KEY-----`.
- **"Don't ship this" markers** — `DO NOT COMMIT`, `TODO:remove`, debug `console.log(` patterns the user routinely adds while working.

The bundled `example-commit-disallowed-terms.txt` has these already written out (commented) as a starting point.

## Installing the conventional-commits guard

Run the installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/guarding-commits/install-conventional-commits.sh"
```

It is idempotent. Re-running picks up an updated `conventional-commit-check.sh`.

The installer:

1. Sets `core.hooksPath` for the current clone if it is unset (same logic as the disallowed-terms installer). If `core.hooksPath` is already pointed somewhere non-default, it uses that existing directory.
2. Copies `conventional-commit-check.sh` into the hooks directory so the hook is **self-contained** — no path inside it resolves outside the repo, so teammates without the sorcery plugin still run the hook unchanged.
3. Creates or extends `.githooks/commit-msg` with the validator call, guarded by a `# conventional-commit-check` marker so repeated installs don't duplicate lines.

The validator enforces:

- Subject matches `type(scope): subject` (scope optional, lowercase alphanumerics plus `-`).
- If a body is present, the second line must be blank — otherwise the subject isn't visually separated and `git log --oneline` ends up showing the body bleed.
- Auto-generated subjects (`Merge`, `Revert`, `fixup!`, `squash!`) get a pass.

The accepted type list is overridable via the `CONVENTIONAL_TYPES` env var (comma-separated). Default: `feat,fix,refactor,docs,chore,test,perf,build,ci,style`. Tighten the list only when the project's release tooling actually distinguishes between types — otherwise the broad default keeps false rejects (and `--no-verify` reflexes) low.

After installing, **verify end-to-end**:

```bash
git commit -m "bogus"           # must reject
git commit -m "chore: verify"   # must accept
```

Invoking the script directly on a crafted message file isn't sufficient — it misses activation-path, execute-bit, and wrong-directory mistakes that only surface under the real trigger.

When reporting completion to the user, state the per-clone activation step explicitly so fresh clones don't inherit the dormant-hook trap unnoticed.

## Activating for teammates

`core.hooksPath` is per-clone local git config — **it is not inherited on clone**. A committed hook directory is a silent trap without an activation step. Each installer handles the current clone; teammates need the activation baked into a script per the sibling skill `following-best-practices` (the *Setup script, not setup instructions* practice). In rough order of preference:

1. **Ecosystem lifecycle hook** that runs on dependency install — strongest because no separate step for the next person.
   - JS/TS (`package.json` exists): add a `prepare` script — `"prepare": "git config --get core.hooksPath >/dev/null 2>&1 || git config core.hooksPath .githooks"` — fires on every `bun install` / `npm install` / `pnpm install`.
   - Python (`pyproject.toml` or `requirements*.txt` exists): use the `pre-commit` framework's `pre-commit install` step in the project's standard setup flow.
2. **A committed `scripts/setup.sh`** (or root-level `setup.sh`) that runs `git config core.hooksPath .githooks`, with the README pointing at it once instead of listing git commands.
3. **A prose onboarding line in README / CONTRIBUTING** as a last resort — instructions in prose drift, get skipped, or get done out of order.

When asked to apply, detect by manifest: `package.json` → `prepare` hook; `pyproject.toml` or `requirements*.txt` → `pre-commit install`; otherwise create or extend `scripts/setup.sh`. The installers themselves don't touch any of these — leave it as a deliberate follow-up so the user reviews the change.

## How the disallowed-terms check works internally

`check-disallowed-terms.sh` is a pure-bash script that runs in one of two modes depending on how it's called:

1. Reads `commit-disallowed-terms.txt`. Strips `#`-prefixed comments and blank lines, trims leading/trailing whitespace. No config file or empty config → exit 0 silently (the hook is a no-op until the user opts in).
2. Picks the input lines to scan:
   - **Diff mode** (no args; called from `pre-commit`): runs `git diff --cached --unified=0 --no-renames --diff-filter=ACM` and walks the added (`+`) lines, tracking the current file via `+++ b/<path>` headers. `--no-renames` ensures a file moving into the repo is rescanned as new content, not skipped as a rename. Each match is reported against the file path.
   - **Message mode** (`--message FILE`; called from `commit-msg`): runs `git stripspace --strip-comments` on the message file and scans the remaining lines. Git's own `#`-prefixed lines are dropped because they don't land in the final commit. Each match is reported as "in commit message".
3. For each input line, runs each term through `grep -F -i` (fixed-string, case-insensitive). A term with spaces, regex metacharacters, or leading symbols works verbatim — no escaping required.
4. On any match, prints `guarding-commits: disallowed term 'X' found in <location>` to stderr and exits 1 at the end. Multiple violations in one commit are all listed before the exit.

In diff mode the scan is **added lines only**, not whole-file — legacy content already in a file that the commit happens to touch doesn't block unrelated work, and a newly-added file is naturally covered because every line of it appears as added content. In message mode the scan is the whole (stripped) commit message — any author-written line containing a term blocks the commit, whether it's subject, body, or trailer.

## How the conventional-commits check works internally

`conventional-commit-check.sh` reads the commit-message file passed as `$1`, runs `git stripspace --strip-comments` to drop git's instructional lines, then:

1. If the first line starts with `Merge`, `Revert`, `fixup!`, or `squash!`, it exits 0 — those subjects are auto-generated by git and don't follow the conventional shape.
2. Builds a regex from `CONVENTIONAL_TYPES` (or the default list) and matches the first line against `^(types)(\(scope\))?: subject`. Scope is optional and limited to lowercase alphanumerics plus `-`.
3. If a body is present, the second line must be blank — keeps the subject visually separated so `git log --oneline` stays readable.

A non-match prints a clear error showing the expected shape, the type list, and the offending subject — then exits 1.

## Caveats

### Apply to both guards

- **`core.hooksPath` is per-clone, not per-repo.** Per *Activating for teammates* — a fresh clone silently skips the hook until activation runs (lifecycle hook, `scripts/setup.sh`, etc.). The installer prints next-step guidance; the user still has to decide which form fits their project.
- **The hook is bypassable with `--no-verify`.** Inherent to all client-side git hooks. If the threat model needs server-side enforcement, this skill isn't the answer — direct the user to a pre-receive hook or CI-side scan.

### Disallowed-terms specific

- **Terms can't start with `#`.** `#` at the start of a line is treated as a comment. If the user genuinely wants to block a `#`-prefixed string, they have to change the match logic or the term format — document this if it comes up.
- **Plain-string match, case-insensitive, not regex.** Fixed-string matching keeps the config format safe for strings containing spaces, slashes, quotes, etc. `grep -F -i` means a single term like `MyProject` also blocks `myproject` and `MYPROJECT` — intentional, so a casing slip doesn't let a term through. If the user asks for regex or case-sensitive matching, note that it requires a rewrite (and that false positives get people running `--no-verify` fast).
- **Very large diffs are scanned in full.** No size cap. For monorepos doing occasional massive reformats, the check could noticeably slow a commit. Acceptable trade-off for now; if it bites, add a size guard.
- **Does not skip rename content.** `--no-renames` rewrites renames to add+delete, which means a rename WITHIN the repo (already-tracked file moving paths) reappears as added content and IS rescanned. A plain path-only rename of untouched content will therefore block if the existing content already contained a disallowed term — surprising but arguably correct.

### Conventional-commits specific

- **Tightening the type list trains `--no-verify`.** A list narrower than the project's actual practice produces false rejects, which conditions devs to bypass the hook. Only restrict `CONVENTIONAL_TYPES` when the project's release tooling actually keys off specific types; otherwise the broad default is the safer choice.
- **Scope characters are conservative.** The regex requires lowercase alphanumerics plus `-`. Projects whose scopes use uppercase letters or `/` (e.g., `feat(API/v2):`) need to edit the regex. Surface this if the project's existing log already uses other scope characters.

## Related skills

- `following-best-practices` — catalogs both these guards (alongside other day-one practices) and points back here for installation.
- `using-dot-claude` — sibling installer pattern for hooks that live under `.claude/`. Not used here because git hooks are under `.githooks/`, not `.claude/`.
- `writing-commit-messages` — sibling concern. It enforces commit-message density and style (subject-only by default, hard caps on bullet count and length, no em dashes, no file paths). Install both for the full set of commit-time guards.
