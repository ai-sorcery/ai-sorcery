# llm-routing/

Local scaffolding for routing a coding agent (Swival) through a single
OpenAI-compatible endpoint (LiteLLM proxy) that fans out to many
providers — Anthropic, OpenAI, Hugging Face Inference Providers,
DeepSeek, Moonshot (Kimi), MiniMax — and lets you swap between them by
changing one `--profile` flag.

## Quick start

```bash
# 1. Bootstrap the toolchain (Nix dev shell + uv venv + swival).
#    Idempotent — re-run any time.
./llm-routing/setup.sh

# 2. Fill in provider keys.
cp .env.example .env
$EDITOR .env

# 3. Boot the pipeline: starts the proxy if needed, polls /health/readiness
#    for readiness, drops you into a Swival session pointed at it.
./llm.sh                  # default profile: claude
./llm.sh cheap            # or frontier / balanced / claude
./llm.sh --profile cheap  # any swival flag passes through
```

The wizard interface (status, retarget tiers, verify aliases, observability):

```bash
./llm-routing/route.sh
```

## What lands where

```
.
├── llm.sh                      # boot-the-pipeline shortcut (at repo root)
├── swival.toml                 # Swival profiles (Swival looks here)
├── .env.example                # template — copy to .env and fill in
├── .env                        # your provider keys (git-ignored)
└── llm-routing/
    ├── setup.sh                # one-shot bootstrap (Nix, .venv, swival)
    ├── flake.nix               # dev shell — python 3.13, bun, uv, …
    ├── route.sh                # wizard entry + sub-commands
    ├── wizard.ts               # interactive menu
    ├── status.ts               # one-shot status report
    ├── observability.ts        # tail / costs viewer for the request log
    ├── start-proxy.sh          # launches LiteLLM on 127.0.0.1:4000
    ├── stop-proxy.sh           # SIGTERM, then SIGKILL after 5s
    ├── litellm.config.yaml     # router config — model aliases, fallbacks
    ├── providers.json          # provider catalog (env, signup URL, picks)
    ├── .venv/                  # uv-managed Python venv (git-ignored)
    └── logs/                   # litellm.pid, litellm.log (git-ignored)
```

## How the pieces fit

```
  ┌─────────┐    OpenAI-compatible    ┌────────────────┐
  │ swival  │ ───────────────────────▶│ litellm proxy  │
  │ --profile│                         │  127.0.0.1:4000│
  └─────────┘                         └────────┬───────┘
                                               │ provider-specific
                              ┌────────────────┼────────────────────┐
                              │                │                    │
                              ▼                ▼                    ▼
                       Anthropic API     OpenAI API     Hugging Face Inference Providers
                       DeepSeek API   Moonshot (Kimi)   MiniMax (OpenAI-compatible)
```

Swival never speaks a provider's native protocol. It always talks
OpenAI-shape to the local proxy; the proxy translates and dispatches.

That means:

- Adding a new model is one stanza in `litellm.config.yaml`.
- Swapping which model `frontier` points at is one line in the same
  file (under `router_settings.model_group_alias`), or one menu choice
  in the wizard (`Re-target a tier alias`).
- Trying a new provider doesn't touch Swival at all.

## Tier aliases

`litellm.config.yaml` ships four tier aliases. Use these from clients
to keep model choices out of code:

| Tier      | Default target      | Why |
|-----------|---------------------|-----|
| frontier  | `deepseek-v4-pro`   | First-party DeepSeek V4 Pro. Falls back to the same model on HF Together (`hf-deepseek-v4-pro`) first, so a DeepSeek-side blip doesn't change the model under the request. |
| balanced  | `kimi-k2`           | Strong long-context coding model via Moonshot. |
| cheap     | `deepseek-v4-flash` | First-party DeepSeek V4 Flash (the current `deepseek-chat` and `deepseek-reasoner` legacy aliases also point here). |
| claude    | `claude-opus-1m`    | Opus 4.7 with the 1M-context beta enabled. Kept on its own tier so the generic frontier/balanced/cheap tiers don't implicitly require an Anthropic key. |

Each tier's resolved target has a provider-diversified fallback chain
configured in `router_settings.fallbacks`, so a 429/5xx/timeout on the
primary cascades to alternates on different providers.

Re-target with the wizard's `Re-target a tier alias` choice, or edit
`router_settings.model_group_alias` in `litellm.config.yaml`.

## Provider keys

Keys live in `.env` at the repo root (next to `llm.sh`). The wrapper
scripts source it before launching the proxy, so a fresh shell isn't
required. `.env.example` lists every variable the shipped config
references — copy it, keep the lines you have, delete the rest.

```bash
cp .env.example .env
$EDITOR .env
```

The proxy only fails when a request targets a model whose key is
missing. Tier aliases inherit their target's env requirement: with
`HF_TOKEN` set but `DEEPSEEK_API_KEY` unset, a request to `frontier`
(→ `deepseek-v4-pro`) falls through to `hf-qwen3-coder` via the
fallback chain.

## Observability

The proxy writes structured JSON to stdout (`litellm_settings.json_logs:
true`); `start-proxy.sh` redirects that to `logs/litellm.log`. View it
without leaving the shell:

```bash
./route.sh tail               # last 20 request records, columnar
./route.sh costs              # totals per model — count, tokens, $
./route.sh verify             # ping each alias, report pass/fail
```

For correlation, prefer `litellm_call_id` (the canonical UUID) over the
upstream's `response.id` (varies by provider). Clients can attach a
per-request `metadata.user_correlation_id` in the request body —
LiteLLM threads it into the record so test runs can match a record to
a known request without racing on response identity.

## Stopping cleanly

`Ctrl-C` if the proxy is in the foreground; `./route.sh stop` (or
`./stop-proxy.sh`) otherwise. The stop script sends SIGTERM, waits 5 s,
and SIGKILLs if the process hasn't exited.
