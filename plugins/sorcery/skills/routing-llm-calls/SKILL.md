---
name: routing-llm-calls
description: Use when the user wants a quick-start setup for routing a coding agent through many LLM providers — phrasings like "set up LiteLLM", "I want to try DeepSeek/Kimi/Qwen/MiniMax", "let me switch between OpenAI and Claude and Hugging Face from one place", "set me up with Swival", "route my coding agent through multiple models", "experiment with cheap vs frontier LLMs", "bootstrap a multi-provider LLM setup". Scaffolds an `llm-routing/` directory plus repo-root entrypoints (`llm.sh`, `swival.toml`, `.env.example`), with LiteLLM as the OpenAI-compatible router and Swival as the coding agent. Toolchain is pinned via a Nix flake; `setup.sh` auto-installs Nix via the Determinate installer when missing.
---

# Routing LLM Calls

Drops two things into the current repo:

1. An `llm-routing/` directory at the repo root containing the Nix
   flake, the LiteLLM proxy config (with tier aliases and fallback
   chains preloaded), the wizard (`route.sh`), and the proxy lifecycle
   scripts.
2. A small set of repo-root entrypoints:
   - `llm.sh` — boot-the-pipeline shortcut. Starts the proxy on first
     call (idempotent), polls `/health/readiness`, and exec's
     Swival with explicit `--provider/--base-url/--model/--api-key`
     flags so cwd doesn't matter.
   - `swival.toml` — at the exact path Swival looks for project config.
     Profiles point at the loopback proxy by tier name.
   - `.env.example` — template for provider keys. `llm.sh` and
     `route.sh` source `.env` before launching the proxy.

Tier aliases ship provider-diversified — `frontier → deepseek-v4-pro`,
`balanced → kimi-k2`, `cheap → deepseek-v4-flash`. The frontier tier's
first fallback is the same V4-Pro model on HF Together, so a
DeepSeek-side blip doesn't change the model under the request. Claude
lives on a dedicated `claude` tier (Opus 4.7 with the 1M-context beta,
falling back to Sonnet then Haiku via `router_settings.fallbacks`).
The generic tiers don't implicitly require `ANTHROPIC_API_KEY`.

The toolchain is pinned in `llm-routing/flake.nix` (Python 3.13, Bun,
uv, plus standard CLI bits). `setup.sh` runs the Determinate Systems
Nix installer if Nix is missing, enters the dev shell, creates a
project-local `.venv` with `uv venv --python 3.13`, installs
`litellm[proxy]` into it, and brew-installs `swival/tap/swival`.

## What to do

Run the bundled installer from anywhere inside the user's current repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/llm-routing/install-llm-routing.sh"
```

The installer copies the canonical files into the two destinations
(`./` and `./llm-routing/`), seeds `llm-routing/logs/` and
`llm-routing/.gitignore`, and idempotently extends the repo's root
`.gitignore` with `.env` and `.swival/` so a first `git add .` after
a Swival session doesn't quietly stage provider keys or per-cwd
transcripts. Files already present are left alone — a user who has
customised `litellm.config.yaml` or `swival.toml` keeps their edits on
re-run.

After the install, tell the user the three follow-ups:

1. **Bootstrap the toolchain** (idempotent — re-run any time):
   ```bash
   cd llm-routing && ./setup.sh
   ```
   This installs Nix via the Determinate installer if missing
   (interactive, asks for sudo), enters the dev shell, creates `.venv`
   with Python 3.13, installs `litellm[proxy]`, and `brew install`s
   swival.
2. **Fill in keys**:
   ```bash
   cp .env.example .env && $EDITOR .env
   ```
3. **Boot a session**:
   ```bash
   ./llm.sh             # default profile: claude
   ./llm.sh cheap       # or frontier / balanced / claude
   ```
   The wizard interface (`./llm-routing/route.sh`) covers status,
   alias verification, tier re-targeting, request-log tail, and cost
   aggregation.

The user doesn't need every provider — LiteLLM only fails when a
request targets a model whose key is missing, and the fallback chain
catches single-provider gaps.

## What lands in the user's repo

```
.
├── llm.sh                      # boot-the-pipeline shortcut (repo root)
├── swival.toml                 # Swival profiles (at the path it expects)
├── .env.example                # template — copy to .env, fill in keys
└── llm-routing/
    ├── setup.sh                # one-shot bootstrap (Nix, .venv, brew)
    ├── flake.nix               # dev shell: python 3.13, bun, uv, …
    ├── route.sh                # wizard + sub-commands
    ├── wizard.ts               # interactive menu (status, verify, retarget)
    ├── status.ts               # env/config/proxy inspector
    ├── observability.ts        # tail / costs viewer
    ├── start-proxy.sh          # idempotent — exits 0 if already running
    ├── stop-proxy.sh           # SIGTERM via pidfile, SIGKILL after 5s
    ├── litellm.config.yaml     # router config — aliases + fallbacks
    ├── providers.json          # catalog: env var, signup URL, picks
    ├── README.md               # repo-rooted version of the README
    └── logs/                   # litellm.pid + litellm.log (git-ignored)
