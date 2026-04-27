# writing-commit-messages

Encodes ai-sorcery's commit-message style as both a ruleset Claude follows when authoring messages and a `commit-msg` hook that enforces the same rules.

The ruleset: subject-only by default; if a body is needed, hyphen-bulleted with hard caps (3 bullets or fewer, 20 words or fewer per bullet), no file paths, no basenames of changed files, no em dashes anywhere. The intent: most readers don't read bodies, so facts worth elaborating usually belong as code comments near the affected code.

See `SKILL.md` for the full ruleset, what the agent does, and how to install the hook in a new repo.
