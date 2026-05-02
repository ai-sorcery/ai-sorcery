#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Commands below expand ~ or $HOME inside the guest (via `tart exec bash -c`)
# rather than hardcoding a guest user, so swapping IMAGE for a base image
# with a different user doesn't require rewriting this script.

want_app() {
  local target="$1"
  local app
  for app in "${APPS[@]}"; do
    [[ "$app" == "$target" ]] && return 0
  done
  return 1
}

echo "Waiting for VM to be reachable..."
for i in $(seq 1 60); do
  if tart exec "$VM_NAME" true &> /dev/null; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Error: VM '$VM_NAME' is not running or guest agent not responding."
    echo "Start it first with ./run.sh (in another terminal)."
    exit 1
  fi
  sleep 2
done

# --- App installs (skip any app not in APPS; all idempotent) ---

install_chrome() {
  want_app chrome || return 0
  if tart exec "$VM_NAME" test -d "/Applications/Google Chrome.app"; then
    echo "Chrome: already installed."
  else
    echo "Installing Chrome..."
    tart exec "$VM_NAME" brew install --cask google-chrome
  fi
}

install_obsidian() {
  want_app obsidian || return 0
  if tart exec "$VM_NAME" test -d "/Applications/Obsidian.app"; then
    echo "Obsidian: already installed."
  else
    echo "Installing Obsidian..."
    tart exec "$VM_NAME" brew install --cask obsidian
  fi
}

install_sublime_text() {
  want_app sublime-text || return 0
  if tart exec "$VM_NAME" test -d "/Applications/Sublime Text.app"; then
    echo "Sublime Text: already installed."
  else
    echo "Installing Sublime Text..."
    tart exec "$VM_NAME" brew install --cask sublime-text
  fi
}

install_bun() {
  want_app bun || return 0
  if tart exec "$VM_NAME" which bun &>/dev/null; then
    echo "Bun: already installed — checking for upgrade..."
    tart exec "$VM_NAME" brew upgrade oven-sh/bun/bun || echo "Bun is already up to date."
  else
    echo "Installing Bun..."
    tart exec "$VM_NAME" brew install oven-sh/bun/bun
  fi
  if tart exec "$VM_NAME" bash -c 'test -d "$HOME/.cache/puppeteer/chrome"'; then
    echo "Puppeteer Chrome: already installed."
  else
    echo "Installing Puppeteer Chrome..."
    tart exec "$VM_NAME" bunx puppeteer browsers install chrome
  fi
}

install_dotnet10() {
  want_app dotnet10 || return 0
  if tart exec "$VM_NAME" bash -c '
    if command -v dotnet &>/dev/null; then
      DOTNET=dotnet
    elif [ -x "$HOME/.dotnet/dotnet" ]; then
      DOTNET="$HOME/.dotnet/dotnet"
    else
      exit 1
    fi
    "$DOTNET" --list-sdks | grep -qE "^10\."
  ' &>/dev/null; then
    echo ".NET 10 SDK: already installed."
    return 0
  fi
  echo "Installing .NET 10 SDK..."
  tart exec "$VM_NAME" bash -c '
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel 10.0
    rm /tmp/dotnet-install.sh
  '
  tart exec "$VM_NAME" bash -c '
    PROFILE=~/.zprofile
    if ! grep -q "DOTNET_ROOT" "$PROFILE" 2>/dev/null; then
      {
        echo ""
        echo "export DOTNET_ROOT=\"\$HOME/.dotnet\""
        echo "export PATH=\"\$DOTNET_ROOT:\$PATH\""
      } >> "$PROFILE"
      echo "Added .NET environment variables to $PROFILE"
    fi
  '
}

install_claude_code() {
  want_app claude-code || return 0
  if ! tart exec "$VM_NAME" brew list claude-code@latest &>/dev/null; then
    echo "Installing Claude Code CLI..."
    # The macos-tahoe-xcode image preinstalls the `claude-code` cask, which
    # owns /opt/homebrew/bin/claude and conflicts with `claude-code@latest`.
    # Remove it before installing the formula.
    if tart exec "$VM_NAME" brew list --cask claude-code &>/dev/null; then
      tart exec "$VM_NAME" brew uninstall --cask claude-code
    fi
    tart exec "$VM_NAME" brew install claude-code@latest
  else
    # Sentinel lives under ~/.cache in the guest (not /tmp, which macOS
    # wipes at boot) so the 4-hour throttle carries across VM restarts.
    NEEDS_UPGRADE=false
    tart exec "$VM_NAME" bash -c 'mkdir -p "$HOME/.cache"'
    if tart exec "$VM_NAME" bash -c 'test -f "$HOME/.cache/claude-code-last-upgrade"'; then
      LAST_TS=$(tart exec "$VM_NAME" bash -c 'cat "$HOME/.cache/claude-code-last-upgrade"')
      NOW_TS=$(tart exec "$VM_NAME" date +%s)
      ELAPSED=$(( NOW_TS - LAST_TS ))
      if [ "$ELAPSED" -ge 14400 ]; then
        NEEDS_UPGRADE=true
      fi
    else
      NEEDS_UPGRADE=true
    fi
    if [ "$NEEDS_UPGRADE" = true ]; then
      echo "Upgrading Claude Code CLI..."
      tart exec "$VM_NAME" brew upgrade claude-code@latest || true
      tart exec "$VM_NAME" bash -c 'date +%s > "$HOME/.cache/claude-code-last-upgrade"'
    else
      echo "Claude Code CLI: upgrade check skipped (<4 hours since last check)."
    fi
  fi
}

