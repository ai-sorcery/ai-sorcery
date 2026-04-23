# running-claude-in-a-vm

Scaffolds a Tart-based macOS VM into the current repo with Claude Code and a small set of utilities preinstalled. After setup, Claude runs inside the VM — the host stays isolated except for folders the user explicitly shares. See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.

## What lands where

Running this skill in a repo creates (default subdir `claude-vm/`):

```
claude-vm/
├── config.sh               # tunables — VM name, image, RAM, disk, APPS
├── shared-folders.json     # host paths to mount into the VM
├── setup.sh                # one-time: brew install tart, tart clone image
├── run.sh                  # boot the VM, open Screen Sharing, run vm-setup
├── vm-setup.sh             # in-VM provisioning (apps, prefs, shared folders)
├── teardown.sh             # stop and delete the VM
├── setup-dock.sh           # Dock cleanup (called by vm-setup.sh)
└── setup-terminal-tabs.sh  # Terminal tabs per shared folder (called by vm-setup.sh)
```

## Quick start

```bash
cd claude-vm
./setup.sh    # one-time: installs Tart via brew, clones the macOS image, configures the VM
./run.sh      # boots the VM, opens Screen Sharing (admin/admin), runs vm-setup.sh automatically
```

`vm-setup.sh` is idempotent — `./run.sh` calls it every boot and it skips apps that are already installed.

## Shared folders

Edit `shared-folders.json` to mount host folders into the VM. Each entry:

```json
{
  "path": "~/Dev/MyProject",
  "active": true,
  "terminal": true
}
```

- `path` — host path (tilde-expanded).
- `active` — if false, the entry is skipped.
- `terminal` — if true, `vm-setup.sh` opens a Terminal tab at that folder.
- `guest` (optional) — override the guest-side mount path. Default is to mirror the host path under the guest user's home.

Host and guest share read-write; edits on either side are visible immediately.

## Stopping the VM

Ctrl+C in the terminal running `./run.sh`, or:

```bash
tart stop <VM_NAME>
```

## Full reset

```bash
./teardown.sh     # deletes the VM — setup.sh re-creates it from scratch
```

## SF Symbols

Auto-downloaded from [developer.apple.com/sf-symbols](https://developer.apple.com/sf-symbols/) when `sf-symbols` is in `APPS`. The URL is pinned to SF Symbols 7 inside `vm-setup.sh`; bump it when Apple ships a new major version.

## Xcode

Already installed in the default image (`ghcr.io/cirruslabs/macos-tahoe-xcode`). If you swap `IMAGE` to `macos-tahoe-base:latest` in `config.sh`, Xcode won't be there — Cirrus Labs' base image deliberately excludes it.

## Caveats

See [`SKILL.md`](SKILL.md) for the full list. Short version: Apple Silicon only, `admin`/`admin` credentials, `~/.tart` storage (not an external drive without advanced setup).
