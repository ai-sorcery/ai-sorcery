---
name: enforcing-periodic-upgrades
description: Use when the user wants to install a pre-commit dependency-staleness check ("enforce periodic upgrades", "install the staleness hook", "nag me to bump deps", "block commits when bun.lock is old"), when the existing hook reports `[periodic-upgrades] Stale dependencies detected`, or when the user wants to do an open-ended dependency-refresh sweep ("make this repo current", "bump everything"). Installs a self-contained `.githooks/check-update-staleness.sh` and walks through the backup → upgrade → test → commit cycle.
---

# Enforcing Periodic Upgrades

A self-contained pre-commit check that refuses commits when any lockfile at the repo root has not been touched in more than `STALE_DAYS` days (default 7). The intent is to drag the next dependency-refresh sweep forward in time, before drift turns into a debugging session.

The check recognises lockfiles for bun, npm, yarn, pnpm, cargo, go modules, bundler, poetry, uv, pipenv, composer, swiftpm, and mix. It silently no-ops in any repo where none of those are present at the root. Subdirectory lockfiles (a typical monorepo with `apps/web/bun.lock`, `apps/api/Cargo.lock`) are not scanned — see *Caveats*.

## Installing

Run the installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/install-periodic-upgrades.sh"
```

It is idempotent. Re-running picks up an updated `check-update-staleness.sh` but never duplicates the hook wiring.

The installer:

1. Sets `core.hooksPath=.githooks` for the current clone if it is unset. If `core.hooksPath` is already pointed somewhere non-default, it uses that existing directory instead of forcing its own choice.
2. Copies `check-update-staleness.sh` into the hooks directory so the hook is **self-contained** — no path inside it resolves outside the repo, so teammates who don't have the sorcery plugin can still run the hook.
3. Creates or extends `.githooks/pre-commit` — a fresh hook if none exists, otherwise a prepended call guarded by a `# periodic-upgrades-check` marker so repeated installs don't duplicate lines. The call is prepended (not appended) because a trailing `exec` in the existing hook would otherwise short-circuit the check.

After installing, **verify end-to-end** by backdating a lockfile and trying to commit — see the installer's printed next-steps. Invoking the script directly isn't sufficient — it misses activation-path, execute-bit, and wrong-directory mistakes that only surface under the real trigger.

When reporting completion to the user, state the per-clone activation step explicitly so fresh clones don't inherit the dormant-hook trap unnoticed (see *Activating for teammates* in the sibling skill `guarding-commits` — the same plumbing applies here).

## When the hook fires

The hook prints:

```
==================================================================
[periodic-upgrades] Stale dependencies detected
==================================================================
The following lockfile(s) have not been touched in more than 7 days:
  bun.lock — last touched 12 days ago
...
```

When this fires, walk the user through the cycle below. Surface things in order; stop at the first sign that the upgrade broke something and treat that as the real work.

### 1. Back up anything irreplaceable first

If the repo has a database, a cache, or any file in tracked or git-ignored state that the test suite touches, snapshot it before bumping. Dependency upgrades have shipped breaking data-format changes more than once — Turso/libSQL minor versions, ORM migrations, ICU collation churn. Two minutes of `cp` saves an hour of "where did the rows go." Skip this only if you're certain there's nothing on disk worth keeping.

### 2. Bump the runtime first, then the deps

When the project ships its own runtime (Bun, Node, Deno, Ruby, Python, Go), upgrade that *before* the dependency manager. Order matters — a runtime bump can change how `update` resolves, can pull a newer bundled TypeScript that flags new lint patterns, or can introduce ABI changes that the package manager would otherwise rebuild against the old runtime.

Quick paths by ecosystem (use whichever applies):

| Ecosystem | Upgrade command(s) |
| --- | --- |
| bun | `bun upgrade && bun update` |
| npm | `npm update` (or `ncu -u && npm install` for major bumps) |
| yarn | `yarn upgrade` |
| pnpm | `pnpm update` |
| cargo | `cargo update` |
| go | `go get -u ./... && go mod tidy` |
| bundler | `bundle update` |
| poetry | `poetry update` |
| uv | `uv lock --upgrade` |
| pipenv | `pipenv update` |
| composer | `composer update` |
| swiftpm | `swift package update` |
| mix (Elixir) | `mix deps.update --all` |

If the user has multiple lockfiles in one repo (a Tauri app, a polyglot monorepo), bump each one — the hook lists every stale lockfile, not just the worst.

### 3. Run the tests against whatever wrapper the repo uses

Not the bare runner. If the repo ships a `./test.sh`, `./run.sh test`, `make test`, or similar, use it — it usually persists output to disk and enforces wall-clock budgets that matter after a runtime bump. A bare `bun test` / `pytest` / `cargo test` skips those guarantees.

### 4. Spot-check the live paths the test suite doesn't cover

Boot the dev server. Click around for thirty seconds. If the project has a database driver, prove it still opens the live data file. Test suites tend to mock the things that break first after an upgrade — connection pools, codec layers, native bindings.

