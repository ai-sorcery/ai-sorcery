#!/usr/bin/env bun
//
// sort-readme-examples — alphabetize the `## ` subsections inside the
// Examples block of the root README.md by heading name.
//
// Runs from the pre-commit hook ahead of update-readme-toc, so the TOC
// it later builds reflects the sorted order. Bails if README.md isn't
// in the staged set (pass --force to bypass, for manual verification).

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
  process.exit(0);
}

// The next `# ` heading (single-hash) closes the Examples section.
let sectionEnd = lines.length;
for (let i = examplesIdx + 1; i < lines.length; i++) {
  if (/^# [^#]/.test(lines[i])) {
    sectionEnd = i;
    break;
  }
}

// Collect `## ` subheading line indices, skipping anything that sits
// inside a fenced code block.
const subheadingIndices: number[] = [];
{
  let inCodeFence = false;
  for (let i = examplesIdx + 1; i < sectionEnd; i++) {
    if (/^```/.test(lines[i])) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (inCodeFence) continue;
    if (/^## /.test(lines[i])) {
      subheadingIndices.push(i);
    }
  }
}
if (subheadingIndices.length < 2) {
  process.exit(0);
}

// Prologue: everything between `# Examples` (exclusive) and the first `## `.
// Keeps the TOC block and any intro lines pinned to the top of the section.
const prologue = lines.slice(examplesIdx + 1, subheadingIndices[0]);

type Subsection = { key: string; body: string[] };
const subsections: Subsection[] = [];
for (let k = 0; k < subheadingIndices.length; k++) {
  const start = subheadingIndices[k];
  const end =
    k + 1 < subheadingIndices.length ? subheadingIndices[k + 1] : sectionEnd;
  const body = lines.slice(start, end);
  // Normalize trailing blank lines to exactly one, so reordering doesn't
  // cause vertical-spacing drift between runs.
  while (body.length > 1 && body[body.length - 1] === "") body.pop();
  body.push("");
  const heading = body[0];
  // Unwrap a `[text](url)` linked heading before deriving the sort key,
  // so subsections with heading-level links still sort by their name.
  const unwrapped = heading.replace(/^(## )\[(.+?)\]\([^)]+\)$/, "$1$2");
  const match = unwrapped.match(/^## (?:`([^`]+)`|(.+))$/);
  const key = (match?.[1] ?? match?.[2] ?? unwrapped).toLowerCase();
  subsections.push({ key, body });
}

subsections.sort((a, b) => a.key.localeCompare(b.key));

const rebuilt = [
  ...lines.slice(0, examplesIdx + 1),
  ...prologue,
  ...subsections.flatMap(({ body }) => body),
  ...lines.slice(sectionEnd),
];

const newContent = rebuilt.join("\n");
if (newContent === original) {
  process.exit(0);
}

await Bun.write(readmePath, newContent);
await $`git add ${readmePath}`;
console.log(`sort-readme-examples: reordered ${subsections.length} subsections`);
