# claiming-authorship

Drops an executable `./me.sh` at the root of the current repo. Running it rewrites the last few commits to set the author field to the current git user while preserving each commit's original author date. Re-runs are a no-op on anything already attributed.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
