# routing-llm-calls

Scaffolds an `llm-routing/` directory plus a small set of repo-root
entrypoints with:

- A LiteLLM proxy config preloaded with model aliases for Anthropic,
  OpenAI, Hugging Face Inference Providers, DeepSeek, Moonshot (Kimi),
  and MiniMax.
- Tier aliases `frontier` / `balanced` / `cheap` (provider-diversified,
  no implicit Anthropic dependency) plus a dedicated `claude` tier
  (Opus 4.7 with 1M context, falling back to Sonnet then Haiku).
- A Swival coding-agent config preloaded with profiles that target the
  local proxy by tier or by named model.
- A Nix flake (`flake.nix`) that pins the toolchain (Python 3.13, Bun,
  uv) — `setup.sh` installs Nix via the Determinate installer if it's
  not already present, then provisions a project-local `.venv` for
  LiteLLM and brew-installs `swival/tap/swival`.
- An `llm.sh` at the repo root that starts the proxy on first call
  (idempotent), polls for readiness, then exec's Swival with explicit
  flags pointed at the local proxy.
- A wizard (`./llm-routing/route.sh`) for status, key setup, alias
  verification, tier re-targeting, request-log tail, and cost
  aggregation.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.

## What lands where

```
.
├── llm.sh                      # boot-the-pipeline shortcut (repo root)
├── swival.toml                 # Swival profiles at the path Swival looks
├── .env.example                # template — copy to .env, fill in keys
└── llm-routing/
    ├── setup.sh                # one-shot bootstrap (Nix, .venv, brew)
    ├── flake.nix               # dev shell: python 3.13, bun, uv, …
    ├── route.sh                # wizard + sub-commands
    ├── wizard.ts               # interactive menu
    ├── status.ts               # env/config inspector
    ├── observability.ts        # tail / costs viewer for the request log
    ├── start-proxy.sh          # launches LiteLLM on 127.0.0.1:4000
    ├── stop-proxy.sh           # SIGTERM via pidfile, SIGKILL after 5s
    ├── litellm.config.yaml     # router config — model aliases + fallbacks
    ├── providers.json          # catalog: env var, signup URL, picks
    ├── README.md               # repo-rooted version of the README
    ├── .venv/                  # uv-managed Python venv (git-ignored)
    └── logs/                   # litellm.pid + litellm.log (git-ignored)
```

The repo's root `.gitignore` is extended (idempotently) with `.env` and
`.swival/` so a first `git add .` after a Swival session doesn't
quietly stage provider keys or prompt transcripts.

## Quick start

```bash
./llm-routing/setup.sh        # one-time: Nix + .venv + swival
cp .env.example .env          # one-time: fill in provider keys
$EDITOR .env

./llm.sh                      # default profile: claude
./llm.sh cheap                # or frontier / balanced / claude
./llm-routing/route.sh        # status + wizard menu
```

## Architecture

```
swival ──OpenAI-compatible──▶ litellm proxy ──provider-specific──▶ Anthropic / OpenAI / HF / DeepSeek / Moonshot / MiniMax
```

Swival never speaks a provider's native protocol — it always talks
OpenAI-shape to the local proxy. Adding a new model is one stanza in
`litellm.config.yaml`. Re-targeting `frontier` at a new winner is one
line under `router_settings.model_group_alias` (or one wizard menu
choice). The Swival side never changes.
