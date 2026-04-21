---
name: following-best-practices
description: Use when the user asks whether a project is set up well, what to improve, whether there's "low-hanging fruit," or what day-one practices a repo is missing. Also used by sibling skills (e.g., using-llm-tasks) to source a seed task for a fresh repo. Catalogs language-agnostic practices that compound if installed early and are painful to retrofit.
---

# Following Best Practices

Things that are cheap on day one, expensive in month six. Each entry names the practice, what to check for in the current repo, and — if it's missing — the shape of a task that would install it.

When invoked, Claude should scan the current repo against each entry in order and surface the first one or two genuine gaps. Prefer concrete gaps over aspirational ones. If everything's present, say so.

## 1. Observability from day one

Every LLM call, outbound HTTP request, and long-running operation runs through a single wrapper that emits a paired START/DONE log with a correlated ID, so cost, timing, and failures can be reconstructed after the fact. Retrofit is painful because call sites are scattered; day-one it's one helper everything flows through.

- **Check for:** a wrapper that every external call goes through. Grep for paired START/DONE log lines sharing an ID, or persisted request/response archives. If only one category is instrumented (LLM but not HTTP, or vice versa), that's a gap.
- **Seed task shape:** add a wrapper that logs the start of an operation, runs it, and logs the end with elapsed time and a correlated ID; wire it around the two or three highest-traffic call sites.

## 2. Test output persisted to a file

A wrapper around the test runner that tees the suite's output to a committed-location file. Lets a long session re-read the output in multiple passes without paying the cost of re-running.

- **Check for:** a wrapper script (or Makefile / Just target / npm script) that runs the suite and writes its output to disk. Plain invocations — `bun test`, `npm test`, `pytest`, `go test` — alone don't count.
- **Seed task shape:** write a thin wrapper that runs the suite and pipes through `tee` to a file under the project's data / log directory; update the agent-facing docs (CLAUDE.md / AGENTS.md) to point at it.

## 3. Committed progress state

A committed markdown file (`PLAN.md`, `ROADMAP.md`, `STATUS.md` — whatever the project prefers) that tracks done / in-progress / not-started, updated as work moves. Any new session — human or agent — picks up where the last one left off.

- **Check for:** a committed file with visible status sections. A README "roadmap" buried below the fold doesn't count; this file should be the first thing a returning session opens.
- **Seed task shape:** create the file with three sections (done / in-progress / not-started) and seed it from recent commits and open issues.

## 4. Structured task workflow

Agent work lives in version-controlled markdown with a known lifecycle, not in chat transcripts. Each task is a file; progress is appended to the file; completion is a filename change.

- **Check for:** an `llm-tasks/` (or similar) directory with in-flight task files.
- **Seed task shape:** install the workflow — see the sibling skill `using-llm-tasks`, which handles this end-to-end.

## 5. Wall-clock test ceiling

A hard cap on total test-suite runtime — seconds, not minutes — enforced in a post-run hook or a tight CI timeout. Forces the suite to stay fast; surfaces bloat the moment it lands instead of six months later.

- **Check for:** a ceiling assertion in test setup/teardown, or a CI timeout tuned low enough to notice drift.
- **Seed task shape:** add a post-run check that records wall-clock time and fails if it exceeds the ceiling; set the ceiling at 20 seconds or 1.2× current runtime, whichever is greater.

## 6. Automated version bumps

Any version number that lives in a committed file (`package.json`, `pyproject.toml`, `plugin.json`, a `VERSION` file, a version constant in code) gets bumped automatically — by a pre-commit hook, a CI step, or a release tool (semantic-release, changesets, release-please). Manual bumps drift, get forgotten in the rush to merge, and add noise to PR diffs.

- **Check for:** a pre-commit hook, CI job, or release-tool config that mutates the version on commit or merge. Skim recent commits — if half touch the version and half don't, the process is manual.
- **Seed task shape:** add a pre-commit hook (or CI step) that bumps the version on every commit touching the versioned artifact; match the project's convention (semver, calver, monotonic integer).

## 7. Conventional commits enforced by a hook

Commit subjects follow `type(scope): subject`, enforced by a git `commit-msg` hook. Keeps the log scannable, makes `git log --grep` reliable, and unlocks release tooling that keys off the prefix (semantic-release, release-please, changesets).

