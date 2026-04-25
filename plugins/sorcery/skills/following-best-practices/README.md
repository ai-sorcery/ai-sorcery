# following-best-practices

Language-agnostic practices that are cheap on day one and painful to retrofit. Claude scans the current repo against the list and surfaces concrete gaps. See [`SKILL.md`](SKILL.md) for the full catalog and trigger description.

## Example

Asking Claude to audit a repo against the best-practices catalog:

![Claude receives "Any best practices I should follow?", loads the following-best-practices skill, scans the repo, and reports that two day-one practices are already in — PLAN.md (progress state) and llm-tasks/ (task workflow) — but conventional-commit enforcement is missing. On "Implement conventional commit enforcement now.", Claude loads the using-llm-tasks skill and begins scaffolding the task.](example.png)
