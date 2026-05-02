#!/usr/bin/env bun
// Search the system SF Symbols catalog by keyword or name.
//
// Usage:
//   bun scripts/sf-symbol-search.ts <query> [--limit N]
//
// Examples:
//   bun scripts/sf-symbol-search.ts lightning
//   bun scripts/sf-symbol-search.ts "check mark" --limit 5
//   bun scripts/sf-symbol-search.ts arrow.up
//
// The catalog lives in CoreGlyphs.bundle and ships with macOS — installing
// SF Symbols.app is not required for the search to work. Each symbol carries
// a small list of designer-curated keywords; multi-word queries are AND'd
// across the joined "name + keywords" haystack.

import { $ } from "bun";

const SEARCH_PLIST =
  "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_search.plist";

const args = process.argv.slice(2);
const limitIdx = args.indexOf("--limit");
const limitArg = limitIdx !== -1 ? args[limitIdx + 1] : undefined;

if (limitIdx !== -1 && limitArg === undefined) {
  console.error("sf-symbol-search: --limit requires a value");
  process.exit(2);
}

const limit = limitArg !== undefined ? Number.parseInt(limitArg, 10) : 20;

if (Number.isNaN(limit) || limit <= 0) {
  console.error(`sf-symbol-search: --limit must be a positive integer (got '${limitArg}')`);
  process.exit(2);
}

const queryArgs =
  limitIdx !== -1
    ? args.filter((_, i) => i !== limitIdx && i !== limitIdx + 1)
    : args;
const query = queryArgs.join(" ").toLowerCase().trim();

if (!query) {
  console.error("Usage: bun scripts/sf-symbol-search.ts <query> [--limit N]");
  console.error("Examples:");
  console.error("  bun scripts/sf-symbol-search.ts bolt");
  console.error('  bun scripts/sf-symbol-search.ts "check mark" --limit 5');
  process.exit(2);
}

if (process.platform !== "darwin") {
  console.error("sf-symbol-search: SF Symbols ships with macOS — this only runs on darwin.");
  process.exit(2);
}

if (!(await Bun.file(SEARCH_PLIST).exists())) {
  console.error(`sf-symbol-search: catalog not found at ${SEARCH_PLIST}`);
  console.error("This file is part of CoreGlyphs.bundle and should be present on any modern macOS.");
  process.exit(2);
}

// `plutil -convert json -o -` round-trips a binary plist to JSON on stdout
// without writing to disk. The catalog maps symbol-name -> [keywords].
const result = await $`plutil -convert json -o - ${SEARCH_PLIST}`.text();
const symbolIndex: Record<string, string[]> = JSON.parse(result);

const terms = query.split(/\s+/);

type Match = { name: string; score: number };
const matches: Match[] = [];

for (const [symbolName, keywords] of Object.entries(symbolIndex)) {
  const nameLC = symbolName.toLowerCase();
  const keywordsLC = keywords.map((k) => k.toLowerCase());
  const joined = [nameLC, ...keywordsLC].join(" ");

  let score = 0;
  let allTermsMatch = true;

  for (const term of terms) {
    if (!joined.includes(term)) {
      allTermsMatch = false;
      break;
    }
    // Exact name segment match scores highest (e.g. "bolt" matching "bolt.fill"
    // beats "bolt" merely appearing inside "lightning_bolt_keyword").
    if (nameLC.split(".").some((seg) => seg === term)) score += 10;
    else if (nameLC.includes(term)) score += 5;
    else if (keywordsLC.some((k) => k === term)) score += 3;
    else score += 1;
  }

  if (allTermsMatch) {
    // Tie-break toward shorter (more specific) symbol names.
    score -= symbolName.length * 0.01;
    matches.push({ name: symbolName, score });
  }
}

matches.sort((a, b) => b.score - a.score);
const shown = matches.slice(0, limit);

if (shown.length === 0) {
  console.log(`No symbols found for "${query}"`);
  process.exit(0);
}

console.log(`Found ${matches.length} symbols for "${query}" (showing ${shown.length}):\n`);
for (const m of shown) {
  const keywords = symbolIndex[m.name];
  console.log(`  ${m.name}  (${keywords.join(", ")})`);
}

if (matches.length > limit) {
  console.log(`\n  ... and ${matches.length - limit} more (use --limit to show more)`);
}