install_chrome
install_obsidian
install_sublime_text
install_bun
install_claude_code
install_dotnet10

# --- Sync time zone from host ---

HOST_TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
echo "Setting VM time zone to $HOST_TZ..."
# systemsetup -settimezone prints a noisy "InternetServices" error on VMs
# without network reachability to Apple's time servers. Filter it — the
# time zone itself still sets correctly.
tart exec "$VM_NAME" sudo systemsetup -settimezone "$HOST_TZ" 2>&1 | grep -v "### Error:.*InternetServices" || true

# --- Configure preferences ---

echo "Configuring preferences..."
tart exec "$VM_NAME" bash -c '
  defaults write NSGlobalDomain com.apple.swipeScrollDirection -bool false
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
  defaults write NSGlobalDomain com.apple.scrollwheel.scaling -float 0.75
  defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
  defaults write NSGlobalDomain AppleShowScrollBars -string Always
  defaults -currentHost write com.apple.screensaver idleTime -int 0
  killall cfprefsd
'

tart exec "$VM_NAME" sudo pmset -a displaysleep 0 sleep 0 disksleep 0

# --- Create "Fix Clipboard" app on Desktop ---

echo "Creating Fix Clipboard app on Desktop..."
tart exec "$VM_NAME" bash -c '
  if [ ! -d ~/Desktop/Fix\ Clipboard.app ]; then
    cat > /tmp/fix_clipboard.applescript << '\''APPLESCRIPT'\''
do shell script "killall tart-guest-agent"
delay 2
display notification "Clipboard sharing restarted" with title "Clipboard Fix"
APPLESCRIPT
    osacompile -o ~/Desktop/Fix\ Clipboard.app /tmp/fix_clipboard.applescript
    rm /tmp/fix_clipboard.applescript
    echo "Created Fix Clipboard app on Desktop."
  else
    echo "Fix Clipboard app already exists."
  fi
'

# --- Configure Dock (one-time) ---

echo "Configuring Dock..."
"$SCRIPT_DIR/setup-dock.sh" "$VM_NAME"

# --- Configure Claude Code: bypass permissions + install/enable superpowers
# plugin (only if claude-code is in APPS) ---

if want_app claude-code; then
  # `marketplace add` and `plugin install` exit 0 on re-run ("already on
  # disk" / "already installed"), so re-running the whole script is safe.
  echo "Installing Claude superpowers plugin..."
  tart exec "$VM_NAME" claude plugin marketplace add anthropics/claude-plugins-official \
    || { echo "Error: 'claude plugin marketplace add anthropics/claude-plugins-official' failed inside the VM. Check VM network connectivity and that 'claude' is on PATH." >&2; exit 1; }
  tart exec "$VM_NAME" claude plugin install superpowers@claude-plugins-official \
    || { echo "Error: 'claude plugin install superpowers@claude-plugins-official' failed inside the VM. The marketplace add succeeded, but the install did not — check the VM's network access to the plugin source." >&2; exit 1; }

  # `plugin install` only stages files on disk; the `enabledPlugins` toggle
  # below is what actually loads the plugin at session start. Both this
  # toggle and `permissions.defaultMode` are written as first-run defaults
  # (only when the key is absent), so a user who disables the plugin or
  # switches permission modes inside the VM keeps that change across re-runs.
  echo "Seeding Claude Code default settings..."
  tart exec "$VM_NAME" osascript -l JavaScript -e '
ObjC.import("Foundation");

function readFile(path) {
  const ns = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return ns.isNil() ? null : ObjC.unwrap(ns);
}
function writeFile(path, contents) {
  $(contents).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}
function mkdirP(path) {
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(path, true, $(), null);
}

const home = ObjC.unwrap($.NSHomeDirectory());
const path = home + "/.claude/settings.json";
const defaults = {
  permissions: { defaultMode: "bypassPermissions" },
  enabledPlugins: { "superpowers@claude-plugins-official": true },
};

