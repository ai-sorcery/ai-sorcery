#!/bin/bash
# setup-dock.sh — one-time Dock cleanup inside the VM.
#
# Keeps: Apps (Launchpad), Safari, Chrome, Sublime Text. Drops everything else.
# Terminal is not pinned since it's always running and macOS surfaces it anyway.
#
# Called by vm-setup.sh. Usage: setup-dock.sh <VM_NAME>

set -euo pipefail

VM_NAME="$1"

tart exec "$VM_NAME" python3 -c '
import plistlib, pathlib, subprocess, os, tempfile

sentinel = pathlib.Path.home() / ".dock-configured"
if sentinel.exists():
    print("Dock already configured.")
    exit(0)

def make_app(url, label, bundle_id, file_type=41):
    return {
        "tile-data": {
            "bundle-identifier": bundle_id,
            "file-data": {"_CFURLString": url, "_CFURLStringType": 15},
            "file-label": label,
            "file-type": file_type,
        },
        "tile-type": "file-tile",
    }

dock = plistlib.loads(subprocess.check_output(["defaults", "export", "com.apple.dock", "-"]))

KEEP = {"com.apple.apps.launcher", "com.apple.Safari", "com.google.Chrome",
        "com.sublimetext.4"}
ADD = {
    "com.google.Chrome": make_app("file:///Applications/Google%20Chrome.app/", "Google Chrome", "com.google.Chrome"),
    "com.sublimetext.4": make_app("file:///Applications/Sublime%20Text.app/", "Sublime Text", "com.sublimetext.4"),
}

apps = dock.get("persistent-apps", [])
kept = [a for a in apps if a.get("tile-data", {}).get("bundle-identifier", "") in KEEP]
present = {a.get("tile-data", {}).get("bundle-identifier", "") for a in kept}
for bid, entry in ADD.items():
    if bid not in present:
        kept.append(entry)
dock["persistent-apps"] = kept
dock["persistent-others"] = []

with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as f:
    plistlib.dump(dock, f)
    tmp = f.name
subprocess.run(["defaults", "import", "com.apple.dock", tmp], check=True)
os.unlink(tmp)
subprocess.run(["killall", "Dock"])
sentinel.touch()
print("Dock configured.")
'
