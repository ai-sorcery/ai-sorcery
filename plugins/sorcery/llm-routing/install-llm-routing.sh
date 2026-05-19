#!/usr/bin/env bash
#
# install-llm-routing — scaffold the llm-routing setup in the current
# repo. Copies the plugin's canonical scripts and config templates into
# two places:
#   - ./llm-routing/   (the bulk of the harness — flake, route.sh, configs)
#   - ./                (entrypoints the user touches: llm.sh, swival.toml,
#                        .env.example — landed at the repo root where the
#                        user lives)
#
# Idempotent: re-running skips files that already exist. A user who has
# edited litellm.config.yaml or swival.toml in their copy keeps their
# edits.
#
# Also appends `.swival/` and `.env` to the repo's root .gitignore so a
# first `git add .` after a swival session doesn't quietly stage prompt
# transcripts or provider keys.

set -euo pipefail

plugin_routing_dir="$(cd "$(dirname "$0")" && pwd)"

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
target_dir="$project_root/llm-routing"

mkdir -p "$target_dir"

# Files that land inside ./llm-routing/
internal_files=(
  "setup.sh"
  "flake.nix"
  "route.sh"
  "start-proxy.sh"
  "stop-proxy.sh"
  "wizard.ts"
  "status.ts"
  "observability.ts"
  "providers.json"
  "litellm.config.yaml"
  "README.md"
)

# Files that land at the repo root (alongside llm-routing/).
# Format: "<source-name>:<dest-name>" — dest can match source.
root_files=(
  "llm.sh:llm.sh"
  "swival.toml:swival.toml"
  ".env.example:.env.example"
)

copied=0
skipped=0

copy_one() {
  local src="$1"
  local dst="$2"
  local rel="$3"

  if [[ -e "$dst" ]]; then
    echo "  skip (exists): $rel"
    skipped=$(( skipped + 1 ))
    return
  fi
  cp "$src" "$dst"
  case "$dst" in
    *.sh) chmod +x "$dst" ;;
  esac
  echo "  copy: $rel"
  copied=$(( copied + 1 ))
}

for name in "${internal_files[@]}"; do
  copy_one \
    "$plugin_routing_dir/$name" \
    "$target_dir/$name" \
    "llm-routing/$name"
done

for entry in "${root_files[@]}"; do
  src_name="${entry%%:*}"
  dst_name="${entry##*:}"
  copy_one \
    "$plugin_routing_dir/$src_name" \
    "$project_root/$dst_name" \
    "$dst_name"
done

# Runtime log dir so first start-proxy.sh run doesn't race on mkdir.
mkdir -p "$target_dir/logs"

# llm-routing/.gitignore — covers the runtime state inside the dir.
gitignore_internal="$target_dir/.gitignore"
if [[ ! -e "$gitignore_internal" ]]; then
  cat > "$gitignore_internal" <<'EOF'
# Runtime state from start-proxy.sh — not source.
logs/
# Project-local Python venv for LiteLLM (created by setup.sh).
.venv/
# Nix lockfile is committed; nothing else from nix to ignore here.
EOF
  echo "  seed: llm-routing/.gitignore"
  copied=$(( copied + 1 ))
fi

# Repo-root .gitignore — append .swival/ and .env. .swival/ is Swival's
# per-cwd state (HISTORY.md transcripts, repl_history, cache.db,
# memory/). .env carries provider keys.
root_gitignore="$project_root/.gitignore"
append_to_gitignore() {
  local pattern="$1"
  local comment="$2"
  if [[ -e "$root_gitignore" ]] && grep -qxF "$pattern" "$root_gitignore"; then
    return
  fi
  if [[ ! -e "$root_gitignore" ]]; then
    : > "$root_gitignore"
  fi
  # Add a section header on first append so the additions are easy to
  # spot in git diff.
  if ! grep -qF "# llm-routing" "$root_gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# llm-routing — agent state and secrets"
    } >> "$root_gitignore"
  fi
  echo "$pattern" >> "$root_gitignore"
  echo "  gitignore: + $pattern  ${comment}"
  copied=$(( copied + 1 ))
}
append_to_gitignore ".env"      "(provider API keys — never commit)"
append_to_gitignore ".swival/"  "(swival per-cwd state — transcripts, cache)"

cat <<EOF

[install-llm-routing] done — $copied file(s) copied/seeded, $skipped already present.

Next:
  1. Bootstrap the toolchain (idempotent):
       cd $target_dir && ./setup.sh
     This installs Nix via the Determinate installer if missing, creates
     a project-local .venv with Python 3.13 and litellm[proxy], and
     brew-installs swival/tap/swival.
  2. Fill in keys:
       cp $project_root/.env.example $project_root/.env
       \$EDITOR $project_root/.env
  3. Boot a swival session pointed at the proxy:
       $project_root/llm.sh            # default profile: frontier
       $project_root/llm.sh claude     # or frontier / balanced / cheap / claude
     llm.sh starts the proxy on first call, reuses it after. It also
     lists the directories the agent will have access to and offers
     to add more — additions land in .env under SWIVAL_ADD_DIRS.
  4. The wizard interface (status, retarget tiers, verify aliases, etc.):
       $target_dir/route.sh
EOF
