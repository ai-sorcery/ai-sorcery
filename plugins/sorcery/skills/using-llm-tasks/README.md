# using-llm-tasks

Introduces a markdown-driven task workflow to a repo: every task is a file under `llm-tasks/`, worked through four append-only sections (Initial Understanding → Tentative Plan → Implementation → Completion Notes), then marked done with a `DONE-` prefix and archived into batched folders.

On first invocation in a repo, the skill scaffolds `llm-tasks/` and seeds a first task by consulting the sibling `following-best-practices` skill for the top-ranked gap. Subsequent invocations handle create / work-next / done / archive flows through the bundled `llm-tasks.sh` script.

See [`SKILL.md`](SKILL.md) for the trigger description and full lifecycle.
