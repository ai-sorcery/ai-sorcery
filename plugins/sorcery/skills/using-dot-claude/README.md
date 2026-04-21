# using-dot-claude

Routes writes to paths under `.claude/` through a bundled bash script so Claude Code's native protection on those paths doesn't block them. See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.

## Example

Asking Claude to write a hook file under `.claude/`:

![The using-dot-claude skill in action: Claude receives "Write .claude/hooks/example.sh so it echoes \"hello\".", loads the skill, routes the write through dot-claude.sh (since Claude Code's native Write is blocked for .claude/ paths), and the file lands. Claude then offers to chmod +x it, and on "Yes." confirms the file is now executable.](example.png)
