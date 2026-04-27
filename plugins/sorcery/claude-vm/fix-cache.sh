#!/usr/bin/env bash
#
# fix-cache — clear a stuck virtio-fs dentry cache by remounting the share.
#
# macOS guests on Apple Virtualization (used by Tart) sometimes get a
# stuck directory listing for paths that were created on the host AFTER
# the VM booted: `ls` returns empty, `bun fs.readdirSync` returns [],
# writes into the directory fail with ENOENT, yet `stat` on a known-named
# file inside still works. The kernel's directory enumeration cache is
# broken for that specific inode, and no userspace operation (touch,
# chmod, xattr, sync, even `sudo purge`) flushes it. A full umount + mount
# cycle for the share is the only known fix short of rebooting the VM.
#
# Tart sets the virtio-fs tag to the share's basename, so the remount
# uses `basename "$mount_point"` as the tag. Override with --tag if your
# setup differs.
#
# Usage: fix-cache.sh [<mount-point>] [--tag <tag>]
# Default mount-point: the git toplevel for the current cwd, falling back
#                      to the cwd itself if that is not a git checkout.

set -euo pipefail

mount_point=""
tag=""

while (( $# > 0 )); do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --tag=*) tag="${1#--tag=}"; shift ;;
    -h|--help)
      sed -n '/^# fix-cache/,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --*)
      echo "fix-cache: unknown flag: $1" >&2
      exit 64
      ;;
    *)
      if [[ -n "$mount_point" ]]; then
        echo "fix-cache: too many positional args" >&2
        exit 64
      fi
      mount_point="$1"
      shift
      ;;
  esac
done

if [[ -z "$mount_point" ]]; then
  mount_point="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
mount_point="$(cd "$mount_point" && pwd)"

if [[ -z "$tag" ]]; then
  tag="$(basename "$mount_point")"
fi

if ! mount | grep -qF "virtio-fs on $mount_point "; then
  echo "fix-cache: $mount_point is not a virtio-fs mount; nothing to do." >&2
  exit 1
fi

echo "fix-cache: remounting $mount_point (tag: $tag)..." >&2
sudo umount "$mount_point"
sudo mount -t virtiofs "$tag" "$mount_point"
echo "fix-cache: done. If your shell's cwd was inside this path, run 'cd .' to re-enter the live mount." >&2
