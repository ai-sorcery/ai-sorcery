---
name: following-best-practices
description: Use when the user asks whether a project is set up well, what to improve, whether there's "low-hanging fruit," or what day-one practices a repo is missing. Also used by sibling skills (e.g., using-llm-tasks) to source a seed task for a fresh repo. Catalogs language-agnostic practices that compound if installed early and are painful to retrofit.
---

# Following Best Practices

Things that are cheap on day one, expensive in month six. Each entry names the practice, what to check for in the current repo, and — if it's missing — the shape of a task that would install it.

When invoked, Claude should scan the current repo against each entry in order and surface the first one or two genuine gaps. Prefer concrete gaps over aspirational ones. If everything's present, say so.

## 1. Repo has a README

A `README.md` (or `README.rst` / `README.txt`) at the repo root with real content answers "what is this / how do I run it / how is it organized" for a returning human or a fresh agent before they've opened anything else. Everyone-has-one practice, but its absence shows up more often than expected on internal tools and throwaway-turned-serious repos — and when it's missing, every other doc and skill has nothing to link back to.

- **Check for:** a `README.md` at the root with non-trivial content. A one-line file, a template with only placeholder sections, or a `README` that hasn't been touched since `git init` counts as missing.
- **Seed task shape:** draft a short README with three sections — what the project is, how to run it locally, how the codebase is organized. Seed content from the manifest (`package.json` / `pyproject.toml` / `Cargo.toml`) and the five most recent commits. Keep it tight — a three-paragraph README that stays true beats a ten-section template that rots.

## 2. Starter scripts at the repo root

Conventional thin wrappers answer the three setup questions at a glance: `./run.sh` for local development, `./deploy.sh` for shipping, `./build.sh` for producing artifacts. Each is a shallow delegation to whatever the project already uses — `npm run dev`, `cargo run`, `docker compose up`, a Makefile target, a CI command — not a re-implementation. The payoff is uniformity: anyone landing in the repo can try `./run.sh` before searching for the right invocation.

- **Check for:** executable `run.sh` / `deploy.sh` / `build.sh` at the repo root that actually do something. An empty file, a stub that prints "TODO," or a leftover `echo "hello"` counts as missing. A one-liner wrapper around `npm start` is fine.
- **Seed task shape:** add the missing scripts as thin wrappers around what the project already uses; mark them executable; reference them in the README so they're discoverable. Skip `deploy.sh` if the project genuinely has no deploy step (a library, a script collection) — two real scripts beat three with a placeholder.

## 3. Setup script, not setup instructions

Per-clone setup — git config (`core.hooksPath`), env priming, dependency install, hook activation — lives in a script the next person *runs*, not a README list they're expected to *follow*. A `scripts/setup.sh` (or the ecosystem equivalent: a `package.json` `prepare` lifecycle, `pre-commit install` for Python, a Makefile target) either runs cleanly or shows you the exact line that failed. Prose instructions guarantee something gets skipped, mistyped, or done out of order.

- **Check for:** a script (or ecosystem lifecycle hook) that handles the per-clone setup. Multiple "after cloning, run X / Y / Z" prose bullets in the README count as missing. The strongest form is an automatic lifecycle hook (`package.json` `prepare`, `.pre-commit-config.yaml`) that runs on dependency install — no extra step for the next person at all.
- **Seed task shape:** consolidate the existing per-clone steps into `scripts/setup.sh`; mark it executable; replace the README's per-clone bullets with a single "Run `./scripts/setup.sh` after cloning". For repos already running `npm install` / `bun install` / `pip install`, prefer wiring the steps into the lifecycle hook so the script runs implicitly.

## 4. Observability from day one

Every LLM call, outbound HTTP request, and long-running operation runs through a single wrapper that emits a paired START/DONE log with a correlated ID, so cost, timing, and failures can be reconstructed after the fact. Retrofit is painful because call sites are scattered; day-one it's one helper everything flows through.

