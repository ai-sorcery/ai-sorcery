# capturing-test-fixtures

Captures real-world web pages as test fixtures with three artifacts per fixture: the raw original (never modified), a `.meta.json` companion documenting provenance (source URL, capture timestamp, capture method, notes), and a simplified version tests load fast. Bundles `capture.sh` (curl or Playwright-rendered DOM), `strip.ts` (Bun + `HTMLRewriter` mechanical noise removal — scripts, styles, comments, link, meta), and a small Playwright entry script.

Simplification splits into two passes: the script does the always-safe mechanical strip, then the LLM does a test-aware semantic trim that drops everything irrelevant to the assertions the specific test makes. The LLM step is the one a script cannot do.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads.
