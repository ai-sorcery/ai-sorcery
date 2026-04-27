---
name: demoing-sorcery-skills
description: Use when the user wants to run a screen-recordable end-to-end walkthrough of every public-facing sorcery skill — typical phrasings "run the sorcery demo", "let's record the demo", "walk through every skill", "demo all the skills".
---

# Demoing Sorcery

A scripted walkthrough that exercises every public-facing skill under `plugins/sorcery/skills/` in one coherent narrative the user can record. The spine is **a developer setting up to build snippet-box** — a tiny TypeScript CLI that stores code snippets on disk in `data/snippets.json` and exposes `add` / `list` / `show`. Every step lends toward that build: scaffolding the dev environment, finding day-one gaps, working tasks, guarding the codebase, firing session hooks, running autonomous improvement on the codebase, learning the runtime, and reclaiming authorship. Each step opens with a single sentence to the viewer, runs the skill, surfaces verifiable evidence, and ends with one sentence on the benefit. While the run proceeds, jot improvements you spot in the skills themselves and emit a follow-up list at the end.

This skill is invoked from the root of the **ai-sorcery** repo. It assumes the canonical `sorcery` and `sorcery-dev` plugins are loaded — i.e., the user is running `./claude.sh` from within this repo.

## You are being recorded

Treat the user as silent and the audience as the screen capture. Narrate **before** each action: one sentence to introduce ("Now we'll use the `<skill>` skill to ..."), one or two commands, one sentence to close ("Confirmed via `<command>` — that file now exists / that commit was rejected"). Pre-announce visually-quiet stretches (long installs) so the viewer knows the silence is intentional. If a step fails live, narrate the failure, fix, and continue — a real fix beats a clean rehearsal.

## The sandbox

All steps run inside `<repo-root>/demo-workspace/`, gitignored at the host repo root. `reset-workspace.ts` (sibling) wipes and reseeds it before every run with a skeleton TypeScript "snippet-box" CLI plus three Claude-Bot-authored commits. The skeleton deliberately lacks a README, setup scripts, observability, and committed progress state, so `following-best-practices` finds real gaps and `claiming-authorship` finds bot commits to rewrite. After the reset, `cd demo-workspace` and stay there for every step unless noted.

**Cwd discipline.** Every code block in this runbook runs from inside `demo-workspace/`. The user may have launched Claude from the parent `ai-sorcery` repo root; the parent has its own `./me.sh` (a launcher delegate), its own real commit history, and its own `.claude/`, so any command resolving against the wrong cwd would mutate the *parent* tree — clobbering the launcher, committing into the plugin repo, or rebasing real commits. The fixed rule: after step 1 does `cd demo-workspace`, never leave; if `pwd` doesn't end in `/demo-workspace`, stop and `cd` back. Steps 6 and 11 include an explicit `[[ "$PWD" == */demo-workspace ]] || exit` guard before any history-rewriting operation, but that's belt-and-suspenders — the real defense is staying put.

## Run order

The full coverage list lives in `manifest.ts` next to this file. The pre-commit guard `check-skill-coverage.ts` blocks any commit that adds a new public skill without listing it there.