### 5. Bump the linter / formatter / type-checker if a new minor is out

Major versions of biome, eslint, ruff, rubocop, clippy, etc. tend to add rules that flag patterns the codebase tolerates. Run the lint pass and either fix the new flags or add explicit overrides — auto-applying `--unsafe`/`--fix` blanket fixes after a major rule churn is how subtle behavior changes slip in.

### 6. Record what you did

A one-line note in the project's progress file (`PLAN.md`, `STATUS.md`, an LLM task — whatever the project uses): which packages bumped, which tests broke, what was patched. The next round of upgrades inevitably surfaces a regression; the previous note is what makes the regression diagnosable. The sibling skill `using-llm-tasks` is the natural home for this if the repo is set up for it.

### 7. Commit

Stage the lockfile (and any other touched files) and commit. The hook will pass — the lockfile mtime is now fresh.

## Bypass

Three escape hatches, in increasing severity:

- **Widen the threshold for one commit.** `STALE_DAYS=14 git commit ...` — useful when you genuinely checked recently and `bun update` had nothing to bump.
- **Mark the lockfile fresh without an upgrade.** `touch <lockfile>` — useful when the lockfile mtime is stale only because the package manager left it untouched on a no-op `update`.
- **Skip the hook entirely.** `git commit --no-verify ...` — the nuclear option. If you reach for this more than once or twice, the threshold is mis-tuned for the workflow; raise `STALE_DAYS` or weaken the trigger rather than train the muscle memory.

## How the check works internally

`check-update-staleness.sh` is a pure-bash script:

1. Walks a built-in list of lockfile names, looking for each in the repo root.
2. If none are present, exits 0 silently — the hook is a no-op until the project introduces a lockfile the script recognises.
3. For each lockfile that exists, computes age in seconds from its mtime (using `stat -f "%m"` on macOS, `stat -c "%Y"` elsewhere — picked once at startup, not per call).
4. Collects every lockfile whose age exceeds `STALE_DAYS * 86400` seconds.
5. If the collection is empty, exits 0. Otherwise, prints the list and the quick-path guidance and exits 1.

The check is **per-lockfile, fail-on-any** — in a polyglot repo, a stale Cargo.lock blocks a commit even if bun.lock is fresh. This matches the spirit of "enforce upgrades": the goal is to keep every ecosystem moving, not to let one ecosystem's activity mask another's drift. If a project has a deliberately-frozen lockfile (a vendored dependency, a pinned-by-policy build), the right response is to `touch` it on the days you've verified it's still intentionally pinned.

## Caveats

- **Bypassable with `--no-verify`.** Inherent to all client-side git hooks. If the threat model needs server-side enforcement, this skill isn't the answer — direct the user to a CI-side staleness check.
- **`core.hooksPath` is per-clone, not per-repo.** A fresh clone silently skips the hook until activation runs. The installer prints next-step guidance for baking activation into a setup script; the user still has to decide which form fits their project. The sibling skill `guarding-commits` documents the same plumbing in more depth.
- **Lockfile mtime, not lockfile content, is what's checked.** A `git checkout` of an old branch can suddenly look "fresh" because the working-tree mtime updates even though the deps inside the file are ancient. Inverse: a `bun install` that produces zero lockfile changes still leaves the mtime at its old value, so the hook keeps firing until the user runs `touch`. The mtime is the right signal for "did somebody recently look at this," but not for "are these deps current" — different question.
- **No major-version pull.** `bun update` / `npm update` / `cargo update` etc. respect the version-range constraints already in the manifest. To pull a major bump, the user has to do `npm install pkg@latest` (or the equivalent) by hand, then re-run the suite. The skill doesn't automate that — major bumps are intentional decisions, not hook-driven sweeps.
- **The check fires on every commit until the lockfile mtime moves.** If a long-lived branch has been parked for weeks, the first commit after returning will block. That's the intended behavior — the alternative is silently shipping multi-week-old deps into a release branch.
- **Default `STALE_DAYS=7` is a guess.** Tighten for security-sensitive projects; loosen for slow-moving libraries that don't get touched daily. Persistent overrides go in a setup script that exports `STALE_DAYS` from the env, not in the hook itself.
- **Repo root only.** Only lockfiles at the root are scanned. A monorepo with all its lockfiles in subdirectories silently passes this check. Workarounds: stash a sentinel root-level lockfile (`touch <name>` after each subdir update), or extend the candidates list in `check-update-staleness.sh` with explicit subdirectory paths once the layout stabilises.

## Related skills

- `guarding-commits` — sibling skill that wires content-based guards (disallowed terms, conventional commits) into the same `.githooks/` infrastructure. The two compose cleanly; install both for the full set of pre-commit guards.
- `following-best-practices` — catalogs the *Periodic dependency updates* practice and points back here for installation.
- `using-llm-tasks` — natural home for the upgrade-record entry from step 6 of the cycle, if the repo is already on the markdown-task workflow.
- `using-dot-claude` — sibling installer pattern for hooks that live under `.claude/`. Not used here because git hooks are under `.githooks/`, not `.claude/`.
