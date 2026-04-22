# guarding-commits

Installs a self-contained pre-commit hook that blocks any commit whose staged diff adds a line containing one of the strings listed in a git-ignored `commit-disallowed-terms.txt` at the repo root. Useful for catching personal emails, obvious secret prefixes, `DO NOT COMMIT` markers, and similar strings you never want to ship.

The check runs in pure bash with no dependencies outside the repo, so teammates who don't have the sorcery plugin installed can still use the hook — they just need to activate `core.hooksPath` once after cloning.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