**Resume detection.** On every invocation, run `cd demo-workspace 2>/dev/null || true` first (idempotent — no-op if you're already inside `demo-workspace/`, harmless if you're not in the parent), then read `.demo-progress`. If it contains a step number, the previous session paused mid-demo (see step 7's pause); skip every step before that number and announce the resume on camera ("we're picking up at step N — that hook from step 2 just printed `snippet-box · 0 snippets stored` because we're now under `./claude.sh`"). If the file is missing or empty, run from step 1.

### 1. Reset the workspace

> "We'll start by wiping the demo sandbox so we begin from a known state."

Run from the **ai-sorcery repo root**:

```bash
bun plugins/sorcery-dev/skills/demoing-sorcery-skills/reset-workspace.ts
```

That deletes `demo-workspace/`, recreates the snippet-box scenario, and seeds three Claude-Bot-authored commits.

Verify with `git -C demo-workspace log --format="%h %ae %s"` — you should see three commits authored by `bot@anthropic.com`.

Now switch cwd into the new workspace and stay there for the rest of the runbook. **This is the single most important command in the demo** — everything after assumes `pwd` ends in `/demo-workspace`:

```bash
cd demo-workspace
```

### 2. `using-dot-claude` — write a snippet-box session greeter

> "Before any code lands, we want every Claude session opened in this repo to greet us with the snippet count — both as a useful signal and as proof the bypass works. Claude Code blocks direct writes under `.claude/`; `using-dot-claude` routes around it."

Write a SessionStart hook that reads `data/snippets.json`:

```bash
cat <<'EOF' | "${CLAUDE_PLUGIN_ROOT}/dot-claude.sh" write .claude/hooks/session-start.sh
#!/usr/bin/env bash
# Greet the developer with snippet-box's stored count when a Claude session
# opens in this repo. Tolerant of the data file not existing yet.
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
count=$(jq length "$root/data/snippets.json" 2>/dev/null || echo 0)
printf 'snippet-box · %s snippets stored\n' "$count"
EOF
chmod +x .claude/hooks/session-start.sh
```

Wire it into `.claude/settings.json` so it actually fires (also via `dot-claude.sh`, since direct writes are blocked):

```bash
cat <<'EOF' | "${CLAUDE_PLUGIN_ROOT}/dot-claude.sh" write .claude/settings.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-start.sh" }
        ]
      }
    ]
  }
}
EOF
```

Confirm with `cat .claude/hooks/session-start.sh` and `cat .claude/settings.json` — both files land cleanly even though Claude's native `Write` would have refused. The hook won't fire until a *new* Claude session opens in this directory; we'll see that happen when we restart under `./claude.sh` after step 7.

> "We'll see this hook print `snippet-box · 0 snippets stored` when the demo resumes — both proof of the bypass and the first piece of snippet-box infrastructure landing."

### 3. `launching-claude` — drop `./claude.sh` (with a demo-mode `--rc` strip)

> "Next, the launcher: a one-file `./claude.sh` that pins the model, raises the effort, and hides the account banner. We'll install it, then make a single post-install edit so the recording is safe to share."

```bash
"${CLAUDE_PLUGIN_ROOT}/install-launcher.sh"
```

The canonical launcher includes a `--rc` flag that, if a viewer of the recording grabbed it, would let them attach to this recorded session. Strip it from the installed copy before going further:

```bash
sed -i.bak '/^exec /s/ --rc//' claude.sh && rm claude.sh.bak
```

Narrate the strip explicitly so the audience understands the why:

> "We're stripping `--rc` from this one copy because the rest of the demo will be on camera. The plugin's canonical `claude.sh` keeps it; this is a one-line edit to the local install."

Verify with `cat ./claude.sh` — show the `--effort max --model claude-opus-4-7` line with no `--rc` between `claude` and `--effort`. We won't run `./claude.sh` here (no nesting); the actual switchover happens after step 7.

> "After the next few steps, we'll open a new Terminal tab and come back through `./claude.sh`. From that point on, snippet-box is a `./claude.sh` project. We don't exit the original session — Claude Code prints a resume-ID line on `/exit` that we don't want in the recording."

### 4. `following-best-practices` — scan for day-one gaps

> "The snippet-box repo is skeletal. `following-best-practices` will find what's missing."

Invoke the skill (`Skill: following-best-practices`) with the cwd inside `demo-workspace/`. Let it produce its top one or two ranked gaps — given the seed, it should call out at minimum the missing README and the missing starter scripts.

Capture the top gap verbatim — step 5 (`using-llm-tasks`) seeds its first task from this same output, so the two steps compose.

> "We've got the gaps. Now let's persist them as work."

### 5. `using-llm-tasks` — scaffold and work a task end-to-end

> "Tasks live as markdown files in `llm-tasks/`. First invocation in a fresh repo scaffolds the directory and seeds task #1 from the gap we just found."

Use the script directly so the viewer sees the file appear:

```bash
"${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh" new install-readme  # body via stdin matching step-4 output
```

Stub the four sections (Initial Understanding, Tentative Plan, Implementation, Completion Notes) using a one-paragraph adaptation of the seed shape. Then add a second task (`add-run-script`) to show batch behavior:

```bash
"${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh" new add-run-script
```

Walk one task through to done — fill the sections, then:

```bash
"${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh" done install-readme
"${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh" list
"${CLAUDE_PLUGIN_ROOT}/llm-tasks.sh" clump
```

Verify with `ls llm-tasks/ llm-tasks/completed/` — show `add-run-script.md` still pending and `install-readme.md` archived under a batch directory.

> "One markdown file per task. Lifecycle is filename change. No external tracker."

### 6. `guarding-commits` — install both commit guards and trigger each one

> "The skill ships two independent commit guards — one blocks strings from a gitignored allow-list, the other enforces conventional-commits subjects. Install both, demo both."

```bash
"${CLAUDE_PLUGIN_ROOT}/guarding-commits/install-guarding-commits.sh"
"${CLAUDE_PLUGIN_ROOT}/guarding-commits/install-conventional-commits.sh"
```

Both wire into `.githooks/commit-msg` with marker comments, so the order of installs doesn't matter and re-running either is a no-op.

Before staging anything, sanity-check cwd — committing into the parent `ai-sorcery` repo would touch the wrong tree:

```bash
[[ "$PWD" == */demo-workspace ]] || { echo "abort: not in demo-workspace ($PWD)" >&2; exit 1; }
```

#### Disallowed-terms

Activate one term in the seeded `commit-disallowed-terms.txt` — uncomment the `AKIA` line (AWS access-key prefix). Then provoke a real rejection:

```bash
echo 'const fakeKey = "AKIAIOSFODNN7EXAMPLE";' >> src/index.ts
git add src/index.ts
git commit -m "feat: stash a fake key for testing"   # must reject
```

Show the hook output naming the term and file. Then revert and commit cleanly:

```bash
git checkout -- src/index.ts
git commit --allow-empty -m "feat: prove the hook lets clean commits through"
```

The `AKIA` line is still active in `commit-disallowed-terms.txt` but no longer in any staged diff, so the hook stays silent.

#### Conventional commits

The same `commit-msg` hook now also rejects subjects that don't match `type(scope): subject`. Provoke a rejection:

```bash
git commit --allow-empty -m "bogus subject"   # must reject
```

Show the error naming the expected shape and the offending subject. Then commit with a conforming subject:

```bash
git commit --allow-empty -m "chore: prove the conventional check accepts conforming subjects"
```

Verify with `git log -2 --format='%h %s'` — the two clean commits landed; the rejected attempts left no trace.

> "End-to-end: two guards installed, both rejection paths demonstrated, both clean paths landed. The terms file stays out of git so each dev keeps their own list; conventional-commits applies uniformly."

### 7. `summarizing-sessions` — install the SessionEnd summary hook

> "The SessionEnd hook fires whenever a Claude session ends. We install it now; step 8's loop spawns its own Claude sessions that end programmatically, so we'll see summaries land as a side effect of the loop running — no on-camera `/exit` needed."

```bash
"${CLAUDE_PLUGIN_ROOT}/install-summary-hook.sh"
```

Verify the registration. The installer merges into the existing `.claude/settings.json` from step 2, so both `SessionStart` and `SessionEnd` should now be wired:

```bash
"${CLAUDE_PLUGIN_ROOT}/dot-claude.sh" cat .claude/settings.json | jq '.hooks | keys'
```

Show both keys present, then drop a progress marker the resumed session will read:

```bash
echo 8 > .demo-progress
```

Hand the demo off to a fresh session via the `./claude.sh` we built in step 3 — **don't exit the current session**. A `/exit` from an interactive session prints a "resume with ID …" line that would leak into the recording. Open a new Terminal tab instead; the original session stays idle in its tab (we'll close it off-camera later if at all).

