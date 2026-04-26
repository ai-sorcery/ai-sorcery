# config.sh — tunables for the claude-vm scripts.
#
# The installer copies this file to config.sh on first install. Edit the
# installed copy (alongside setup.sh / run.sh / etc.), not this example.
#
# All scripts in this directory source config.sh at startup.

VM_NAME="claude-macos"
# macos-tahoe-xcode bundles Xcode (and Flutter) on top of macos-tahoe-base.
# Swap to macos-tahoe-base:latest if you want a leaner image without Xcode.
IMAGE="ghcr.io/cirruslabs/macos-tahoe-xcode:latest"

VM_CPU=4
VM_MEMORY_MB=8192
VM_DISK_GB=150
VM_DISPLAY="1920x1080"

# Apps to install inside the VM. Comment out the ones you don't want.
# Options: chrome, claude-code (recommended), obsidian, sublime-text,
# bun, dotnet10, sf-symbols. (Xcode is pre-installed by the default image.)
APPS=(chrome claude-code obsidian sublime-text)

# No TART_HOME here — Tart uses ~/.tart by default and that's the right
# choice for most setups. Pointing TART_HOME at a /Volumes/... path (or
# symlinking ~/.tart to one) often fails with cross-device-link errors
# because some Tart operations rename or hardlink within the same
# filesystem. See cirruslabs/tart#226 and #1112.
