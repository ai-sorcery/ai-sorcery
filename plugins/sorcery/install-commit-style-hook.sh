#!/usr/bin/env bash
#
# install-commit-style-hook — wire `check-commit-message.ts` into the
# current project's `.githooks/commit-msg`. Idempotent: re-runs are no-ops
# when an entry referencing this plugin's validator is already present.

set -euo pipefail

if ! command -v bun >/dev/null 2>&1; then
    echo "install-commit-style-hook: bun is required (brew install bun)" >&2
    exit 1
fi

plugin_dir="$(cd "$(dirname "$0")" && pwd)"
validator="$plugin_dir/check-commit-message.ts"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
hooks_dir="$project_root/.githooks"
hook_file="$hooks_dir/commit-msg"

mkdir -p "$hooks_dir"

current_path="$(git -C "$project_root" config --get core.hooksPath 2>/dev/null || echo "")"
if [[ "$current_path" != ".githooks" ]]; then
  git -C "$project_root" config core.hooksPath .githooks
  echo "[install-commit-style-hook] set core.hooksPath=.githooks"
fi

# Exact path match — substring matches produce false positives for siblings
# that share a prefix.
if [[ -f "$hook_file" ]] && grep -Fq "$validator" "$hook_file"; then
  echo "[install-commit-style-hook] already installed: $hook_file"
  exit 0
fi

hook_line="bun \"$validator\" \"\$1\" || exit 1  # writing-commit-messages-check"

if [[ ! -f "$hook_file" ]]; then
  cat > "$hook_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail

$hook_line
EOF
  chmod +x "$hook_file"
  echo "[install-commit-style-hook] created $hook_file"
else
  printf '\n%s\n' "$hook_line" >> "$hook_file"
  echo "[install-commit-style-hook] appended check to $hook_file"
fi