> "I'll open a new Terminal tab, run `./claude.sh` from `demo-workspace/`, and prompt 'resume the sorcery demo'. The SessionStart hook from step 2 will fire as the new session opens — `snippet-box · 0 snippets stored` — proving both step 2 and step 3 in one move."

The literal commands the viewer should see on screen:

```
# in a new Terminal tab, from demo-workspace/:
./claude.sh
# in the new session:
"resume the sorcery demo"
```

Stop here. The skill picks up at step 8 on its next invocation by reading `.demo-progress`. The SessionEnd summary hook stays unfired for now — step 8's loop iterations will exercise it as they go.

### 8. `running-improvement-loops` — install, run a couple iterations, see what landed

> "The improvement loop runs Claude unattended, rotating through personas. Each iteration is usually a few minutes — fast enough to show two on camera, sped up in post."

```bash
"${CLAUDE_PLUGIN_ROOT}/loop/install-improvement-loop.sh"
```

That copies the loop scripts into `improvement/`, seeds empty `SUCCINCT-CHANGELOG.md` and `VERBOSE-CHANGELOG.md`, and wires the wrap-up hook into `.claude/settings.json`.

Then adapt `improvement/personas.json` to the snippet-box scenario. The default four personas (test-strengthener, code-improver, checkin, wildcard) are general-purpose; for snippet-box add a domain-specialist persona ("storage-layer-improver") that focuses on the JSON-on-disk store. Edit the file directly with the `Read` and `Write` tools.

