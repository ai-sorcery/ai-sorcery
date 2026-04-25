# demoing-sorcery

A scripted walkthrough that exercises every public-facing sorcery skill in one screen-recordable narrative. Operates inside a gitignored `demo-workspace/` sandbox at the host repo root, wiped clean at the start of every run.

Internal-only meta-skill, in `sorcery-dev`. Fires on phrasings like "run the sorcery demo", "let's record the demo", or "walk through every skill". Pairs with the pre-commit guard `check-skill-coverage.ts`, which blocks commits that add a new public skill without listing it in the manifest.

See [`SKILL.md`](SKILL.md) for the trigger description and the full run order.
