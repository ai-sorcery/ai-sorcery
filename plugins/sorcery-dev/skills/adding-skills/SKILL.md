---
name: adding-skills
description: Use when a contributor is adding a new skill, extending an existing skill, or adding a language-agnostic practice to the ai-sorcery sorcery plugin. Typical phrasings — "let's add a skill for X", "help me author a sorcery skill", "we need a skill that does Y", "extend the using-dot-claude skill with Z".
---

# Adding Skills

Sorcery skills live under `plugins/sorcery/skills/<skill-name>/`. This skill is the checklist the author reads before starting, so each new or edited skill lands with the conventions the repo has settled on.

Invoke this skill, then walk the checklist below in order, skipping sections only when truly inapplicable.

## Example invocation

> "Let's add a skill that wires up a GitHub Actions summary job to every repo."

## Checklist

### Decide the shape

Three options — pick the lightest that fits:

- **New standalone skill.** A fresh concept with its own trigger phrases. Creates a new dir under `plugins/sorcery/skills/`.
- **Extension to an existing skill.** The work belongs inside a current skill's scope — edit that skill's `SKILL.md` (and scripts) in place rather than duplicating triggers.
- **New entry in `following-best-practices`.** If it's a language-agnostic practice that compounds on day one, append a named entry to that skill's catalog instead of creating a whole skill.

Pick a gerund name for a new skill: `using-X`, `running-X`, `claiming-X`, `summarizing-X`, `writing-X`, `building-X`, `adding-X`. Match the pattern of sibling skills.

### Plan the happy path before writing

Before touching any file, state:

- **Who invokes this?** What natural phrasing from the user fires the skill?
- **The shortest end-to-end.** One paragraph: what does the agent do the moment the skill loads?

If the happy path doesn't fit in a paragraph, the scope isn't clear yet. Iterate on scope before writing files.

### File layout

- Skill dir: `plugins/sorcery/skills/<skill-name>/` with `SKILL.md`, `README.md`, and an optional `example.png` (the user will tend to provide this later after actually using the fully built skill).
- Shared scripts the skill calls:
  - Single file → flat at the plugin root (e.g. `plugins/sorcery/me.sh`).
  - Bundle of three or more related files → a subdir at the plugin root (e.g. `plugins/sorcery/loop/`).
- Every script reference from `SKILL.md` uses `${CLAUDE_PLUGIN_ROOT}/...`. One carve-out: a skill in the sibling `sorcery-dev` plugin that needs to invoke a script from this plugin uses `${CLAUDE_PLUGIN_ROOT}/../sorcery/...` — both plugins live as siblings under the same marketplace install, so the relative reach is durable. (Direct `${CLAUDE_PLUGIN_ROOT}` would resolve to the *sorcery-dev* plugin root, which doesn't host the helper scripts.)
- **Anything that writes or edits under `.claude/` MUST route through `${CLAUDE_PLUGIN_ROOT}/dot-claude.sh`** — never the native Write or Edit tools. If the new skill's installer touches `.claude/settings.json` or `.claude/hooks/...`, invoke the sibling skill `using-dot-claude` from the installer.

### Installer decision

Wrap the install steps into an `install-<skill>.sh` at the plugin root when either:

- The install touches `.claude/` (JSON merges, hook registration).
- The install is non-trivial: multi-file copy, idempotency checks, settings merges, dependency checks (jq, bun).

Inline `cp + chmod` directly in the `What to do` section of SKILL.md when the install is a single file to the repo root with no complexity — see `claiming-authorship/SKILL.md` for the minimal form.

For wrappers that register hooks:

- Idempotency is exact command-string match, not substring — substring matches produce false positives for paths that share a prefix.
- Merge new `PostToolUse` (or `SessionEnd`, etc.) entries into an existing `matcher: "*"` group rather than creating parallel siblings. The reference patterns are `install-summary-hook.sh` (single SessionEnd entry) and `loop/install-improvement-loop.sh` (PostToolUse merged into an existing matcher group).
- Fail fast on missing dependencies (`command -v jq` or `command -v bun`).

### SKILL.md content

- Frontmatter `name` matches the skill's directory name exactly.
- `description` names the trigger AND the outcome, specifically enough that Claude picks it up from natural user phrasing. Read a few sibling `description` fields before writing yours — the existing set shows the level of specificity that works.
- Body structure: intro → `What to do` (or the equivalent happy-path section) → `How it works internally` → `Caveats` (or `When not to use`).
- Cross-skill references are explicit: write "invoke the sibling skill X" or "see the sibling skill X," not bare "see X." Keep content-level references symmetric within the same plugin — if sibling A's instructions delegate to sibling B in the same plugin, B should have a pointer back. A "related skills" educational list at the end of a skill (like this one's tail) is one-way by design and doesn't require back-pointers.
- Refer to list entries from other skills by name ("the conventional-commits practice"), not by position ("#9"). Position numbers shift as the list evolves; names survive reorderings. (Numbered headings inside a skill's own catalog are fine — the rule is about references *into* a catalog from outside.)
- Don't tell Claude to read partial slices of small documents. If the instruction is "read the README," let it read the whole README.
- No explicit give-up paths. Don't write "if you can't do X, just do Y" — it legitimises settling. If the agent is truly blocked, it will reason to a fallback on its own.
- `Caveats` ordered by importance, not alphabetically. Flag every dependency (jq, bun, Playwright), every stability caveat (undocumented flags, env vars), every non-obvious behavior.

### Testing

Before committing:

- `bash -n <script>` on every shell script.
- `jq -e . <file>` on every JSON file.
- Run any `.ts` file through `bun` once.
- Sandbox-test every installer end-to-end in `/tmp/`: fresh empty repo, re-run for idempotency, then re-run over an existing `.claude/settings.json` that already contains unrelated hooks.
- Verify path references match the installer-produced filenames. A common bug: rename a script in the installer, then forget to update the SKILL.md that instructs the user to call it.

### Housekeeping

- Add a section to the root `README.md`'s Examples block matching the existing per-skill pattern — heading + `> Ask: ...` + a 2-3 line description of what the skill does.
- If the work surfaced a new language-agnostic practice, add it to `following-best-practices/SKILL.md` (named entry, seed task shape included).
- **Wire the new skill into the demo runbook.** Add an entry for it in `plugins/sorcery-dev/skills/demoing-sorcery-skills/manifest.ts` — either `{ status: "covered" }` paired with a step in that skill's `SKILL.md` (run-order section, with narration / verification / benefit), or `{ status: "skipped", reason: "..." }` if it can't run in the demo environment. The pre-commit guard `check-skill-coverage.ts` will block the commit until this is done.

### Review and commit

Before the commit, invoke `superpowers:requesting-code-review` (external plugin — installed separately) to dispatch a reviewer subagent against the change. Apply the reviewer's Critical and Important findings unless there's a clear reason to skip one. For non-trivial changes, run a second review after the first-pass fixes land — a reviewer often surfaces second-order issues that the first pass revealed.

Conventional commit: `feat(sorcery): add <skill-name> skill` for a new skill, `feat(sorcery): extend <skill-name> skill` for extensions, `refactor(sorcery): ...` for restructuring existing skills. Body is a hyphen-bulleted list of specifics — one detail per bullet.

## Related skills

- `superpowers:requesting-code-review` (external plugin) — dispatch a reviewer subagent before committing.
- `using-dot-claude` — every installer that touches `.claude/` routes through its bundled `dot-claude.sh`.
- `following-best-practices` — the home for new language-agnostic practices that belong in the catalog rather than in a new skill.