Verify with `ls improvement/` and `jq '.[] | .name' improvement/personas.json`.

#### Pause — let the loop run

Hand off to the user. They run the loop in a separate terminal and let it iterate twice; the recording gets sped up over this stretch in post. Print the literal command:

```
# in a separate terminal, from demo-workspace/:
./improvement/loop.sh
```

Narrate the handoff:

> "I'll start the loop in a separate terminal, let it run two iterations, then come back here."

Stop and wait. The current Claude session stays open; the user comes back when they've seen two iterations land.

#### Resume — read what the loop left behind (and what the SessionEnd hook caught)

When the user signals they're back ("resume" / "ok done" / "two iterations done"), look at three things: what the loop committed, what its wrap-up hook recorded, and what the SessionEnd hook from step 7 captured as a side effect.

```bash
git log --format="%h %s" -10
cat improvement/SUCCINCT-CHANGELOG.md
find ~/LLM_Summaries -name "*.md" -mmin -30 -type f 2>/dev/null
```

The `find` line surfaces summary files written in the last 30 minutes — those are the SessionEnd hook firings from the loop's two iterations. Each loop iteration spawns its own Claude session; when it ends programmatically, the hook runs Haiku, the summary lands. No interactive `/exit` was involved.

Read the persona names and the one-line entries the wrap-up hook wrote. Acknowledge what landed concretely — name the persona and what it did:

> "Nice — the storage-layer-improver replaced the placeholder export with a real read/write path, the test-strengthener added a roundtrip test, and as a bonus the SessionEnd hook caught two summaries while the loop ran. Three skills demonstrated by one stretch of unattended work."

Keep the acknowledgment specific to whatever actually shows in the changelog and the summary files. If the loop did something surprising, surface that — surprises are good demo content.

> "Two iterations on camera; an unattended overnight run would compound this into something real."

### 9. `learning-new-tech` — scaffold the first lesson of a curriculum

> "Step nine is the learning skill. The snippet-box is a Bun project — `package.json` already declares it — so we'll ask Claude to build us a Bun learning track without having to switch tech."

This step operates inside the same `demo-workspace/` but in a separate `learning/` subtree, so it doesn't tangle with the snippet-box.

To stay inside the 2-3 minute per-step budget, give the skill a fully-formed prompt that pre-answers its onboarding questions — that way Claude skips straight to scaffolding:

> "Set up a Bun learning plan. I've used Node before, including npm, async/await, and basic TypeScript. Skip the JavaScript-from-scratch material. Goal: a small CLI."

Invoke the skill (`Skill: learning-new-tech`) with that ask. The skill scaffolds:

- `learning/OUTLINE.md` — 10-15 milestones, skipping the JS-from-scratch range per the user's stated background.
- `learning/NOTES.md` — seeded with the Node-experience answer.
- `learning/01-<topic>/` — first lesson only, with `README.md`, `start.sh`, `score.sh`.

Verify with:

```bash
ls learning/ learning/01-*/
head -20 learning/OUTLINE.md
```

Show the file tree on camera. Don't actually run `./start.sh` — completing a lesson live would burn the rest of the recording.

> "Outline first, lessons one at a time. After the user finishes lesson 01, they come back — we review the work, capture feedback, adapt the outline, and generate lesson 02. Each lesson is self-contained, so the user can drop in to any of them cold."

### 10. `capturing-test-fixtures` — snapshot a real page for the parser tests

> "Snippet-box's roadmap includes pulling code blocks out of real web pages — eventually the CLI grows an `add-from-url` subcommand. We won't write that parser today, but we will lay the test fixture for it. `capturing-test-fixtures` codifies how to capture, store, and simplify a real page so the future test stays fast and the source of truth survives."

