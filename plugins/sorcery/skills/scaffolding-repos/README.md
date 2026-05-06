# scaffolding-repos

Bundles the universal-baseline sorcery installers behind one entry point. Asking "scaffold this repo" runs `install-scaffold.sh`, which calls each sibling installer in order — `./claude.sh`, `./me.sh`, conventional-commits + style + disallowed-terms commit guards, the periodic-upgrades pre-commit, and the SessionEnd summary hook. Every step is idempotent, so re-runs only fill in what's missing.

After the bundle, Claude invokes the `following-best-practices` skill to scan for remaining day-one gaps (README, starter scripts, observability, persisted test output, etc.) that aren't part of the universal baseline.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