- **Check for:** a wrapper that every external call goes through. Grep for paired START/DONE log lines sharing an ID, or persisted request/response archives. If only one category is instrumented (LLM but not HTTP, or vice versa), that's a gap.
- **Seed task shape:** add a wrapper that logs the start of an operation, runs it, and logs the end with elapsed time and a correlated ID; wire it around the two or three highest-traffic call sites.

## 5. Test output persisted to a file

A wrapper around the test runner that tees the suite's output to a committed-location file. Lets a long session re-read the output in multiple passes without paying the cost of re-running.

- **Check for:** a wrapper script (or Makefile / Just target / npm script) that runs the suite and writes its output to disk. Plain invocations — `bun test`, `npm test`, `pytest`, `go test` — alone don't count.
- **Seed task shape:** write a thin wrapper that runs the suite and pipes through `tee` to a file under the project's data / log directory; update the agent-facing docs (CLAUDE.md / AGENTS.md) to point at it.

## 6. Committed progress state

A committed markdown file (`PLAN.md`, `ROADMAP.md`, `STATUS.md` — whatever the project prefers) that tracks done / in-progress / not-started, updated as work moves. Any new session — human or agent — picks up where the last one left off.

- **Check for:** a committed file with visible status sections. A README "roadmap" buried below the fold doesn't count; this file should be the first thing a returning session opens.
- **Seed task shape:** create the file with three sections (done / in-progress / not-started) and seed it from recent commits and open issues.

## 7. Structured task workflow

Agent work lives in version-controlled markdown with a known lifecycle, not in chat transcripts. Each task is a file; progress is appended to the file; completion is a filename change.

- **Check for:** an `llm-tasks/` (or similar) directory with in-flight task files.
- **Seed task shape:** install the workflow — see the sibling skill `using-llm-tasks`, which handles this end-to-end.

## 8. Wall-clock test ceiling

A hard cap on total test-suite runtime — seconds, not minutes — enforced in a post-run hook or a tight CI timeout. Forces the suite to stay fast; surfaces bloat the moment it lands instead of six months later.

- **Check for:** a ceiling assertion in test setup/teardown, or a CI timeout tuned low enough to notice drift.
- **Seed task shape:** add a post-run check that records wall-clock time and fails if it exceeds the ceiling; set the ceiling at 20 seconds or 1.2× current runtime, whichever is greater.

## 9. Automated version bumps

Any version number that lives in a committed file (`package.json`, `pyproject.toml`, `plugin.json`, a `VERSION` file, a version constant in code) gets bumped automatically — by a pre-commit hook, a CI step, or a release tool (semantic-release, changesets, release-please). Manual bumps drift, get forgotten in the rush to merge, and add noise to PR diffs.

- **Check for:** a pre-commit hook, CI job, or release-tool config that mutates the version on commit or merge. Skim recent commits — if half touch the version and half don't, the process is manual.
- **Seed task shape:** add a pre-commit hook (or CI step) that bumps the version on every commit touching the versioned artifact; match the project's convention (semver, calver, monotonic integer).

## 10. Conventional commits enforced by a hook

Commit subjects follow `type(scope): subject`, enforced by a git `commit-msg` hook. Keeps the log scannable, makes `git log --grep` reliable, and unlocks release tooling that keys off the prefix (semantic-release, release-please, changesets).