Pick a primary URL with fallbacks. The Wikipedia article on Bun makes a thematic fixture (snippet-box runs on Bun) and Wikipedia reliably serves clean HTML over plain `curl`. If the live site happens to be blocked, returns a 4xx, or hits a Cloudflare challenge during the recording, fall through to one of the backups in order — every modern site occasionally throws a transient error, so the demo carries spares:

```bash
"${CLAUDE_PLUGIN_ROOT}/fixtures/capture.sh" --strip \
  --notes="Bun runtime article — nav, infobox, and code blocks; representative shape for the parser to skip / extract / preserve." \
  https://en.wikipedia.org/wiki/Bun_(software) \
  tests/fixtures/parser/bun-article
```

If that one trips, try the next:

```bash
# Fallback A — GNU's GPL page: well-structured static document, no JS
"${CLAUDE_PLUGIN_ROOT}/fixtures/capture.sh" --strip \
  --notes="Long-form static document with section headings — unrelated subject, representative HTML shape." \
  https://www.gnu.org/licenses/gpl-3.0-standalone.html \
  tests/fixtures/parser/gpl

# Fallback B — example.com: tiny, permanent, useful as a sanity check
"${CLAUDE_PLUGIN_ROOT}/fixtures/capture.sh" --strip \
  --notes="Sanity-check fixture — trivial content, verifies the capture pipeline works at all." \
  https://example.com/ \
  tests/fixtures/parser/example
```

Verify the three artifacts that landed for whichever capture succeeded:

```bash
ls tests/fixtures/parser/ tests/fixtures/parser/originals/
cat tests/fixtures/parser/originals/*.meta.json
```

You should see the raw original under `originals/`, the `.meta.json` companion (sourceUrl, capturedAt, captureMethod=curl, the Firefox UA, and the notes), and the mechanically stripped sibling tests would load.

> "Mechanical strip done — scripts, styles, comments, link/meta tags gone. The semantic trim — the LLM pass that drops everything irrelevant to the specific test — happens when we actually write the parser test. We're laying foundations here, not finishing the parser."

### 11. `claiming-authorship` — re-author the bot commits to a chosen identity

> "The seed gave us three commits authored by `bot@anthropic.com`. `claiming-authorship` rewrites them under whatever identity we pass in — handy here because this VM has no git config of its own."

Show the before state:

```bash
git log --format="%h %ae %s"
```

The seed's three commits are still `bot@anthropic.com`. **Sanity-check cwd before going further** — the parent `ai-sorcery` repo also has a `me.sh` (it's a launcher delegate, different content). Copying over it from the wrong cwd, or running `./me.sh` from there, would rewrite ai-sorcery's real commit history:

```bash
[[ "$PWD" == */demo-workspace ]] || { echo "abort: not in demo-workspace ($PWD)" >&2; exit 1; }
```

Install snippet-box's own `./me.sh` and run it with a fake demo identity. The VM has no git config, so `CLAIM_EMAIL` / `CLAIM_NAME` give the script an identity to claim under without touching git config:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/me.sh" ./me.sh && chmod +x ./me.sh
CLAIM_EMAIL=jane@doe.com CLAIM_NAME='Jane Doe' ./me.sh
```

Show the after state with the same `git log` invocation. The author email column should read `jane@doe.com` for every previously-bot-authored commit. Author dates are preserved; only committer dates change (expected for a rebase).

> "Fake identity for the recording — off-camera, you'd run `./me.sh` without env vars and claim under your real `user.email`. Either way, re-running is a no-op once a commit is already under the chosen identity."

### 12. `running-claude-in-a-vm` — **skipped, with reason**

> "There's one public skill we won't demo: `running-claude-in-a-vm`. We're already inside a Tart VM right now, and Apple's Virtualization framework doesn't support nested virtualization, so a Tart-in-Tart attempt would just fail. The manifest records the skip with this reason; the pre-commit guard verifies the manifest stays in sync."

Show the entry:

```bash
grep -A2 'running-claude-in-a-vm' \
  plugins/sorcery-dev/skills/demoing-sorcery-skills/manifest.ts
