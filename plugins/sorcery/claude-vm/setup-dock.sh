#!/bin/bash
# setup-dock.sh — one-time Dock cleanup inside the VM.
#
# Keeps: Apps (Launchpad), Safari, Chrome, Sublime Text. Drops everything else.
# Terminal is not pinned since it's always running and macOS surfaces it anyway.
#
# Called by vm-setup.sh. Usage: setup-dock.sh <VM_NAME>

set -euo pipefail

VM_NAME="$1"

tart exec "$VM_NAME" osascript -l JavaScript -e '
ObjC.import("Foundation");
const app = Application.currentApplication();
app.includeStandardAdditions = true;
const fm = $.NSFileManager.defaultManager;

const home = ObjC.unwrap($.NSHomeDirectory());
const sentinel = home + "/.dock-configured";
if (fm.fileExistsAtPath(sentinel)) {
  console.log("Dock already configured.");
} else {
  // Round-trip through NSPropertyListSerialization (not plutil JSON) so that
  // CFURL bookmark `book` blobs on system tiles like the Apps launcher
  // survive the read-modify-write cycle. JSON conversion fails on those bytes.
  const tmp = "/tmp/dock-setup.plist";
  app.doShellScript("defaults export com.apple.dock " + tmp);
  const data = $.NSData.dataWithContentsOfFile(tmp);
  // 2 = NSPropertyListMutableContainersAndLeaves -> mutable dicts/arrays.
  // The format out-param needs a real Ref() — passing $() yields an invalid
  // pointer and crashes osascript on -e invocation.
  const fmt = Ref();
  const dock = $.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 2, fmt, null);

  function makeApp(url, label, bundleId) {
    return $({
      "tile-data": {
        "bundle-identifier": bundleId,
        "file-data": { "_CFURLString": url, "_CFURLStringType": 15 },
        "file-label": label,
        "file-type": 41,
      },
      "tile-type": "file-tile",
    });
  }

  const KEEP = $.NSSet.setWithArray($([
    "com.apple.apps.launcher", "com.apple.Safari",
    "com.google.Chrome", "com.sublimetext.4",
  ]));

  const apps = dock.objectForKey("persistent-apps");
  const kept = $.NSMutableArray.array;
  const presentBids = $.NSMutableSet.set;
  const total = apps.count;
  for (let i = 0; i < total; i++) {
    const entry = apps.objectAtIndex(i);
    const td = entry.objectForKey("tile-data");
    if (td.isNil()) continue;
    const bid = td.objectForKey("bundle-identifier");
    if (bid.isNil()) continue;
    if (KEEP.containsObject(bid)) {
      kept.addObject(entry);
      presentBids.addObject(bid);
    }
  }
  if (!presentBids.containsObject($("com.google.Chrome"))) {
    kept.addObject(makeApp("file:///Applications/Google%20Chrome.app/", "Google Chrome", "com.google.Chrome"));
  }
  if (!presentBids.containsObject($("com.sublimetext.4"))) {
    kept.addObject(makeApp("file:///Applications/Sublime%20Text.app/", "Sublime Text", "com.sublimetext.4"));
  }

  dock.setObjectForKey(kept, "persistent-apps");
  dock.setObjectForKey($.NSArray.array, "persistent-others");

  // 200 = NSPropertyListBinaryFormat_v1_0
  const newData = $.NSPropertyListSerialization.dataWithPropertyListFormatOptionsError(dock, 200, 0, null);
  newData.writeToFileAtomically(tmp, true);
  app.doShellScript("defaults import com.apple.dock " + tmp);
  fm.removeItemAtPathError(tmp, $());
  app.doShellScript("killall Dock");
  $("").writeToFileAtomicallyEncodingError(sentinel, true, $.NSUTF8StringEncoding, null);
  console.log("Dock configured.");
}
' || { echo "Error: setup-dock.sh failed to configure the Dock inside the VM. The osascript step did not succeed — re-run vm-setup.sh after diagnosing." >&2; exit 1; }