```

The repo's root `.gitignore` gets `.env` and `.swival/` appended
(idempotent — no-ops if either is already there).

## Wizard menu

After printing the status report, `wizard.ts` shows:

```
── llm-routing wizard ──
   1) Show status (keys, models, proxy)
   2) Start the LiteLLM proxy
   3) Stop the LiteLLM proxy
   4) Send a test prompt through the proxy
   5) Verify all model aliases (ping each one)
   6) List all model aliases
   7) Tail the request log
   8) Aggregate costs by model
   9) Set up provider API keys
  10) Edit litellm.config.yaml
  11) Edit swival.toml (at repo root)
  12) Re-target a tier alias
  13) Show recommended model picks
   q) quit
```

Every menu choice returns to the menu when it's done so the user can
do a full setup without re-launching.

## How it works internally

- **LiteLLM is the router.** OpenAI-compatible proxy on
  `http://127.0.0.1:4000`. Clients POST to `/v1/chat/completions` with
  a `model` field; LiteLLM dispatches to the upstream based on the
  `model_name` declared in `litellm.config.yaml`. Provider secrets are
  pulled from `os.environ/<NAME>` at proxy-start time.
- **Tier aliases** (`router_settings.model_group_alias`) give clients
  stable names (`frontier`/`balanced`/`cheap`/`claude`) that resolve to
  concrete model_names. Swap the right-hand side when a new winner
  shows up; client code keeps asking for the tier name.
- **Fallback chains** (`router_settings.fallbacks`) make each tier's
  target resilient to single-provider blips — when the primary returns
  429/5xx/timeout, the request cascades to alternates on different
  providers.
- **Swival is the coding-agent UI.** Its `generic` provider speaks the
  OpenAI shape, so every profile in `swival.toml` points at the local
  proxy. `llm.sh` invokes Swival with explicit flags so cwd doesn't
  matter and the per-cwd `swival.toml` lookup is bypassed.
- **The wizard is pure Bun TS.** No external npm deps, no Python in
  the user's code path. `status.ts`, `wizard.ts`, and `observability.ts`
  share a small naive YAML parser sufficient for configs produced by
  this skill.
- **`start-proxy.sh` is foreground-by-default, idempotent.** Pass
  `--detach` (or `DETACH=1`) to fork into the background. If a live
  proxy is already recorded in the pid file, the script exits 0 with
  "already running" instead of erroring — so wrappers can call it
  unconditionally.

## Caveats

- **`setup.sh` installs Nix when missing.** Via the Determinate
  Systems installer. That installer is third-party (a fork of upstream
  Nix), prompts for sudo, owns `/nix` via a managed APFS volume on
  macOS, and uninstalls cleanly. Tell the user this before running
  setup if they're not already on Nix.
- **DeepSeek's legacy `deepseek-chat` and `deepseek-reasoner` model ids
  are slated for deprecation** per DeepSeek's own docs. The shipped
  cheap tier points at `deepseek-v4-flash` (the current id); the
  legacy aliases are kept in `model_list` for back-compat but new
  work should target the V4 ids.
- **Local proxy has no auth in front of it.** Bound to `127.0.0.1:4000`.
  If the user wants to expose it off-host, uncomment `master_key:` in
  `litellm.config.yaml` and update the `--api-key` flag in `llm.sh`.
- **MiniMax routes via the OpenAI provider with `api_base` override.**
  MiniMax exposes an OpenAI-compatible endpoint, so LiteLLM dispatches
  it through the `openai/` driver pointed at `https://api.minimax.io/v1`.
- **Model identifiers age.** The shipped `claude-opus-4-7`, `gpt-5`,
  `kimi-k2.6`, etc. are correct at scaffold time but providers retire
  and rename models. The wizard's `Verify all model aliases` choice
  pings each one and reports which still work; a 404 from a reachable
  alias is flagged as a likely-retired upstream id rather than a
  transient error.
- **`anthropic-beta: context-1m-2025-08-07` is the current 1M-context
  beta tag.** Anthropic bumps the tag occasionally; if Opus calls start
  failing with a beta-header error, update `extra_headers` in the
  `claude-opus-1m` stanza of `litellm.config.yaml`.
- **`logs/` and `.venv/` are per-machine.** Both are git-ignored.

## When not to use

- **One provider only.** If the user only ever wants to talk to
  Anthropic, skipping LiteLLM and pointing Swival straight at the
  Anthropic API is simpler. This skill earns its keep when the user
  wants to swap providers, A/B them against a workload, or pair a
  frontier model with a cheap one without rewriting client config.
- **A different coding agent.** Skills bundling specific agent UIs
  (Cursor, Aider, Cline) need their own scaffolding. The LiteLLM half
  is reusable — fork this skill and swap the Swival config for the
  target agent's config format.
- **Production traffic.** This is a single-user, loopback-only setup.
  Use LiteLLM's hosted cloud or a properly secured self-hosted
  deployment for shared or production use.

## Related skills

- `launching-claude` — pairs naturally if the user wants to keep the
  Claude Code launcher alongside Swival for the cases where they want
  first-party Claude features (memory, plugins, etc.) that don't go
  through an OpenAI-compatible shim.
- `using-llm-tasks` — task workflow for project work; combines with
  this skill to run a queue of work through a chosen model tier.
- `following-best-practices` — for scanning a real project for day-one
  gaps; not bundled into this skill because routing setup is opt-in,
  not universal.
