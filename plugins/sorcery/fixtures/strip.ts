#!/usr/bin/env bun
// strip.ts — mechanical-only noise stripping for a captured HTML file. This
// is the always-safe tier that a script can do. The semantic, test-aware
// simplification (drop the parts the test does not assert on, keep just the
// minimum that exercises the parser) is the LLM's job in a separate pass —
// see the parent skill's "Simplify (LLM pass)" section.
//
// Removes, via Bun's HTMLRewriter (a real HTML parser, not regex):
//   - HTML comments
//   - <script> blocks, except <script type="application/ld+json">
//   - <style>
//   - <noscript>
//   - <link>
//   - <meta>, except <meta charset=...>
// Collapses trailing whitespace and runs of blank lines.
//
// Usage:
//   strip.ts <input-html> [<output-html>]
//
// When no output path is given, writes to stdout. When given, the parent
// directory is created if missing. Refuses input==output (different paths
// resolving to the same file are detected via realpathSync).

import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";

const usage = "Usage: strip.ts <input-html> [<output-html>]";

const [, , input, output] = process.argv;
if (!input) {
  console.error(usage);
  process.exit(2);
}

if (!existsSync(input)) {
  console.error(`strip.ts: not a file: ${input}`);
  process.exit(1);
}

if (output) {
  const inReal = realpathSync(input);
  let outReal: string | null = null;
  try {
    outReal = realpathSync(output);
  } catch {
    outReal = null;
  }
  if (outReal && inReal === outReal) {
    console.error(`strip.ts: input and output are the same file: ${input}`);
    console.error(
      "  Pass a distinct output path; in-place rewrites are not supported.",
    );
    process.exit(2);
  }
}

if (typeof HTMLRewriter === "undefined") {
  console.error(
    "strip.ts: HTMLRewriter is not available. Run this script under Bun.",
  );
  process.exit(1);
}

const original = readFileSync(input, "utf-8");

const transformed = await new HTMLRewriter()
  .onDocument({
    comments(comment) {
      comment.remove();
    },
  })
  .on("script", {
    element(el) {
      const type = el.getAttribute("type") ?? "";
      if (!/application\/ld\+json/i.test(type)) el.remove();
    },
  })
  .on("style, noscript, link", {
    element(el) {
      el.remove();
    },
  })
  .on("meta", {
    element(el) {
      const charset = el.getAttribute("charset");
      if (charset === null || charset.trim() === "") el.remove();
    },
  })
  .transform(new Response(original))
  .text();

// HTMLRewriter leaves blank lines where elements used to be. Collapse them
// so a stripped fixture diffs cleanly against the original where structure
// survived.
const cleaned = transformed
  .replace(/[ \t]+$/gm, "")
  .replace(/\n[ \t]*\n+/g, "\n\n");

if (!output) {
  process.stdout.write(cleaned);
} else {
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, cleaned);
  console.log(`Wrote ${output}`);
}
