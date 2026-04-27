## Axioms

### 1. Write code that is readily understandable

Favor clarity over cleverness. Use descriptive variable and function names, and when a comment is needed, explain _why_ — not what. This applies to every language in the repo, including shell scripts.

### 2. Use conventional commits

Format commit messages as `type(scope): subject`, with scope optional. Common types here: `feat`, `fix`, `refactor`, `docs`, `chore`.

A body is optional. When present, separate it from the subject with a blank line, and prefer a hyphen-bulleted list of specifics — one detail per bullet — over a prose paragraph.

### 3. Don't use Python or Perl — reach for JXA or Bun TypeScript instead

Two reasons to keep both off the menu. (1) Python's `/usr/bin/python3` lives behind the Command Line Tools install on the macOS guests this repo targets, so first invocation can prompt to install CLT and break the "vm-setup.sh is idempotent" contract. (2) Perl ships with stock macOS, but adding another language to the mix is noise — one more runtime, one more set of conventions and error modes for the next contributor to learn. Two replacements cover every reasonable use:

- For inline shell-style scripting that needs JSON, plists, or Foundation APIs, use `osascript -l JavaScript` (JXA). It ships in `/usr/bin/osascript` on every macOS install since 10.10, gives you a real JavaScript engine with native `JSON.parse` / `JSON.stringify`, and reaches plist data via `NSPropertyListSerialization` plus shell-outs to `defaults` / `plutil` for round-tripping. When you'd otherwise write `python3 -c '...'`, write `osascript -l JavaScript -e '...'` instead.
- For anything bigger — text processing, HTML parsing, multi-file scripts, anything that would tempt a `perl -0777 -pe '...'` — use Bun TypeScript. Bun is already required elsewhere in the repo, ships a real HTML parser via `HTMLRewriter`, and keeps the language count down.

Pre-commit hooks (`.githooks/check-no-python.sh`, `.githooks/check-no-perl.sh`) block `.py` / `.pl` / `.pm` files, Python and Perl shebangs, and `python` / `python3` / `perl` invocations in shell scripts.
