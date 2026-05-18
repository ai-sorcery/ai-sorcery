#!/usr/bin/env bash
#
# setup.sh — one-shot bootstrap for the llm-routing scaffold.
#
# Idempotent. Steps:
#   1. Ensure nix is installed (runs the Determinate Systems installer
#      if not — that installer is itself interactive and asks for sudo).
#   2. Ensure brew is on PATH (required for swival).
#   3. Enter the flake's dev shell, then:
#      a. Create a project-local .venv with Python 3.13 via uv.
#      b. uv pip install 'litellm[proxy]' into .venv.
#      c. brew install swival/tap/swival if not already on PATH.
#
# Re-run any time — each step skips when already satisfied.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

source_nix_profile() {
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    /etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -f "$profile" ]]; then
      # shellcheck disable=SC1090
      . "$profile"
      return 0
    fi
  done
  return 1
}

# --- Step 1: ensure nix --------------------------------------------------
if ! command -v nix >/dev/null 2>&1; then
  # nix may be installed but missing from this shell's PATH.
  source_nix_profile || true
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "[setup] Nix not installed — running the Determinate Systems installer."
  echo "[setup] sudo is required: the installer creates the /nix APFS volume,"
  echo "[setup] registers the nix-daemon, and edits /etc/synthetic.conf."
  echo "[setup] Priming sudo now so the install runs unattended."
  echo "[setup] Ctrl-C at the prompt to back out."
  echo
  # Cache sudo credentials up front so the installer doesn't hit a
  # TTY-bound prompt mid-run. --no-confirm tells the Determinate
  # installer to accept its own defaults without prompting (without it,
  # the installer refuses to run when stdin isn't a TTY).
  sudo -v
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  source_nix_profile || true
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "[setup] Nix install finished but nix is still not on PATH in this shell." >&2
  echo "[setup] Open a new terminal (or 'exec \$SHELL -l') and re-run ./setup.sh." >&2
  exit 1
fi

# --- Step 2: ensure brew (for swival) ------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  echo "[setup] Homebrew is required for installing swival." >&2
  echo "[setup] Install it first: https://brew.sh" >&2
  exit 1
fi

# --- Step 3: enter dev shell and run the rest ----------------------------
echo "[setup] entering nix dev shell to install LiteLLM deps + swival"
export SETUP_DIR="$script_dir"
exec nix develop "$script_dir" --command bash -c '
  set -euo pipefail
  cd "$SETUP_DIR"

  if [[ ! -d .venv ]]; then
    echo "[setup] creating .venv (3.13)"
    uv venv .venv -p 3.13
  else
    echo "[setup] .venv already exists — reusing"
  fi

  # Activate the venv so uv pip install targets it (sets VIRTUAL_ENV).
  # shellcheck disable=SC1091
  . .venv/bin/activate

  echo "[setup] installing litellm[proxy] into .venv"
  uv pip install "litellm[proxy]"

  if ! command -v swival >/dev/null 2>&1; then
    echo "[setup] installing swival via brew tap"
    brew install swival/tap/swival
  else
    echo "[setup] swival already on PATH at $(command -v swival)"
  fi

  echo
  echo "[setup] done."
  echo
  echo "Next steps:"
  echo "  1. Copy .env.example → .env at the repo root and fill in your"
  echo "     provider keys (only those you actually have)."
  echo "  2. Run ./llm.sh from the repo root to start the proxy and"
  echo "     open a swival session. (Or ./llm-routing/route.sh for the"
  echo "     wizard interface.)"
'
