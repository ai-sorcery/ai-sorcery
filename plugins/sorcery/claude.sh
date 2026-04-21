#!/usr/bin/env bash
# Launch Claude Code with privacy-friendly defaults; extra args pass through.
#
#   IS_DEMO=1                — hide email/org from the welcome banner
#                              (undocumented Anthropic env var, v2.1.116;
#                              also skips first-run onboarding prompts)
#   --rc                     — hidden CLI flag
#   --effort max             — deepest reasoning level
#   --model claude-opus-4-7  — pin to Opus 4.7

set -euo pipefail

exec env IS_DEMO=1 claude --rc --effort max --model claude-opus-4-7 "$@"
