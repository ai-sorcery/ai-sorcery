#!/usr/bin/env bun
//
// update-readme-toc — keep a Table of contents block inside the Examples
// section of the root README.md in sync with its `## ` subheadings.
//
// Runs from the pre-commit hook. Markers bracketing the TOC:
//   <!-- toc:begin -->
//   <!-- toc:end -->
// Missing markers are inserted immediately after the `# Examples` heading
// on first run.
//
// Only runs when README.md is in the staged set — commits that touch
// unrelated files don't drag in TOC regeneration. Pass --force to bypass
// the staged-set check (useful for manual verification).

import { $ } from "bun";
import path from "node:path";

const force = process.argv.includes("--force");
const repoRoot = (await $`git rev-parse --show-toplevel`.text()).trim();
const readmePath = path.join(repoRoot, "README.md");
const readmeRelPath = "README.md";

if (!force) {
  const stagedPaths = (await $`git diff --cached --name-only --no-renames`.text())
    .split("\n")
    .filter(Boolean);
  if (!stagedPaths.includes(readmeRelPath)) {
    process.exit(0);
  }
}

const original = await Bun.file(readmePath).text();
const lines = original.split("\n");

const examplesIdx = lines.findIndex((line) => line === "# Examples");
if (examplesIdx === -1) {
  // Nothing to do — the README has no Examples section.
  process.exit(0);
}

// The next `# ` heading (single-hash) closes the section.
let sectionEnd = lines.length;
for (let i = examplesIdx + 1; i < lines.length; i++) {
  if (/^# [^#]/.test(lines[i])) {
    sectionEnd = i;
    break;
  }
}

// Collect `## ` subheadings inside the section, skipping anything that
// sits inside a fenced code block.
const entries: { heading: string; anchor: string }[] = [];
{
  let inCodeFence = false;
  for (let i = examplesIdx + 1; i < sectionEnd; i++) {
    if (/^```/.test(lines[i])) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (inCodeFence) continue;
    const match = lines[i].match(/^## (.+)$/);
    if (match) {
      // Strip a wrapping `[text](url)` so the TOC entry shows only the
      // displayed text and the anchor matches what GitHub generates for
      // a linked heading (which is keyed off the visible text, not the URL).
      const linkMatch = match[1].match(/^\[(.+?)\]\([^)]+\)$/);
      const heading = linkMatch ? linkMatch[1] : match[1];
      entries.push({ heading, anchor: slug(heading) });
    }
  }
}

const tocLines: string[] = [
  "<!-- toc:begin -->",
  ...entries.map(({ heading, anchor }) => `- [${heading}](#${anchor})`),
  "<!-- toc:end -->",
];

const beginIdx = lines.findIndex((line) => line.trim() === "<!-- toc:begin -->");
const endIdx = lines.findIndex((line) => line.trim() === "<!-- toc:end -->");

let updated: string[];
if (beginIdx !== -1 && endIdx !== -1 && beginIdx < endIdx) {
  updated = [
    ...lines.slice(0, beginIdx),
    ...tocLines,
    ...lines.slice(endIdx + 1),
  ];
} else {
  // First run — insert with a blank line on each side.
  updated = [
    ...lines.slice(0, examplesIdx + 1),
    "",
    ...tocLines,
    ...lines.slice(examplesIdx + 1),
  ];
}

const newContent = updated.join("\n");
if (newContent === original) {
  process.exit(0);
}

await Bun.write(readmePath, newContent);
await $`git add ${readmePath}`;
console.log(`update-readme-toc: refreshed ${entries.length} entries`);

function slug(heading: string): string {
  // GitHub-compatible anchor slug for this repo's Examples subheadings:
  // lowercase, drop everything that isn't a word char / space / hyphen,
  // collapse whitespace into hyphens, trim leading/trailing hyphens.
  return heading
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}