- **Check for:** a `commit-msg` hook (in `.githooks/` or wherever `core.hooksPath` points) that rejects malformed subjects. Skim the last 20 commit subjects — if prefixes drift (`fix:` vs `Fix:` vs `bugfix:` vs bare sentences), enforcement isn't in place.
- **Seed task shape:**
  - **Copy the validator into the repo.** Put the plugin's `conventional-commit-check.sh` into `.githooks/` — inlined inside `commit-msg` for a small hook, or as a sibling script the hook calls. **The hook must be self-contained: no path in it should resolve outside the repository.** A hook that `exec`'s `${CLAUDE_PLUGIN_ROOT}/...` silently no-ops on any clone without the plugin installed and rots on plugin version bump. The plugin's own repo is the one exception — pointing at the in-repo script is fine there because it's committed alongside the hook.
  - **Activate the hooks directory.** `core.hooksPath` is local git config, not inherited on clone, so a committed-but-dormant hook is a silent trap. Pick one: commit a `scripts/setup.sh` that runs `git config core.hooksPath .githooks` and reference it in README / CONTRIBUTING; or add an onboarding line (`After cloning: git config core.hooksPath .githooks`) to contributor / agent-facing docs; or use ecosystem tooling that auto-activates (Husky or Lefthook via `package.json`'s `prepare` script for JS/TS; `pre-commit` for Python).
  - **Verify end-to-end.** Stage a trivial change, then run `git commit -m "bogus"` (must reject) and `git commit -m "chore: verify hook"` (must accept). Invoking the script directly on crafted message files isn't sufficient — it misses activation-path, execute-bit, and wrong-directory mistakes.
  - Accepted types are overridable via the `CONVENTIONAL_TYPES` env var (comma-separated); merge / revert / fixup! / squash! subjects auto-pass.
  - When reporting completion, state the per-clone activation step explicitly so fresh clones don't inherit the dormant-hook trap unnoticed.

## 8. Parse, don't validate

Use branded / newtype'd types (`UsdAmount`, `EmailAddress`, `FiniteNumber`) so invalid states can't be represented. Parsing happens once at the system boundary; internal code trusts the type.

- **Check for:** branded types in the type system, parser functions at the boundary (`parseAmount`, `parseEmail`), no `number` / `string` sprinkled through business logic for domain values.
- **Seed task shape:** pick one domain value (e.g., monetary amounts) and introduce a branded type + parser; migrate one or two call sites as the template.

## 9. Transient vs. permanent errors

Errors carry an explicit tag saying whether retrying could succeed. Without it, retry logic is heuristic and either over-retries (wasting budget on content errors) or under-retries (giving up on a flaky network).

- **Check for:** an error shape that includes a `transient: true` / `retryable: true` flag, or discriminated-union error types that encode the same thing.
- **Seed task shape:** introduce `{ transient: boolean }` on the project's error type; classify existing error sites; update the one retry loop that matters most.

## 10. Cheap before expensive

When multiple checks or operations produce the same outcome, run the cheap ones first so the expensive ones only see survivors. Applies to validation cascades, test ordering, pipeline stages, and UI render paths.

- **Check for:** a filter / validation cascade that short-circuits (e.g., regex filter before LLM call, cached lookup before DB query).
- **Seed task shape:** pick the pipeline that burns the most wall-clock / money; add a cheap pre-filter (regex, hash lookup, or cached negative result) in front of the expensive step.

## How to use this list

Scan top to bottom. Stop at the first genuine gap and propose it as the next task; at most, surface two. Don't propose a gap that's already partially addressed — "observability exists for LLM calls but not HTTP" is a refinement, not a day-one gap.

For any practice that installs a mechanism (hooks, CI steps, wrappers, tooling): the seed task isn't done at "script exists." Keep the install self-contained — no paths resolving outside the repo, or the mechanism silently no-ops on clones. Check that it activates on a fresh clone, not just the author's machine; when activation requires per-clone setup (`core.hooksPath`, a `prepare` script, etc.), surface the one-time step in the completion message rather than leaving it implicit. And verify end-to-end by triggering the real code path, not by unit-testing the handler — unit tests miss activation-path, mode-bit, and wrong-directory mistakes that only surface under the real trigger.

If another skill invoked this one for seed inspiration (e.g., `using-llm-tasks` picking the first task for a fresh repo), return the top-ranked gap along with the "Seed task shape" text, adapted to the specific repo. When consulted by `using-llm-tasks`, skip practice #4 — that's the workflow being installed — and pick the next gap instead.
