# summarizing-sessions

Installs a SessionEnd hook in the current repo that summarizes each Claude Code session into a dated markdown file under `~/LLM_Summaries/YYYY-MM-DD/`. The summarizer runs Haiku with a forced JSON schema in a detached background process and filters out subagent transcripts so multi-agent iterations don't produce duplicate summaries.

Point an Obsidian vault at `~/LLM_Summaries/` for a zero-config daily journal of agent work.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
