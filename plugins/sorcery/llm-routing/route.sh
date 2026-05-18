#!/usr/bin/env bash
#
# route.sh — entry point for the llm-routing scaffolding. With no args,
# launches the interactive wizard. Sub-commands let you script the
# individual actions without going through the menu.
#
# Sub-commands:
#   status              one-shot status report (no menu, no prompts)
#   start [--detach]    start the LiteLLM proxy (idempotent — no-op if up)
#   stop                stop the LiteLLM proxy
#   test [model [prompt]]   send a one-line test prompt through the proxy
#                       (default model alias: cheap)
#   verify              ping every model_name alias and report pass/fail
#   tail [--last N]     print the last N (default 20) request records
#   costs               aggregate cost-per-model from the request log
#   wizard              the interactive menu (same as no args)
#
# Designed to be the single thing the user has to remember. Everything
# else (litellm.config.yaml, swival.toml, start/stop scripts) is
# reachable from inside the wizard.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

# --- Source .env at the repo root if present -----------------------------
if [[ -f "$project_root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$project_root/.env"
  set +a
fi

# --- Re-exec inside the nix dev shell ------------------------------------
if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  if ! command -v nix >/dev/null 2>&1; then
    echo "route: nix not on PATH. Run ./setup.sh first." >&2
    exit 1
  fi
  exec nix develop "$script_dir" --command bash "$0" "$@"
fi

cd "$script_dir"

require() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "route: required tool '$cmd' not on PATH" >&2
    echo "       $hint" >&2
    return 1
  fi
}

# bun is always required — every interactive action is a Bun TS script.
if ! require bun "install via the dev shell (./setup.sh) or: brew install oven-sh/bun/bun"; then
  exit 1
fi

cmd="${1:-wizard}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  status)
    exec bun run status.ts
    ;;
  start)
    exec bash start-proxy.sh "$@"
    ;;
  stop)
    exec bash stop-proxy.sh "$@"
    ;;
  test)
    model="${1:-cheap}"
    prompt="${2:-say hi in five words}"

    # JSON-encode via Bun so quotes, percents, newlines, and backslashes
    # in the prompt survive intact.
    body=$(MODEL="$model" PROMPT="$prompt" bun -e '
      console.log(JSON.stringify({
        model: process.env.MODEL,
        messages: [{ role: "user", content: process.env.PROMPT }],
        max_tokens: 256,
      }))
    ')

    # Capture status + body separately so we can exit non-zero on
    # upstream errors and surface the parsed problem instead of a raw
    # JSON blob.
    tmp_body="$(mktemp)"
    trap 'rm -f "$tmp_body"' EXIT
    http_status=$(curl --silent --show-error --output "$tmp_body" --write-out '%{http_code}' \
        --header 'content-type: application/json' \
        --header 'authorization: Bearer not-needed' \
        --data "$body" \
        http://127.0.0.1:4000/v1/chat/completions || echo "000")

    MODEL="$model" STATUS="$http_status" BODY_FILE="$tmp_body" bun -e '
      const fs = await import("node:fs");
      const status = parseInt(process.env.STATUS, 10);
      const model = process.env.MODEL;
      const body = fs.readFileSync(process.env.BODY_FILE, "utf-8");
      let j; try { j = JSON.parse(body); } catch { j = null; }

      // Successful chat completion shape.
      if (status >= 200 && status < 300 && j?.choices?.[0]?.message?.content) {
        process.stdout.write(j.choices[0].message.content + "\n");
        process.exit(0);
      }

      // Upstream / proxy error — parsed and informative, not a raw blob.
      const errCode = j?.error?.code ?? j?.error?.type ?? "";
      const errMsg  = j?.error?.message ?? body.trim() || "(empty body)";
      const isModelNotFound =
        status === 404 ||
        /not.*found/i.test(errCode + " " + errMsg) ||
        /Invalid model/i.test(errMsg);

      console.error(`route test: HTTP ${status || "no response"} — model=${model}`);
      if (errCode) console.error(`  code: ${errCode}`);
      console.error(`  message: ${errMsg.slice(0, 400)}`);

      // "did you mean" hint when the alias is unknown.
      if (isModelNotFound) {
        try {
          const yaml = fs.readFileSync("litellm.config.yaml", "utf-8");
          const known = [
            ...yaml.matchAll(/^\s*- model_name:\s*(\S+)/gm),
            ...yaml.matchAll(/^\s+(frontier|balanced|cheap|claude):\s*(\S+)/gm),
          ].map((m) => m[1] || "").filter(Boolean);
          const uniq = Array.from(new Set(known));
          // Rank by simple substring/Levenshtein-ish distance.
          const lower = model.toLowerCase();
          const scored = uniq
            .map((n) => ({ n, score: n.toLowerCase().includes(lower) ? 0 : 1 }))
            .sort((a, b) => a.score - b.score)
            .slice(0, 5);
          if (scored.length) {
            console.error(`  did you mean: ${scored.map((s) => s.n).join(", ")}`);
            console.error(`  full list:    ./route.sh status  (under "LiteLLM model aliases")`);
          }
        } catch { /* litellm.config.yaml unreadable — skip the hint */ }
      }
      process.exit(1);
    '
    ;;
  verify)
    exec bun run wizard.ts --verify
    ;;
  tail)
    exec bun run observability.ts tail "$@"
    ;;
  costs)
    exec bun run observability.ts costs "$@"
    ;;
  wizard|menu)
    exec bun run wizard.ts
    ;;
  help|-h|--help)
    sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "route: unknown sub-command '$cmd'" >&2
    echo "       try: ./route.sh help" >&2
    exit 2
    ;;
esac
