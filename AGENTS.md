## Axioms

### 1. Write code that is readily understandable

Favor clarity over cleverness. Use descriptive variable and function names, and when a comment is needed, explain _why_ — not what. This applies to every language in the repo, including shell scripts.

### 2. Use conventional commits

Format commit messages as `type(scope): subject`, with scope optional. Common types here: `feat`, `fix`, `refactor`, `docs`, `chore`.

A body is optional. When present, separate it from the subject with a blank line, and prefer a hyphen-bulleted list of specifics — one detail per bullet — over a prose paragraph. Skip `Co-Authored-By: Claude ...` trailers; Claude attribution flows through the commit author field (see `me.sh`).
