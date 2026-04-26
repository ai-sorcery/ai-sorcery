## Axioms

### 1. Write code that is readily understandable

Favor clarity over cleverness. Use descriptive variable and function names, and when a comment is needed, explain _why_ — not what. This applies to every language in the repo, including shell scripts.

### 2. Use conventional commits

Format commit messages as `type(scope): subject`, with scope optional. Common types here: `feat`, `fix`, `refactor`, `docs`, `chore`.

A body is optional. When present, separate it from the subject with a blank line, and prefer a hyphen-bulleted list of specifics — one detail per bullet — over a prose paragraph.

### 3. Don't use Python — reach for JXA via `osascript -l JavaScript` instead

This repo's scripts target macOS guests inside Tart VMs, where `/usr/bin/python3` lives behind the Command Line Tools install — first invocation can prompt to install CLT, breaking the "vm-setup.sh is idempotent" contract. `osascript -l JavaScript` (JXA) ships in `/usr/bin/osascript` on every macOS install since 10.10, gives you a real JavaScript engine with native `JSON.parse`/`JSON.stringify`, and reaches plist data via Foundation (`NSPropertyListSerialization`) plus shell-outs to `defaults` / `plutil` for round-tripping. When you'd otherwise write `python3 -c '...'` (or `python -c '...'`), write `osascript -l JavaScript -e '...'` instead. A pre-commit hook (`.githooks/check-no-python.sh`) blocks `.py` files, Python shebangs, and `python` / `python3` invocations in shell scripts.