```

> "If you're recording from the host (outside the VM), this is the skill you'd run first — it's how you'd build the VM we're recording from now."

## Where snippet-box stands

Before the wrap-up, take 30 seconds to show what the build looks like at the end of the demo. Run the seeded stub once and read the git log:

```bash
bun src/index.ts list
git log --format="%h %ae %s" -8
```

The CLI's entry point may still echo a stub depending on what the loop touched in step 8 — we built the *infrastructure* to develop snippet-box and the loop has already started filling pieces in. The git log shows commits attributed to the user (step 11), the bot's gone, the loop's two iterations are recorded as their own commits, and the pending `add-run-script` task is queued for the next loop iteration to pick up.

> "Snippet-box came in as a bot-authored stub. It leaves with a session greeter, guarded commit history, two unattended improvement iterations, fresh SessionEnd summaries from those iterations in `~/LLM_Summaries/`, a queued task, and a learning track. Each step earned its place."

## Wrap-up — the skill-improvement follow-up list

Throughout the run, hold a running list of rough edges you noticed in the skills themselves: phrasing in `SKILL.md` that didn't match observed behavior, error messages that could be clearer, dependencies that should fail faster, descriptions that wouldn't match a natural user phrasing, install paths that produce noisy output, etc.

At the end of the demo, summarize the follow-up list in a final chat message (one sentence per item) and write it to `../IMPROVEMENTS.md` — that's the parent `ai-sorcery` repo root, so it shows up as an untracked file in `git status` and the user actually sees it (whereas anything inside `demo-workspace/` is gitignored and easy to overlook). Format:

```markdown
# Skill improvements noticed during the demo

## <skill-name>
- <observation> → suggested change
```

Bias toward concrete suggestions ("rename flag X to Y", "add a check for Z before running W"). Vague observations ("could be smoother") are worth less than one specific change.

## Keeping the demo on track

- **Time-box each step to 2-3 minutes.** If a step sprawls, cut and move on — the skill's own SKILL.md is the full reference, the demo just needs to land the highlights.
- **No detours.** Interesting tangents go on the follow-up list; they don't get explored on camera.
- **Speak to the audience, not to Claude.** The viewer doesn't see the transcript. Say "we'll inspect the file," not "let me read it."
- **Surface tooling failures, don't hide them.** A missing `bun` or `jq` gets called out for the recording, then the demo continues with whatever remains.

## Caveats

- **Apple Silicon, macOS host.** Several skills (the loop, the VM, the launcher) assume `bun` and `jq` are on the host. The reset script depends on `bun`. The improvement-loop installer fails fast on missing `bun` / `jq`.
- **Workspace lifetime.** `demo-workspace/` survives between demo runs only as long as you don't reset. The next run wipes it. If a viewer wants to inspect post-demo state, do it before re-running this skill.
- **`launching-claude` is exercised across a tab swap.** Nesting Claude inside the current session is still unsupported, so step 3 installs and inspects, then step 7 pauses the demo. The user opens a new Terminal tab, runs `./claude.sh` there, and prompts "resume the sorcery demo" in the new session. The original session stays idle in its tab — the demo never shows an interactive `/exit`, because Claude Code prints a "resume with ID …" line on exit that we don't want in the recording.
- **`summarizing-sessions` is exercised by step 8's loop iterations.** The loop spawns Claude sessions that end programmatically (no resume-ID leak), and each one fires the SessionEnd hook. The `find ~/LLM_Summaries -mmin -30` line during step 8's resume surfaces those summary files as the verifiable artifact.
- **The pause-and-resume relies on `.demo-progress`.** The skill writes `8` to `demo-workspace/.demo-progress` at the end of step 7 and reads it on its next invocation. `reset-workspace.ts` wipes the workspace, so the marker auto-clears between recordings — but if a partial recording leaves the file behind, delete it manually before starting fresh.
- **`running-improvement-loops` runs on camera for two iterations.** Typical iterations finish in a few minutes; the recording is sped up over the iteration stretch in post-production.
- **`running-claude-in-a-vm` is unrunnable from inside a Tart VM** (this is the recording environment). The manifest skips it.
- **The pre-commit guard stays loud.** When a contributor adds a public skill without updating `manifest.ts` and `SKILL.md`, the commit fails until they do. That is by design — the demo skill is the only place the full skill catalog is exercised end-to-end, and silent drift means the recording you take six months from now is missing skills the catalog has gained.

## Related

- `sorcery-dev:adding-skills` — the skill-author checklist. It points back here so every new public skill gets a demo step or an explicit skip reason.
