#!/usr/bin/env bun
//
// check-skill-coverage — fail the commit when any public-facing skill under
// `plugins/sorcery/skills/` is missing from `manifest.ts`, when a manifest
// entry no longer has a matching skill directory, or when a `skipped` entry
// has no reason. The intent is that adding a new public skill must come
// with a corresponding step in the demoing-sorcery-skills runbook (or an explicit
// reason for skipping).
//
// Runs from the pre-commit hook. Pass --force to bypass the staged-set
// short-circuit (useful for manual verification).

import { $ } from "bun";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { SKILLS } from "./manifest";

const force = process.argv.includes("--force");

const repoRoot = (await $`git rev-parse --show-toplevel`.text()).trim();
const manifestRel =
  "plugins/sorcery-dev/skills/demoing-sorcery-skills/manifest.ts";
const skillRel =
  "plugins/sorcery-dev/skills/demoing-sorcery-skills/SKILL.md";

if (!force) {
  const staged = (await $`git diff --cached --name-only --no-renames`.text())
    .split("\n")
    .filter(Boolean);
  const relevant = staged.some(
    (p) => p.startsWith("plugins/sorcery/skills/") || p === manifestRel,
  );
  if (!relevant) process.exit(0);
}

const publicSkillsDir = path.join(repoRoot, "plugins/sorcery/skills");
const entries = await readdir(publicSkillsDir, { withFileTypes: true });
const present = entries
  .filter((e) => e.isDirectory())
  .map((e) => e.name)
  .sort();

const known = new Set(SKILLS.map((s) => s.name));
const missing = present.filter((name) => !known.has(name));
const stale = SKILLS.filter((s) => !present.includes(s.name)).map((s) => s.name);
const skippedWithoutReason = SKILLS.filter(
  (s) => s.status === "skipped" && !s.reason.trim(),
).map((s) => s.name);

if (missing.length === 0 && stale.length === 0 && skippedWithoutReason.length === 0) {
  process.exit(0);
}

console.error("check-skill-coverage: demoing-sorcery-skills is out of sync.");
console.error("");

if (missing.length > 0) {
  console.error(
    `  Public skills missing from ${manifestRel}:`,
  );
  for (const name of missing) console.error(`    - ${name}`);
  console.error("");
  console.error(
    `  Add a step for each in ${skillRel} and list it as { status: "covered" } in the manifest,`,
  );
  console.error(
    `  or list it as { status: "skipped", reason: "..." } if it can't run in the demo environment.`,
  );
  console.error("");
}

if (stale.length > 0) {
  console.error(
    `  Manifest entries with no matching directory under plugins/sorcery/skills/:`,
  );
  for (const name of stale) console.error(`    - ${name}`);
  console.error("");
  console.error(`  Remove these from ${manifestRel}.`);
  console.error("");
}

if (skippedWithoutReason.length > 0) {
  console.error(`  Skipped entries with no reason:`);
  for (const name of skippedWithoutReason) console.error(`    - ${name}`);
  console.error("");
  console.error(`  Add a non-empty reason field for each in ${manifestRel}.`);
  console.error("");
}

process.exit(1);
