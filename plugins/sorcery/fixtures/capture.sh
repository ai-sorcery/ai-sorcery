#!/usr/bin/env bash
set -euo pipefail

# capture.sh — fetch a URL into an originals/ tree with a .meta.json companion.
#
# Usage:
#   capture.sh <url> <output-base>
#              [--render]
#              [--wait-until=<load|domcontentloaded|networkidle|commit>]
#              [--cookie=<value>]
#              [--header=<k:v>]...
#              [--notes=<text>]
#              [--strip]
#
# <output-base> is a path *without* extension. The script writes:
#   $(dirname <output-base>)/originals/$(basename <output-base>).html
#   $(dirname <output-base>)/originals/$(basename <output-base>).meta.json
#
# Example:
#   capture.sh https://example.com/products/123 tests/fixtures/products/listing
# →   tests/fixtures/products/originals/listing.html
#     tests/fixtures/products/originals/listing.meta.json
#
# With --strip, also runs the bundled strip.ts pass to write a mechanically
# de-noised sibling at <output-base>.html. The semantic, test-aware
# simplification (drop everything irrelevant to what the test asserts on) is
# the LLM's job in a separate pass — see the parent skill's "Simplify"
# section.

USAGE='Usage: capture.sh <url> <output-base> [--render] [--wait-until=<event>] [--extra-wait-ms=<int>] [--cookie=<value>] [--header=<k:v>]... [--notes=<text>] [--strip]'