mkdirP(home + "/.claude");
const raw = readFile(path);
const data = raw ? JSON.parse(raw) : {};
for (const key of Object.keys(defaults)) {
  const value = defaults[key];
  if (value && typeof value === "object" && !Array.isArray(value)) {
    if (!data[key] || typeof data[key] !== "object") data[key] = {};
    for (const k of Object.keys(value)) {
      if (!(k in data[key])) data[key][k] = value[k];
    }
  } else if (!(key in data)) {
    data[key] = value;
  }
}
writeFile(path, JSON.stringify(data, null, 2) + "\n");
' || { echo "Error: failed to seed ~/.claude/settings.json inside the VM. The osascript step writing the settings file did not succeed — check VM filesystem permissions." >&2; exit 1; }
  tart exec "$VM_NAME" bash -c 'rm -f ~/Library/LaunchAgents/com.anthropic.claude.plist'
fi

SHARED_FOLDERS_FILE="$SCRIPT_DIR/shared-folders.json"

# --- Mount shared folders (before Terminal tabs auto-cd into them) ---
# Each share has its own virtiofs tag (set via tag=<name> in run.sh).
# Guest path defaults to mirroring the host path; entries may set `guest`
# to override (e.g., for host paths that live outside ~/Dev).
# Must run before setup-terminal-tabs.sh — that script opens Terminal
# whose .zprofile cd's into these mount points.

if [ -f "$SHARED_FOLDERS_FILE" ]; then
  MOUNT_COUNT=0
  while IFS=$'\t' read -r host_entry guest_entry; do
    name="$(basename "$guest_entry")"
    # Replace a leading ~ with a literal $HOME that the guest's bash will
    # expand — avoids hardcoding the guest user's absolute path here.
    vm_path="${guest_entry/#\~/\$HOME}"

    tart exec "$VM_NAME" bash -c "mkdir -p \"$vm_path\""
    if tart exec "$VM_NAME" bash -c "/sbin/mount_virtiofs \"$name\" \"$vm_path\"" 2>/dev/null; then
      echo "Mounted: $name -> $guest_entry"
      MOUNT_COUNT=$((MOUNT_COUNT + 1))
    else
      echo "Already mounted or skipped: $name"
    fi
  done < <(jq -r '.[] | select(.active) | "\(.path)\t\(.guest // .path)"' "$SHARED_FOLDERS_FILE")
  echo "Shared folders mounted: $MOUNT_COUNT"
fi

# --- Configure Terminal tabs (only if there are active terminal entries) ---

DEV_DIRS=()
if [ -f "$SHARED_FOLDERS_FILE" ]; then
  while IFS= read -r line; do
    DEV_DIRS+=("$line")
  done < <(jq -r '.[] | select(.active and .terminal) | (.guest // .path)' "$SHARED_FOLDERS_FILE")
fi
# DEV_DIRS entries keep their leading ~ so the .zprofile that
# setup-terminal-tabs.sh writes has `cd ~/...` lines — zsh expands those
# at login, no need to know the guest user on the host side.

if [ ${#DEV_DIRS[@]} -gt 0 ]; then
  echo "Configuring Terminal tabs..."
  "$SCRIPT_DIR/setup-terminal-tabs.sh" "$VM_NAME" "${DEV_DIRS[@]}"
else
  echo "No active terminal shared folders — skipping Terminal tab setup."
fi

# --- Add ~/Dev to Finder sidebar favorites ---

echo "Adding ~/Dev to Finder sidebar favorites..."
tart exec "$VM_NAME" bash -c '
  cat > /tmp/add_sidebar.swift << '\''SWIFT'\''
import Foundation
import CoreServices

let devPath = NSHomeDirectory() + "/Dev"
let devURL = NSURL(fileURLWithPath: devPath)
let listType = kLSSharedFileListFavoriteItems.takeUnretainedValue()

guard let list = LSSharedFileListCreate(nil, listType, nil)?.takeRetainedValue() else {
    print("ERROR: Failed to create shared file list")
    exit(1)
}

var seed: UInt32 = 0
if let snapshot = LSSharedFileListCopySnapshot(list, &seed)?.takeRetainedValue() as? [LSSharedFileListItem] {
    for item in snapshot {
        if let resolved = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as NSURL? {
            if resolved.path == devPath {
                print("Dev already in Finder sidebar favorites")
                exit(0)
            }
        }
    }
    if let last = snapshot.last {
        LSSharedFileListInsertItemURL(list, last, "Dev" as NSString, nil, devURL, nil, nil)
        print("Added Dev to Finder sidebar favorites")
        exit(0)
    }
}

let sentinelPtr = kLSSharedFileListItemLast.toOpaque()
let sentinel = Unmanaged<LSSharedFileListItem>.fromOpaque(sentinelPtr).takeUnretainedValue()
LSSharedFileListInsertItemURL(list, sentinel, "Dev" as NSString, nil, devURL, nil, nil)
print("Added Dev to Finder sidebar favorites")
SWIFT
  swiftc /tmp/add_sidebar.swift -o /tmp/add_sidebar -framework CoreServices -framework Foundation 2>&1 | grep -v "deprecated"
  /tmp/add_sidebar
  rm -f /tmp/add_sidebar /tmp/add_sidebar.swift
'

echo ""
echo "VM setup complete."
