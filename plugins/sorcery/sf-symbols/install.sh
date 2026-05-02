#!/usr/bin/env bash
#
# install.sh — drop the sf-symbol-search.ts / sf-symbol-to-svg.swift pair
# into the user's repo (under scripts/). Idempotent: re-running overwrites
# both with the latest versions, so the user always gets fixes from the
# plugin without manual sync.

set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git rev-parse --show-toplevel)"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "install: SF Symbols ships with macOS — these scripts only run on Darwin." >&2
    echo "         Install will write the files anyway, but neither will work elsewhere." >&2
fi

scripts_dir="$repo_root/scripts"
mkdir -p "$scripts_dir"

# Use sf-symbol-* prefix so they sort together in any listing of scripts/.
search_dst="$scripts_dir/sf-symbol-search.ts"
svg_dst="$scripts_dir/sf-symbol-to-svg.swift"

cp "$src_dir/search.ts" "$search_dst"
chmod +x "$search_dst"
echo "install: wrote $search_dst"

cp "$src_dir/to-svg.swift" "$svg_dst"
chmod +x "$svg_dst"
echo "install: wrote $svg_dst"

cat <<EOF

install: done.

Try them:

  bun $search_dst lightning
  swift $svg_dst bolt.fill /tmp/bolt.svg

The scripts use only public AppKit / Vision APIs — no automation permissions
prompt. The catalog they search lives in CoreGlyphs.bundle and ships with
macOS itself, so no extra install is required.

If you want a visual browser to flip through the catalog, Apple's free
SF Symbols.app is one Homebrew cask away (this skill does not depend on
it):

  brew install --cask sf-symbols
EOF
