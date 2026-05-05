---
name: capturing-test-fixtures
description: Use when the user wants to capture real-world web pages as test fixtures and store them with provenance — phrasings like "capture this page as a fixture", "set up test fixtures from real URLs", "snapshot this page for tests", "build a fixture from the live site", "I need a fixture for the parser tests". Bundles `capture.sh` (curl or Playwright-rendered DOM) and `strip.ts` (mechanical noise-stripping via Bun's HTMLRewriter) under the plugin's `fixtures/` directory. Codifies a two-pass simplification model — the script does the mechanical strip, then the LLM does a test-aware semantic trim — so every fixture is small, fast to load, and answers "where did this come from?" / "is it stale?" at a glance.
---

# Capturing Test Fixtures

Real HTML caught from the source beats hand-typed fakes. Tests that load real fixtures catch the bugs synthetic data hides — class names that drifted, missing fields, surprising whitespace, inconsistent encodings, layout the docs never mentioned.

The convention is three artifacts per fixture:

1. **The original** — exactly what the source served. Never modified after capture.
2. **The meta companion** — provenance: source URL, capture timestamp, capture method, notes.
3. **The simplified version** — what tests actually load. Built in two passes: a script-driven mechanical strip (always-safe noise removal), then an LLM-driven semantic trim (drop everything irrelevant to the specific test).

The originals are the source of truth; the simplified version is the working copy. Every fixture answers "where did this come from?" and "is it stale?" at a glance.

## Two passes, not one

The simplification work splits into a part a script can do reliably and a part it cannot:

- **The mechanical pass (`strip.ts`).** Removes things that are *always* noise: `<script>` blocks, `<style>` blocks, `<noscript>`, `<link>`, `<meta>` (other than `<meta charset>`), HTML comments. Idempotent and test-agnostic. Built on Bun's `HTMLRewriter` — a real HTML parser, not regex, so quoted attribute values containing `<` / `>` (data URLs, inline SVG, etc.) round-trip correctly.
- **The semantic pass (LLM).** Trims everything irrelevant to *this specific test*. If the test only asserts on a single sentence's structure, almost everything else can go. A script cannot reason about test relevance; that's the LLM's job. See the "Simplify (LLM pass)" section below.

Result: a fixture an order of magnitude smaller than the original, with the mechanical pass done deterministically and the semantic pass done by a reader who knows what the test is actually checking.

## File layout

```
tests/fixtures/<feature>/
  originals/
    <name>.html          # raw source — never edited after capture
    <name>.meta.json     # provenance
  <name>.html            # simplified — tests load this
```

For multi-page fixtures (a parent page and its detail children, a list and a sample of its items), keep the related files under one feature directory and use names that make the relationship obvious:

```
tests/fixtures/<feature>/
  originals/
    listing.html
    listing.meta.json
    detail-42.html
    detail-42.meta.json
    detail-43.html
    detail-43.meta.json
  listing.html
  detail-42.html
```

**Capture a handful of children, not the whole catalog.** The number of `originals/` children needed is the number that exercises every distinct *shape* the test cares about — typically two or three. A listing page that links to 200 detail pages does not need 200 captures; pick representative samples (one happy-path, one edge case, maybe one variant) and stop. Each capture costs disk space, review time, and re-capture work whenever the source page changes; the value flattens after the third one.

**The simplified set is often even smaller than the originals set.** A test that walks the listing and asserts that *one* detail link resolves to the right shape only needs *one* simplified detail file in the test-facing directory, even if `originals/` holds three. Keep the unused originals around as audit trail (re-run the LLM pass against them later if the test grows), but do not produce simplified siblings the test never loads.

The filename pattern (`listing.html` + `detail-42.html`) is the relationship — any reader can see that `detail-42` is what the listing entry with id `42` links to. If a test needs to encode something the names cannot (which child is the happy-path sample, why a particular id was chosen, ordering that matters), put that in the parent's `notes` field at capture time or in the test file itself. No separate manifest file.

## What to do

### Capture a static page

```bash
"${CLAUDE_PLUGIN_ROOT}/fixtures/capture.sh" --strip \
  https://example.com/products/123 \
  tests/fixtures/products/listing
```

The `--strip` flag runs the mechanical pass on the captured original immediately, producing all three artifacts in one step:

- `tests/fixtures/products/originals/listing.html` — the raw response (Firefox User-Agent, redirects followed, decompressed).
- `tests/fixtures/products/originals/listing.meta.json` — `{sourceUrl, capturedAt, captureMethod, userAgent, notes?, ...}`.
- `tests/fixtures/products/listing.html` — the mechanically stripped sibling. Still needs the LLM pass before it's the final test-facing fixture.

`strip.ts` removes: HTML comments, `<script>` blocks (with one opinionated exception — `<script type="application/ld+json">` is preserved, since structured-data payloads are often what tests are reading), `<style>` blocks, `<noscript>` blocks, `<link>` tags, `<meta>` tags (except `<meta charset>`), then collapses trailing whitespace and runs of blank lines. The implementation uses Bun's `HTMLRewriter`, so quoted attribute values containing `<` or `>` (data URLs in `<link rel="icon">`, inline SVG, escaped angle brackets) round-trip correctly without regex tricks.

`strip.ts` is also runnable standalone — drop `--strip` from `capture.sh` if you want to inspect the raw original before stripping, then call `"${CLAUDE_PLUGIN_ROOT}/fixtures/strip.ts" <input> <output>` once you're ready.

### Capture a JS-heavy page

When the page renders content client-side, pass `--render`:

```bash
"${CLAUDE_PLUGIN_ROOT}/fixtures/capture.sh" --render --strip \
  https://example.com/dashboard \
  tests/fixtures/dashboards/main
```

The render path uses `playwright` from the user's project (resolved against the invoking CWD), launches headless Chromium, waits for `domcontentloaded`, then waits an additional 7000ms to let client-side hydration / late XHR fetches settle, and dumps `document.documentElement.outerHTML`. The script fails fast with an install hint when Playwright or the Chromium binary is missing.

The `--wait-until` event and the post-event settle time are independently tunable. Pass `--wait-until=<load|domcontentloaded|networkidle|commit>` to swap the event, and `--extra-wait-ms=<int>` to swap the post-event delay (set `--extra-wait-ms=0` to opt out). The defaults (`domcontentloaded` plus a 7s settle) are the most reliable shape across modern sites — `networkidle` hangs on pages with persistent websockets or polling analytics, while raw `domcontentloaded` returns before client-side rendering finishes.

### Simplify (LLM pass)

After the mechanical strip, the fixture still contains far more markup than any one test needs. The LLM pass cuts it down to "the smallest fixture that still represents the production page for this specific test."

When invoked for a fixture-trim task:

1. **Read the test that will use the fixture.** If the test does not exist yet, ask what assertions it will make. Without that, there is nothing to trim against.
2. **Identify the landmarks the test depends on.** Examples:
   - CSS selectors or XPath the parser walks (`.product-title`, `[data-price]`)
   - Specific text content asserted on (a single heading, a price string, an error message)
   - Attribute names/values the parser reads
   - Structural shape (a list of N items, a table with K columns)
3. **Walk the stripped fixture top-down. For each subtree, decide:**
   - Does a landmark live inside it? Keep, and trim siblings/children that do not contribute.
   - No landmark inside? Drop the entire subtree.
4. **Preserve the minimum scaffolding** so the result still parses as the same kind of document: `<!DOCTYPE>`, `<html>`, `<head>` containing `<meta charset>` and `<title>` if present, `<body>` wrapping the kept content.
5. **Reproduce dynamic behavior with hand-rolled vanilla JS, never a framework.** If the test asserts on JS-driven behavior — a viewmodel that updates when an input fires `change`, a click handler that toggles a class, a button that enables only after a field validates — the original framework code is already gone (the mechanical strip removed all `<script>` blocks except JSON-LD). Do not reintroduce it. Loading React, Vue, Angular, AngularJS, Solid, Svelte, or anything similar just to make a fixture interactive is a multi-megabyte tax on every test run for behavior recreatable in 10-20 lines. Instead, write the smallest possible vanilla JS that approximates production behavior just well enough for the test to be a reliable reproduction, and inline it as a `<script>` block in `<head>`. The goal is "the test exercises this quirk," not "the test runs the production app."
6. **Save the result to the test-facing path** (the simplified file in the feature directory, *not* a file under `originals/`). The original stays untouched.

A worked example. Suppose a parser-test only asserts that a product page exposes one `<h1 class="product-title">` and one `<span data-price>` inside a `<main>` region. The mechanically-stripped fixture might still be hundreds of lines of unrelated nav, footer, related-items grids, breadcrumbs, and review widgets:

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Acme Widget — Acme Co</title></head>
<body>
  <header class="site-header">…(20 lines of nav links)…</header>
  <nav class="breadcrumbs">…(crumb trail)…</nav>
  <main>
    <article class="product">
      <h1 class="product-title">Acme Widget</h1>
      <div class="price-block">
        <span data-price>$29.00</span>
        <span class="price-strike">$39.00</span>
      </div>
      <section class="reviews">…(40 lines of review markup)…</section>
      <section class="related">…(60 lines of related-products grid)…</section>
    </article>
  </main>
  <footer>…(30 lines of footer links and tracking opt-outs)…</footer>
</body>
</html>
```

After the semantic pass:

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Acme Widget — Acme Co</title></head>
<body>
  <main>
    <article class="product">
      <h1 class="product-title">Acme Widget</h1>
      <div class="price-block">
        <span data-price>$29.00</span>
      </div>
    </article>
  </main>
</body>
</html>
```

The breadcrumbs, header, footer, reviews, related grid, and the strike-through price all dropped — the test asserts on none of them. The `<main>` and `<article class="product">` ancestors stayed because the parser likely walks through them to reach the title and price (a `document.querySelector("main .product .product-title")` style traversal). When in doubt, err on the side of trimming more rather than less — the original is preserved, so any over-trim is recoverable by re-running this pass with looser criteria.

#### Common further-strip targets

The mechanical pass can only remove noise it knows is *always* noise. On content-heavy pages, that's a small fraction of total bytes — a Wikipedia article, for example, often loses only ~10% of lines because almost every element is real content from the parser's perspective. The semantic pass picks up where the mechanical one stops; these patterns recur often enough to be worth scanning for first.

- **Wikipedia / MediaWiki.** Drop `nav`, `.navbox`, `.infobox` (unless the test asserts on it), `#toc` and `.toc`, `.references` / `.reflist`, `.mw-editsection`, `.mw-jump-link`, `.mw-empty-elt`, `.hatnote`, `.thumb`, footer `.printfooter`, the language-list `#p-lang`, and anything else under the `mw-` prefix the test doesn't read. The article body lives in `.mw-parser-output`; everything outside it is chrome.
- **Long-form blogs and docs.** Strip comment threads (`#disqus_thread`, `.comments`), share widgets, related-posts grids, sidebar TOCs (unless the test reads the TOC), author bio cards, newsletter sign-up modals, and footer link farms.
- **E-commerce listings and detail pages.** Review widgets, "you might also like" carousels, breadcrumbs (unless asserted on), filter sidebars, recently-viewed grids, and footer link farms (shipping, returns, careers, etc.).
- **News articles.** Subscription paywalls and modals, related-articles rails, social-share rails, comment counters, byline metadata not under test, and inline ad slots (`.ad`, `[data-ad-slot]`, `iframe`).
- **Vendor docs and SDK references.** Version selectors, locale switchers, API-key prompts, search bars, dark-mode toggles, "edit on GitHub" links, sidebar nav (unless the test walks it).

The originals are not edited; the further-strip operates on the test-facing copy only.

### Persisting hand-edits across re-captures

When a fixture is re-captured (the source page changed, you want to verify against the latest), running `capture.sh` again with the same URL and base path overwrites the originals and stamps a new `capturedAt`. The mechanical strip is deterministic — re-running `strip.ts` reproduces the same baseline. **The LLM pass is not deterministic**, so the test-facing fixture must be re-trimmed against the current test after every re-capture.

Two ways to make the re-trim cheap:

- **Re-run the same instructions.** The "Simplify (LLM pass)" section above is the canonical workflow; the same agent reading the same test should converge on a similar trim.
- **Annotate kept regions.** When a kept region is non-obvious (a sibling included only to provide a structural ancestor for a selector, a duplicated element kept because the test counts them), leave a brief `<!-- KEEP: ... -->` comment so the next pass preserves the same shape.

### Re-capturing

To refresh a fixture, run `capture.sh` again with the same URL and base path. It overwrites the originals and stamps a new `capturedAt`. With `--strip`, the mechanical sibling is regenerated too. Then re-run the LLM pass to re-trim.

## The `.meta.json` shape

```json
{
  "sourceUrl": "https://example.com/products/123",
  "capturedAt": "2026-04-26T15:30:00Z",
  "captureMethod": "curl",
  "userAgent": "Mozilla/5.0 ...",
  "notes": "Captured during a sale; price banner is visible."
}
```

For `--render`:

```json
{
  "sourceUrl": "https://example.com/dashboard",
  "capturedAt": "2026-04-26T15:30:00Z",
  "captureMethod": "playwright",
  "waitUntil": "domcontentloaded",
  "extraWaitMs": 7000,
  "notes": "Captured for the dashboard-parser tests."
}
```

Optional keys (`userAgent`, `waitUntil`, `extraWaitMs`, `headers`, `cookies`, `notes`) are only emitted when present — an empty `notes` field is omitted entirely so a missing-notes fixture is visibly missing them, not silently empty. Fill in `--notes=` at capture time, or hand-edit the meta.json to add them — anything a future reader needs to interpret the fixture (A/B variant, date-sensitive content, "trimmed to N items for size") goes there.

The `headers` array stores raw `"Name: Value"` strings regardless of capture method — that's the canonical form. Render mode internally transforms them into Playwright's `extraHTTPHeaders` object before the fetch, but the on-disk record keeps the curl-shaped form so the array is comparable across methods.

## Loading from tests

A small loader in your test setup is enough:

```ts
import { readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const FIXTURE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

export const loadHtmlFixture = (rel: string): string =>
  readFileSync(join(FIXTURE_ROOT, rel), "utf-8");

export const loadFixtureMeta = (rel: string): unknown => {
  const featureDir = dirname(rel);
  const name = basename(rel, ".html");
  return JSON.parse(
    readFileSync(join(FIXTURE_ROOT, featureDir, "originals", `${name}.meta.json`), "utf-8"),
  );
};
```

Tests then call:

```ts
const html = loadHtmlFixture("products/listing.html");
const meta = loadFixtureMeta("products/listing.html");
```

The loader reads the test-facing path for the HTML and the sibling `originals/<name>.meta.json` for the provenance, matching the file layout `capture.sh` writes.

For DOM-parsed fixtures, parse once in `beforeAll` and share. Re-parsing on every test is the most common fixture cost — a factor-of-N waste when the parsed DOM is read-only.

## Anti-patterns

- **Hand-typed HTML.** Reads clean, drifts fast, lies about real page structure. Always start from a real capture.
- **Storing only the simplified version.** You lose the source of truth — when a test fails, you cannot tell whether the bug is in your code or in your simplification.
- **Storing only the original.** Tests pay the cost of parsing every script, style, comment, and analytics block on every run. Multiplied across hundreds of tests this is real wall-clock.
- **Skipping the LLM pass.** A mechanically-stripped fixture is 80% of the way there; the last 20% — dropping everything irrelevant to the test — is where most of the speed and clarity wins live.
- **Missing `.meta.json`.** A fixture without provenance is a mystery. Six months later, no one knows which environment it came from or whether the data shape still matches the current production schema.
- **Capturing assets.** No image payloads, no JS bundles, no font files, no stylesheet downloads. They balloon the repo for zero test-time value.
- **Capturing every child of a parent page.** A listing fixture does not need every linked detail page — pick two or three representative samples that cover the distinct shapes the test exercises. Capture cost is real (disk, review, re-capture work); test value flattens after the third sample.
- **Loading a JS framework into a fixture.** React / Vue / Angular / Solid / Svelte / etc. are megabytes of runtime to reload on every test for behavior the LLM can recreate in 10-20 lines of vanilla JS. If a test depends on framework-driven dynamic behavior, hand-write the minimum reproduction inline.
- **Editing files in `originals/` after capture.** Defeats the "this is exactly what the source served" guarantee. Fix bad captures by re-capturing, not by editing.

## Caveats

- **Requires `jq`** for `meta.json` composition. `capture.sh` fails fast if jq is absent.
- **`--strip` requires `bun`** because `strip.ts` uses Bun's built-in `HTMLRewriter`. The script fails fast with a hint if `bun` is not on `PATH`.
- **`--render` requires Playwright** in the project (`bun add -d playwright && bunx playwright install chromium`) or globally; `playwright` is resolved against the invoking shell's CWD, not the plugin directory. The script detects both "package not resolvable" and "Chromium binary missing" cases and prints actionable hints.
- **Cookies are flagged but redacted.** `--cookie` writes `"cookies": "redacted"` to `meta.json` with no secret leak, but this only applies to curl mode. In render mode, cookies travel as a `--header="Cookie: ..."` and are stored verbatim — see the next caveat.
- **`--header` values are stored verbatim in `meta.json`.** Pass non-secret headers only (or use `--cookie` in curl mode), or scrub the `headers` array from `meta.json` before committing.
- **`--render` defaults to `waitUntil=domcontentloaded` plus `--extra-wait-ms=7000`.** Raw `domcontentloaded` returns before client-side hydration finishes; the extra 7s settle covers most modern sites without the `networkidle` hang risk. Override either flag when the page genuinely needs different timing.
- **Static-page assumption.** The pattern fits pages whose initial DOM (or fully-rendered DOM) is the test target. Single-page apps that re-fetch data after every interaction are better served by a recording proxy (Polly.js, Mockttp, MSW) than by HTML snapshots.
- **Stale-fixture detection is on you.** A scheduled job that scans `*.meta.json` for a `capturedAt` older than N days is a good day-90 task; the skill itself ships no such mechanism. The right place for that recurring sweep is whatever workflow surfaces day-N gaps in the repo.
- **The LLM pass is not deterministic.** Different agents (or the same agent at different times) will produce slightly different trims. That's tolerable because the test exists as the ground truth — re-trimming against the same test should always preserve the same landmarks.

## Related skills

- `following-best-practices` — fixtures-from-the-source is a long-term-payoff practice; a future contributor cataloging it there is welcome.
- `using-llm-tasks` — the natural home for the day-N stale-fixture sweep mentioned above (a markdown task per stale fixture, or one rolling task that lists them).
