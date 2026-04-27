#!/usr/bin/env node
// render.mjs — invoked by capture.sh in --render mode. Loads a URL in headless
// Chromium via Playwright and writes the fully-rendered outerHTML to stdout.
//
// Resolves `playwright` against the user's CWD, not this script's directory,
// so a project-local install (e.g. via `bun add -d playwright`) is found. The
// surrounding capture.sh exports CAPTURE_INVOKER_CWD = $PWD before invoking.
//
// Inputs:
//   argv[2]                    URL to capture (required)
//   env.CAPTURE_WAIT_UNTIL     Playwright waitUntil event (default: domcontentloaded)
//   env.CAPTURE_EXTRA_WAIT_MS  Extra settle time after waitUntil fires (default: 0)
//   env.CAPTURE_HEADERS        JSON object of extra HTTP headers to forward (default: {})
//   env.CAPTURE_INVOKER_CWD    Resolution root for `require("playwright")`
//
// Exits non-zero on any failure so capture.sh can surface the error rather
// than persisting an empty fixture.

import { createRequire } from "node:module";
import { join } from "node:path";

const url = process.argv[2];
if (!url) {
  console.error("usage: render.mjs <url>");
  process.exit(2);
}

const cwd = process.env.CAPTURE_INVOKER_CWD || process.cwd();
const waitUntil = process.env.CAPTURE_WAIT_UNTIL || "domcontentloaded";
const extraWaitMs = Number.parseInt(process.env.CAPTURE_EXTRA_WAIT_MS ?? "0", 10);
const extraHTTPHeaders = JSON.parse(process.env.CAPTURE_HEADERS || "{}");

let chromium;
try {
  // createRequire anchored at the user's CWD lets `require("playwright")`
  // walk node_modules from there, finding the project-local install.
  const require = createRequire(join(cwd, "_"));
  ({ chromium } = require("playwright"));
} catch (e) {
  console.error("render.mjs: cannot resolve 'playwright' from " + cwd);
  console.error("  Install it with: bun add -d playwright && bunx playwright install chromium");
  process.exit(1);
}

let browser;
try {
  browser = await chromium.launch();
} catch (e) {
  const msg = String(e?.message ?? e);
  if (msg.includes("Executable doesn't exist")) {
    console.error("render.mjs: Chromium binary missing.");
    console.error("  Install it with: bunx playwright install chromium");
    process.exit(1);
  }
  console.error("render.mjs: failed to launch chromium: " + msg);
  process.exit(1);
}

try {
  const context = await browser.newContext({ extraHTTPHeaders });
  const page = await context.newPage();
  await page.goto(url, { waitUntil });
  if (extraWaitMs > 0) await page.waitForTimeout(extraWaitMs);
  process.stdout.write(await page.content());
} finally {
  await browser.close();
}
