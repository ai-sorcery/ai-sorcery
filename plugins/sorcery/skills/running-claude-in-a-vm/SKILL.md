---
name: running-claude-in-a-vm
description: Use when the user wants to run Claude Code inside an isolated macOS VM (sandboxed from the host) — phrasings like "set up Claude in a VM", "isolate Claude", "give Claude a macOS sandbox", "run Claude without touching my host". Creates a subdir (default `claude-vm/`) with Tart-based setup scripts that clone a macOS image, boot it with VNC/Screen Sharing, and install Claude Code plus a small set of nice-to-have apps. Apple Silicon only.
---

# Running Claude in a VM

Drops a `claude-vm/` directory (configurable) into the current repo with the scripts that stand up a Tart-based macOS VM, install Claude Code inside it, and mount host folders as needed. After setup, the user runs Claude inside the VM — host files stay untouched except for anything they explicitly share.

## What to do

Ask the user one question first:

> "Easy mode (sensible defaults — recommended) or custom mode (I'll ask a few questions first)?"

### Easy mode

Run the plugin's installer from the root of the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/claude-vm/install-claude-vm.sh"
```

The installer copies the bundled scripts into `./claude-vm/`, seeds `config.sh` with sensible defaults (VM name `claude-macos`, 4 CPU / 8 GB RAM / 150 GB disk, apps: Chrome, Claude Code, Obsidian, Sublime Text), and seeds an empty `shared-folders.json`. Tart's own storage default (`~/.tart`) is used — no config change needed.

Tell the user the next command to run:

```bash
cd claude-vm && ./setup.sh    # one-time: installs Tart, clones the macOS image
./run.sh                       # boots the VM, opens Screen Sharing, runs vm-setup
```

### Custom mode

Batch four questions in a single message:

1. **Install subdir?** Default `claude-vm`.
2. **VM name?** Default `claude-macos`.
3. **Which apps?** Multi-select from:
   `chrome`, `claude-code` (recommended), `obsidian`, `sublime-text`, `bun` (ships Puppeteer Chrome too), `dotnet10`, `sf-symbols`.
   All of these install unattended. Xcode is already pre-installed by the default image (`macos-tahoe-xcode`), so it doesn't appear as a separate option.
4. **Any shared folders to pre-register?** List of host paths. Each entry can set `terminal: true` to also open a Terminal tab for it.

Run the installer with the chosen subdir:

```bash
"${CLAUDE_PLUGIN_ROOT}/claude-vm/install-claude-vm.sh" <subdir>
```

Then overwrite `<subdir>/config.sh` with the user's answers, using the plain Write tool (config.sh isn't under `.claude/`, so the sibling skill `using-dot-claude` isn't needed). Overwrite `<subdir>/shared-folders.json` with the pre-registered folders if any were provided. Give the same `setup.sh` / `run.sh` next-command tip as easy mode.

## How it works internally

- `setup.sh` — one-time host-side prep: `brew install` Tart if missing, `tart clone` the macOS image from `config.sh`, configure CPU / memory / disk / display.
- `run.sh` — boots the VM with VNC and shared-folder `--dir` flags built from `shared-folders.json`, opens Screen Sharing once the VM has an IP, then runs `vm-setup.sh` inside the booted VM.
- `vm-setup.sh` — in-VM provisioning: installs each app in `APPS`, syncs time zone from host, applies preferences (dark mode, natural-scroll off, dimmer cursor), drops a "Fix Clipboard" AppleScript on the Desktop, configures Dock and (optionally) Terminal tabs, mounts shared folders. When `claude-code` is installed, it also installs and enables the `superpowers` plugin from `anthropics/claude-plugins-official`. Idempotent on re-run.
- `teardown.sh` — `tart stop` + `tart delete` the VM named in `config.sh`.

## Configuration knobs (config.sh)

| Variable | Default | Meaning |
|---|---|---|
| `VM_NAME` | `claude-macos` | Tart VM name |
| `IMAGE` | `ghcr.io/cirruslabs/macos-tahoe-xcode:latest` | Tart image to clone (includes Xcode) |
| `VM_CPU` | `4` | vCPUs |
| `VM_MEMORY_MB` | `8192` | RAM (MB) |
| `VM_DISK_GB` | `150` | Disk (GB) |
| `VM_DISPLAY` | `1920x1080` | Resolution |
| `APPS` | `(chrome claude-code obsidian sublime-text)` | In-VM apps to install |

## Caveats

- **Apple Silicon only.** Tart uses Apple's Virtualization.framework. macOS-in-Docker needs x86 KVM, which isn't available on M-series.
- **Requires Homebrew and `jq`.** `setup.sh` will brew-install Tart if missing; `jq` is required on the host to parse `shared-folders.json`.
- **VM credentials are `admin` / `admin`** — the upstream Tart base image's default. Not suitable for shared or networked use.
- **VM storage is `~/.tart`** (Tart's own default). External-drive layouts — `TART_HOME` on `/Volumes/...` or `~/.tart` symlinked to one — often fail with cross-device-link errors (see cirruslabs/tart#226, #1112) because some Tart operations rename or hardlink within the same filesystem. Not covered by this skill; advanced users handle it out-of-band.
- **SF Symbols URL is pinned to version 7.** `vm-setup.sh` downloads `https://devimages-cdn.apple.com/design/resources/download/SF-Symbols-7.dmg` — bump the URL in `install_sf_symbols` when Apple ships a new major version.
- **Scripts are copies, not symlinks.** Edits to the installed scripts are local to the repo; they don't propagate to other installs. If the plugin's canonical scripts change, re-run the installer — it skips files that already exist, so old versions stay unless the user removes them first.
- **Not for running Claude instances in parallel on the same host.** Tart supports multiple VMs with different names, but each needs its own clone of the image and its own RAM / disk allocation.

## Troubleshooting

When something fails, these three diagnostics cover most cases:

- **`tart run` exits silently or with `VZErrorDomain Code=1`.** Apple's framework hides the real error; pull it from the unified log:
  ```bash
  /usr/bin/log show --predicate 'processImagePath CONTAINS "Virtualization" OR subsystem CONTAINS "virtualization"' --last 30m --style compact | tail -60
  ```
  Look for `[com.apple.virtualization:breadcrumb]` lines and the last `com.apple.Virtualization.VirtualMachine` messages before the process exited.
- **Bypass the wrapper to isolate tart vs. our scripts.** Run `tart run --vnc-experimental --dir <one-share> <VM_NAME>` directly. If that works, the problem is in `run.sh` / `vm-setup.sh`. Halve the `--dir` flag set to find a toxic share.
- **`tart ip` can return a stale IP after the VM exits.** `run.sh`'s "VM is up at..." line is not proof of liveness — if `tart exec` immediately fails, check `tart list` (state should be `running`) and `ps aux | grep tart` for the actual VM process.

## Related skills

Pair with the sibling skill `launching-claude` inside the VM once Claude Code is installed — it drops a `claude.sh` launcher with privacy-friendly defaults. The sibling skill `using-dot-claude` is not needed here since this skill doesn't touch `.claude/`.
