# launching-claude

Drops an executable `./claude.sh` at the root of the current repo that launches Claude Code with privacy-friendly defaults — `IS_DEMO=1`, `--rc`, `--effort max`, `--model claude-opus-4-7`. See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.

## Example

Asking Claude to set up the launcher in a repo:

![The launching-claude skill in action: Claude receives "Set up claude.sh in this repo.", loads the skill, runs install-launcher.sh, and reports that ./claude.sh is installed and ready to launch Claude Code with IS_DEMO=1, --rc, --effort max, and --model claude-opus-4-7.](example.png)
