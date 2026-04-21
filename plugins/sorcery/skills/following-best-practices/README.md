# following-best-practices

Language-agnostic practices that are cheap on day one and painful to retrofit. Claude scans the current repo against the list and surfaces concrete gaps. See [`SKILL.md`](SKILL.md) for the full catalog and trigger description.

## Example

Asking Claude to audit a repo against the best-practices catalog:

![The following-best-practices skill in action: Claude receives "Any best practices I should follow?", loads the skill, scans the repo (git log, core.hooksPath, .githooks/), and reports that most entries are N/A for this sandbox but two day-one practices are already in — PLAN.md (progress state) and llm-tasks/ (task workflow). It surfaces one genuine gap — #7, conventional commits aren't enforced — with evidence (recent subjects like "plan", "delete", "stuff" show no type(scope): subject shape; no commit-msg hook; no core.hooksPath) and a seed task shape that delegates to the bundled conventional-commit-check.sh, then asks whether to create the task file under llm-tasks/. On "Implement conventional commit enforcement now.", Claude loads the using-llm-tasks skill and begins scaffolding the task and wiring the hook.](example.png)