# Resolve our own directory through any symlinks so sibling scripts
# (render.mjs, strip.ts) are found whether the user invokes us directly, via
# a symlink, or through ${CLAUDE_PLUGIN_ROOT}. macOS lacks `readlink -f` and
# `realpath` in the base install, so this is the portable readlink-loop idiom.
__src="${BASH_SOURCE[0]}"
while [[ -L "$__src" ]]; do
  __dir="$(cd -P "$(dirname "$__src")" >/dev/null && pwd)"
  __src="$(readlink "$__src")"
  [[ "$__src" != /* ]] && __src="$__dir/$__src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$__src")" >/dev/null && pwd)"
unset __src __dir

URL=""
BASE=""
RENDER=0
STRIP=0
WAIT_UNTIL=""
EXTRA_WAIT_MS=""  # empty = use the render-mode default (7000)
COOKIE=""
NOTES=""
HEADERS=()

while (( $# )); do
  case "$1" in
    --render)            RENDER=1 ;;
    --strip)             STRIP=1 ;;
    --wait-until=*)      WAIT_UNTIL="${1#--wait-until=}" ;;
    --extra-wait-ms=*)   EXTRA_WAIT_MS="${1#--extra-wait-ms=}" ;;
    --cookie=*)          COOKIE="${1#--cookie=}" ;;
    --header=*)          HEADERS+=("${1#--header=}") ;;
    --notes=*)           NOTES="${1#--notes=}" ;;
    -h|--help)           echo "$USAGE"; exit 0 ;;
    --*)                 echo "capture.sh: unknown flag $1" >&2; exit 2 ;;
    *)
      if   [[ -z "$URL"  ]]; then URL="$1"
      elif [[ -z "$BASE" ]]; then BASE="$1"
      else echo "capture.sh: too many positional args" >&2; echo "$USAGE" >&2; exit 2
      fi
      ;;
  esac
  shift
done

if [[ -z "$URL" || -z "$BASE" ]]; then
  echo "$USAGE" >&2
  exit 2
fi

# --cookie is curl-native. In --render mode, passing cookies as a Cookie:
# header is the portable path (Playwright forwards arbitrary request headers
# without needing a per-cookie domain/path map).
if (( RENDER )) && [[ -n "$COOKIE" ]]; then
  echo "capture.sh: --cookie is not supported with --render." >&2
  echo "  Pass cookies as a header instead, for example:" >&2
  echo "    --header=\"Cookie: \$YOUR_COOKIE_STRING\"" >&2
  exit 2
fi

if (( ! RENDER )) && [[ -n "$WAIT_UNTIL" ]]; then
  echo "capture.sh: --wait-until applies only with --render." >&2
  exit 2
fi

if (( ! RENDER )) && [[ -n "$EXTRA_WAIT_MS" ]]; then
  echo "capture.sh: --extra-wait-ms applies only with --render." >&2
  exit 2
fi

# --extra-wait-ms must be a non-negative integer. Validate before fetch so a
# typo does not blow up inside the headless browser after Chromium launches.
if [[ -n "$EXTRA_WAIT_MS" ]]; then
  if ! [[ "$EXTRA_WAIT_MS" =~ ^[0-9]+$ ]]; then
    echo "capture.sh: --extra-wait-ms must be a non-negative integer (milliseconds)" >&2
    exit 2
  fi
fi

# Pre-validate header values before any fetch. Catching format errors here
# beats silent loss in render mode (where a header without a colon would be
# dropped before reaching Playwright) or the surprise of duplicate-name
# headers being merged last-write-wins by jq's `add`.
if (( ${#HEADERS[@]} > 0 )); then
  declare -a SEEN_HEADER_NAMES=()
  HAS_COOKIE_HEADER=0
  for h in "${HEADERS[@]}"; do
    if [[ "$h" != *:* ]]; then
      echo "capture.sh: --header value must be 'Name: Value' — got: $h" >&2
      exit 2
    fi
    name="${h%%:*}"
    name_lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$name_lower" == "cookie" ]]; then
      HAS_COOKIE_HEADER=1
    fi
    for prev in "${SEEN_HEADER_NAMES[@]:-}"; do
      if [[ "$prev" == "$name_lower" ]]; then
        echo "capture.sh: duplicate --header name '$name' — combine values into one header." >&2
        exit 2
      fi
    done
    SEEN_HEADER_NAMES+=("$name_lower")
  done

  # Pairing --cookie with --header="Cookie: ..." would put the cookie value
  # into the meta.json's verbatim headers array AND flip the redaction flag,
  # which is misleading. Refuse the combo so there is one source of truth.
  if (( HAS_COOKIE_HEADER )) && [[ -n "$COOKIE" ]]; then
    echo "capture.sh: pass cookies via --cookie OR --header=\"Cookie: ...\", not both." >&2
    exit 2
  fi
fi

# Validate --wait-until against Playwright's documented event names rather than
# letting Chromium launch first and fail mid-render on a typo.
if [[ -n "$WAIT_UNTIL" ]]; then
  case "$WAIT_UNTIL" in
    load|domcontentloaded|networkidle|commit) ;;
    *)
      echo "capture.sh: --wait-until must be one of: load, domcontentloaded, networkidle, commit" >&2
      exit 2
      ;;
  esac
fi

command -v jq >/dev/null 2>&1 || { echo "capture.sh: jq is required" >&2; exit 1; }

DIR="$(dirname "$BASE")"
NAME="$(basename "$BASE")"
ORIG_DIR="$DIR/originals"
HTML_PATH="$ORIG_DIR/$NAME.html"
META_PATH="$ORIG_DIR/$NAME.meta.json"
STRIPPED_PATH="$DIR/$NAME.html"

CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Capture into a tempfile and only move into place on success — a failed
# fetch must not leave behind a half-written original or a bare meta.json.
TMP_HTML="$(mktemp -t capture.XXXXXX)"
trap 'rm -f "$TMP_HTML"' EXIT

if (( RENDER )); then
  RENDER_JS="$SCRIPT_DIR/render.mjs"
  [[ -f "$RENDER_JS" ]] || { echo "capture.sh: missing $RENDER_JS" >&2; exit 1; }

  if   command -v bun  >/dev/null 2>&1; then RUNNER=bun
  elif command -v node >/dev/null 2>&1; then RUNNER=node
  else
    echo "capture.sh: --render needs bun or node on PATH" >&2
    exit 1
  fi

  # Build extra-headers JSON object for Playwright. Duplicate names were
  # already refused above, so the merge is information-preserving.
  HEADERS_OBJECT='{}'
  if (( ${#HEADERS[@]} > 0 )); then
    HEADERS_OBJECT="$(
      printf '%s\n' "${HEADERS[@]}" \
        | jq -Rs 'split("\n") | map(select(length > 0) | capture("^(?<k>[^:]+):\\s*(?<v>.*)$") | {(.k): .v}) | add // {}'
    )"
  fi

  WAIT_UNTIL_EFFECTIVE="${WAIT_UNTIL:-domcontentloaded}"
  EXTRA_WAIT_MS_EFFECTIVE="${EXTRA_WAIT_MS:-7000}"

  CAPTURE_HEADERS="$HEADERS_OBJECT" \
  CAPTURE_WAIT_UNTIL="$WAIT_UNTIL_EFFECTIVE" \
  CAPTURE_EXTRA_WAIT_MS="$EXTRA_WAIT_MS_EFFECTIVE" \
  CAPTURE_INVOKER_CWD="$PWD" \
  "$RUNNER" "$RENDER_JS" "$URL" > "$TMP_HTML"

  CAPTURE_METHOD="playwright"
  USER_AGENT=""
else
  USER_AGENT='Mozilla/5.0 (X11; Linux x86_64; rv:145.0) Gecko/20100101 Firefox/145.0'
  CURL_ARGS=( -fsSL --compressed -A "$USER_AGENT" )
  [[ -n "$COOKIE" ]] && CURL_ARGS+=( -b "$COOKIE" )
  if (( ${#HEADERS[@]} > 0 )); then
    for h in "${HEADERS[@]}"; do CURL_ARGS+=( -H "$h" ); done
  fi
  CURL_ARGS+=( -o "$TMP_HTML" "$URL" )

  curl "${CURL_ARGS[@]}"
  CAPTURE_METHOD="curl"
  WAIT_UNTIL_EFFECTIVE=""
  EXTRA_WAIT_MS_EFFECTIVE=""
fi

# Only commit the destination directory once the fetch succeeded. mkdir is
# idempotent, but failing fetches leaving behind empty `originals/` dirs is
# noise we can avoid.
mkdir -p "$ORIG_DIR"
mv "$TMP_HTML" "$HTML_PATH"
chmod 644 "$HTML_PATH"  # mktemp creates 0600; align with sibling files written through umask
trap - EXIT

HEADERS_JSON='[]'
if (( ${#HEADERS[@]} > 0 )); then
  HEADERS_JSON="$(printf '%s\n' "${HEADERS[@]}" | jq -Rs 'split("\n") | map(select(length > 0))')"
fi

HAD_COOKIE='false'
[[ -n "$COOKIE" ]] && HAD_COOKIE='true'

EXTRA_WAIT_MS_JSON='null'
[[ -n "$EXTRA_WAIT_MS_EFFECTIVE" ]] && EXTRA_WAIT_MS_JSON="$EXTRA_WAIT_MS_EFFECTIVE"

jq -n \
  --arg sourceUrl       "$URL" \
  --arg capturedAt      "$CAPTURED_AT" \
  --arg captureMethod   "$CAPTURE_METHOD" \
  --arg userAgent       "$USER_AGENT" \
  --arg waitUntil       "$WAIT_UNTIL_EFFECTIVE" \
  --argjson extraWaitMs "$EXTRA_WAIT_MS_JSON" \
  --argjson headers     "$HEADERS_JSON" \
  --argjson hadCookie   "$HAD_COOKIE" \
  --arg notes           "$NOTES" \
  '
  {sourceUrl: $sourceUrl, capturedAt: $capturedAt, captureMethod: $captureMethod}
  + (if $userAgent != ""        then {userAgent: $userAgent}     else {} end)
  + (if $waitUntil != ""        then {waitUntil: $waitUntil}     else {} end)
  + (if $extraWaitMs != null    then {extraWaitMs: $extraWaitMs} else {} end)
  + (if ($headers | length) > 0 then {headers: $headers}         else {} end)
  + (if $hadCookie              then {cookies: "redacted"}       else {} end)
  + (if $notes != ""            then {notes: $notes}             else {} end)
  ' > "$META_PATH"

echo "Wrote $HTML_PATH"
echo "Wrote $META_PATH"

if (( STRIP )); then
  command -v bun >/dev/null 2>&1 || {
    echo "capture.sh: --strip needs bun on PATH (strip.ts uses Bun's HTMLRewriter)" >&2
    exit 1
  }
  echo "Stripping..."
  "$SCRIPT_DIR/strip.ts" "$HTML_PATH" "$STRIPPED_PATH"
fi
