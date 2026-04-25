# guarding-commits

Installs self-contained git hooks that guard commits in two independent ways:

- **Disallowed-terms guard** — blocks any commit whose staged diff or message contains one of the strings listed in a git-ignored `commit-disallowed-terms.txt` at the repo root. Catches personal emails, obvious secret prefixes, `DO NOT COMMIT` markers, code-name project strings.
- **Conventional-commits guard** — rejects subjects that don't match `type(scope): subject`. Keeps the log scannable and unlocks release tooling that keys off the prefix (semantic-release, release-please, changesets).

Each guard has its own installer; install one, the other, or both. The checks run in pure bash with no dependencies outside the repo, so teammates who don't have the sorcery plugin installed can still use the hooks — they just need to activate `core.hooksPath` once after cloning.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
