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

// `symbol_search.plist` is keyword-indexed but only covers ~3189 of the ~9184
// shipping symbols — common names like `terminal` and the entire
// `chevron.left.forwardslash.*` family aren't there. `name_availability.plist`
// is the authoritative full-catalog list. Merging both gives every symbol a
// hit on its own name plus whatever keywords the curated index provides.
const SEARCH_PLIST =
  "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_search.plist";
const NAME_PLIST =
  "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist";

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

for (const path of [SEARCH_PLIST, NAME_PLIST]) {
  if (!(await Bun.file(path).exists())) {
    console.error(`sf-symbol-search: catalog not found at ${path}`);
    console.error("This file is part of CoreGlyphs.bundle and should be present on any modern macOS.");
    process.exit(2);
  }
}

// Apple's curated keywords are sparse for some engineering concepts — a
// search for "code" returns only QR/barcode glyphs, not the obvious
// `chevron.left.forwardslash.chevron.right`. This table maps a few common
// terms to additional substrings to OR into the per-term match. Each value
// is treated as a substring against the joined name+keyword haystack, so
// partial symbol names work (e.g. "chevron.left.forwardslash" matches
// `chevron.left.forwardslash.chevron.right`).
const QUERY_SYNONYMS: Record<string, string[]> = {
  branch: ["arrow.triangle.branch"],
  cli: ["terminal", "chevron.left.forwardslash"],
  code: ["chevron.left.forwardslash", "curlybraces"],
  command: ["terminal", "command"],
  fork: ["arrow.triangle.branch"],
  git: ["arrow.triangle.branch", "arrow.triangle.merge"],
  ide: ["terminal", "chevron.left.forwardslash"],
  merge: ["arrow.triangle.merge"],
  programming: ["chevron.left.forwardslash", "curlybraces"],
  repo: ["arrow.triangle.branch"],
  shell: ["terminal", "command"],
};

// `plutil -convert json -o -` round-trips a binary plist to JSON on stdout
// without writing to disk. Build the search index by union: every name from
// name_availability.plist gets an entry; keywords come from symbol_search.plist
// if present, else an empty array.
const searchJson = await $`plutil -convert json -o - ${SEARCH_PLIST}`.text();
const searchKeywords: Record<string, string[]> = JSON.parse(searchJson);

const namesJson = await $`plutil -convert json -o - ${NAME_PLIST}`.text();
const allNames = Object.keys(
  (JSON.parse(namesJson) as { symbols: Record<string, unknown> }).symbols,
);

const symbolIndex: Record<string, string[]> = {};
for (const name of allNames) {
  symbolIndex[name] = searchKeywords[name] ?? [];
}

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
    // For each term, accept either the term itself or one of its synonyms.
    // The matching candidate (term or synonym) drives the score, plus a
    // synonym bonus so deliberate synonym hits beat incidental substring
    // collisions in the widened catalog (e.g. searching "git" should
    // surface `arrow.triangle.branch` ahead of `digitalcrown`, which
    // contains "git" as a substring of "digital").
    const synonyms = QUERY_SYNONYMS[term] ?? [];
    const candidates = [term, ...synonyms];
    const matchedCandidate = candidates.find((c) => joined.includes(c));
    if (matchedCandidate === undefined) {
      allTermsMatch = false;
      break;
    }
    // Exact name segment match scores highest (e.g. "bolt" matching "bolt.fill"
    // beats "bolt" merely appearing inside "lightning_bolt_keyword").
    if (nameLC.split(".").some((seg) => seg === matchedCandidate)) score += 10;
    else if (nameLC.includes(matchedCandidate)) score += 5;
    else if (keywordsLC.some((k) => k === matchedCandidate)) score += 3;
    else score += 1;
    // Synonym bonus: nudges deliberate metaphors above incidental substring
    // hits without overtaking literal segment matches in non-synonym queries.
    if (matchedCandidate !== term) score += 3;
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
  console.log("");
  console.log("Apple's curated keywords don't cover every concept. If you already");
  console.log("know the symbol name, pass it directly to sf-symbol-to-svg.swift —");
  console.log("the conversion script does not depend on the search index.");
  console.log("");
  console.log("Engineering glyphs worth knowing by name:");
  console.log("  chevron.left.forwardslash.chevron.right  (code / </>)");
  console.log("  curlybraces                              (code blocks)");
  console.log("  terminal                                 (CLI / shell)");
  console.log("  arrow.triangle.branch                    (git branch / fork)");
  console.log("");
  console.log("Browse the full catalog visually with `brew install --cask sf-symbols`.");
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