- **Check for:** a `commit-msg` hook (in `.githooks/` or wherever `core.hooksPath` points) that rejects malformed subjects. Skim the last 20 commit subjects — if prefixes drift (`fix:` vs `Fix:` vs `bugfix:` vs bare sentences), enforcement isn't in place.
- **Seed task shape:**
  - **Copy the validator into the repo.** Put the plugin's `conventional-commit-check.sh` into `.githooks/` — inlined inside `commit-msg` for a small hook, or as a sibling script the hook calls. **The hook must be self-contained: no path in it should resolve outside the repository.** A hook that `exec`'s `${CLAUDE_PLUGIN_ROOT}/...` silently no-ops on any clone without the plugin installed and rots on plugin version bump. The plugin's own repo is the one exception — pointing at the in-repo script is fine there because it's committed alongside the hook.
  - **Activate the hooks directory via a setup script** (per the *Setup script, not setup instructions* practice). `core.hooksPath` is local git config, not inherited on clone, so a committed-but-dormant hook is a silent trap. Strongest: a `package.json` `prepare` script (`"prepare": "git config --get core.hooksPath >/dev/null 2>&1 || git config core.hooksPath .githooks"`) for JS/TS, or `pre-commit install` for Python — both run on dependency install. Fallback: a `scripts/setup.sh` referenced once in the README. A bare onboarding line in CONTRIBUTING is the last resort and rots fast.
  - **Verify end-to-end.** Stage a trivial change, then run `git commit -m "bogus"` (must reject) and `git commit -m "chore: verify hook"` (must accept). Invoking the script directly on crafted message files isn't sufficient — it misses activation-path, execute-bit, and wrong-directory mistakes.
  - Accepted types are overridable via the `CONVENTIONAL_TYPES` env var (comma-separated); merge / revert / fixup! / squash! subjects auto-pass.
  - When reporting completion, state the per-clone activation step explicitly so fresh clones don't inherit the dormant-hook trap unnoticed.

## 11. Parse, don't validate

Use branded / newtype'd types (`UsdAmount`, `EmailAddress`, `FiniteNumber`) so invalid states can't be represented. Parsing happens once at the system boundary; internal code trusts the type.

- **Check for:** branded types in the type system, parser functions at the boundary (`parseAmount`, `parseEmail`), no `number` / `string` sprinkled through business logic for domain values.
- **Seed task shape:** pick one domain value (e.g., monetary amounts) and introduce a branded type + parser; migrate one or two call sites as the template.

## 12. Transient vs. permanent errors

Errors carry an explicit tag saying whether retrying could succeed. Without it, retry logic is heuristic and either over-retries (wasting budget on content errors) or under-retries (giving up on a flaky network).

- **Check for:** an error shape that includes a `transient: true` / `retryable: true` flag, or discriminated-union error types that encode the same thing.
- **Seed task shape:** introduce `{ transient: boolean }` on the project's error type; classify existing error sites; update the one retry loop that matters most.

## 13. Cheap before expensive

When multiple checks or operations produce the same outcome, run the cheap ones first so the expensive ones only see survivors. Applies to validation cascades, test ordering, pipeline stages, and UI render paths.

- **Check for:** a filter / validation cascade that short-circuits (e.g., regex filter before LLM call, cached lookup before DB query).
- **Seed task shape:** pick the pipeline that burns the most wall-clock / money; add a cheap pre-filter (regex, hash lookup, or cached negative result) in front of the expensive step.

## How to use this list

Scan top to bottom. Stop at the first genuine gap and propose it as the next task; at most, surface two. Don't propose a gap that's already partially addressed — "observability exists for LLM calls but not HTTP" is a refinement, not a day-one gap.

For any practice that installs a mechanism (hooks, CI steps, wrappers, tooling): the seed task isn't done at "script exists." Keep the install self-contained — no paths resolving outside the repo, or the mechanism silently no-ops on clones. Check that it activates on a fresh clone, not just the author's machine; when activation requires per-clone setup (`core.hooksPath`, a `prepare` script, etc.), bake it into the project's setup script (per the *Setup script, not setup instructions* practice) rather than documenting it as a prose step the next person has to follow. And verify end-to-end by triggering the real code path, not by unit-testing the handler — unit tests miss activation-path, mode-bit, and wrong-directory mistakes that only surface under the real trigger.

If another skill invoked this one for seed inspiration (e.g., `using-llm-tasks` picking the first task for a fresh repo), return the top-ranked gap along with the "Seed task shape" text, adapted to the specific repo. When consulted by `using-llm-tasks`, skip the "Structured task workflow" practice — that's the workflow being installed — and pick the next gap instead.
