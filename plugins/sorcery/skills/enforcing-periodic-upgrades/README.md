# enforcing-periodic-upgrades

Installs a self-contained pre-commit check that refuses commits when any lockfile at the repo root has not been touched in more than `STALE_DAYS` days (default 7). The intent is to drag the next dependency-refresh sweep forward in time, before drift turns into a debugging session.

The check recognises lockfiles for bun, npm, yarn, pnpm, cargo, go modules, bundler, poetry, uv, pipenv, composer, swiftpm, and mix. It silently no-ops in any repo where none of those are present at the root.

The hook runs in pure bash with no dependencies outside the repo, so teammates who don't have the sorcery plugin installed can still use it — they just need to activate `core.hooksPath` once after cloning.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads, the install command, and the upgrade-cycle checklist.
