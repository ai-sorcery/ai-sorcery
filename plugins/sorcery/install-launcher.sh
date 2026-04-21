#!/usr/bin/env bash
#
# install-launcher — copy the plugin's canonical claude.sh launcher into
# the current working directory as ./claude.sh and make it executable.
# Refuses to overwrite an existing ./claude.sh so a user-customized copy
# isn't silently clobbered.

set -euo pipefail

plugin_dir="$(cd "$(dirname "$0")" && pwd)"
src="$plugin_dir/claude.sh"
dest="./claude.sh"

if [[ -e "$dest" ]]; then
    echo "install-launcher: $dest already exists — remove it first if you want to replace it" >&2
    exit 1
fi

cp "$src" "$dest"
chmod +x "$dest"
echo "[install-launcher] installed: $dest"
