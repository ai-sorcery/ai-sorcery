#!/usr/bin/env bash
#
# install-claude-vm — copy the plugin's canonical claude-vm scripts into
# <subdir>/ at the current working directory. Seeds config.sh and
# shared-folders.json from their .example.* siblings on first install.
#
# Idempotent: existing files are left alone. Re-run after editing
# config.sh / shared-folders.json; neither will be clobbered.
#
# Usage: install-claude-vm.sh [<subdir>]     # default: claude-vm

set -euo pipefail

subdir="${1:-claude-vm}"

plugin_dir="$(cd "$(dirname "$0")" && pwd)"

# Install into $subdir relative to the current working directory. Deliberately
# not `git rev-parse --show-toplevel` — that would silently plant the subdir
# at the repo root when the user ran the installer from a nested path.
target_dir="$PWD/$subdir"

mkdir -p "$target_dir"

# Canonical scripts + data files. Left column is the source filename in the
# plugin; right column (after ':') is the destination name.
declare -a files=(
  "setup.sh"
  "run.sh"
  "vm-setup.sh"
  "teardown.sh"
  "setup-dock.sh"
  "setup-terminal-tabs.sh"
  "fix-cache.sh"
  "config.example.sh:config.sh"
  "shared-folders.example.json:shared-folders.json"
)

copied=0
skipped=0
for entry in "${files[@]}"; do
  src_name="${entry%%:*}"
  dst_name="${entry##*:}"
  if [[ "$entry" != *":"* ]]; then
    dst_name="$src_name"
  fi

  src="$plugin_dir/$src_name"
  dst="$target_dir/$dst_name"

  if [[ -e "$dst" ]]; then
    echo "  skip (exists): $subdir/$dst_name"
    skipped=$(( skipped + 1 ))
    continue
  fi

  cp "$src" "$dst"
  case "$dst_name" in
    *.sh) chmod +x "$dst" ;;
  esac
  echo "  copy: $subdir/$dst_name"
  copied=$(( copied + 1 ))
done

echo
echo "[install-claude-vm] done — $copied file(s) copied, $skipped already present."
echo "Next: review $subdir/config.sh, then run: cd $subdir && ./setup.sh"
