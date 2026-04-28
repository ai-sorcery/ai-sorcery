#!/usr/bin/env bun
//
// check-readme-skill-links — enforce a two-way contract between the root
// README and the public skills under plugins/sorcery/skills/:
//
//   1. Every public skill has a heading link in the README pointing at its
//      folder (`plugins/sorcery/skills/<name>`) — GitHub renders the folder's
//      README.md when a viewer follows that link, so the folder must contain
//      one.
//   2. Every folder-style link anywhere in the README that targets a skill
//      must resolve to a folder containing a README.md. Catches typos and
//      stale references after a rename or removal.
//
// Runs from the pre-commit hook. Pass --force to bypass the staged-set
// short-circuit (useful for manual verification).

import { $ } from "bun";
import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import path from "node:path";

const force = process.argv.includes("--force");

const repoRoot = (await $`git rev-parse --show-toplevel`.text()).trim();
const readmeRel = "README.md";
const readmePath = path.join(repoRoot, readmeRel);
const skillsRel = "plugins/sorcery/skills";
const skillsRoot = path.join(repoRoot, skillsRel);

if (!force) {
  const staged = (await $`git diff --cached --name-only --no-renames`.text())
    .split("\n")
    .filter(Boolean);
  const relevant = staged.some(
    (p) => p === readmeRel || p.startsWith(`${skillsRel}/`),
  );
  if (!relevant) process.exit(0);
}

const readme = await Bun.file(readmePath).text();
const lines = readme.split("\n");

// Find the Examples section so we know where heading links must live.
const examplesIdx = lines.findIndex((line) => line === "# Examples");
if (examplesIdx === -1) {
  console.error("check-readme-skill-links: README is missing '# Examples' heading.");
  process.exit(1);
}
let examplesEnd = lines.length;
for (let i = examplesIdx + 1; i < lines.length; i++) {
  if (/^# [^#]/.test(lines[i])) {
    examplesEnd = i;
    break;
  }
}

// Map of skill name -> link target found in heading links inside Examples.
const headingLinks = new Map<string, string>();
{
  let inCodeFence = false;
  for (let i = examplesIdx + 1; i < examplesEnd; i++) {
    if (/^```/.test(lines[i])) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (inCodeFence) continue;
    const match = lines[i].match(/^## \[`([^`]+)`\]\(([^)]+)\)\s*$/);
    if (match) headingLinks.set(match[1], match[2]);
  }
}

// Discover public skills on disk.
const dirEntries = await readdir(skillsRoot, { withFileTypes: true });
const skills = dirEntries
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();

const errors: string[] = [];

// Rule 1 — every skill has a heading link pointing at its folder, and the
// folder contains a README.md (which is what GitHub renders when the link
// is followed).
for (const skill of skills) {
  const expected = `${skillsRel}/${skill}`;
  const target = headingLinks.get(skill);
  if (!target) {
    errors.push(
      `Skill '${skill}' has no heading link in ${readmeRel} — ` +
        `expected '## [\`${skill}\`](${expected})' under '# Examples'.`,
    );
  } else if (target !== expected) {
    errors.push(
      `Heading link for '${skill}' points at '${target}', expected '${expected}'.`,
    );
  }
  const skillReadme = path.join(repoRoot, skillsRel, skill, "README.md");
  if (!existsSync(skillReadme)) {
    errors.push(
      `Skill folder '${skillsRel}/${skill}/' is missing a README.md — ` +
        `GitHub needs one to render the folder link.`,
    );
  }
}

// Rule 1 (reverse) — flag heading links for skills that no longer exist on disk.
for (const skill of headingLinks.keys()) {
  if (!skills.includes(skill)) {
    errors.push(
      `README has a heading link for '${skill}', but no directory exists at ` +
        `'${skillsRel}/${skill}/'.`,
    );
  }
}

// Rule 2 — every folder-style link anywhere in the README that targets a
// skill must point at a folder containing a README.md. Trailing slash is
// optional (`plugins/sorcery/skills/<name>` and `<name>/` are both treated
// as folder links by GitHub).
const linkPattern = /\]\(([^)\s]+)\)/g;
const skillFolderRel = new RegExp(`^${skillsRel}/([^/]+)/?$`);
const seen = new Set<string>();
for (const line of lines) {
  for (const match of line.matchAll(linkPattern)) {
    const target = match[1];
    if (seen.has(target)) continue;
    seen.add(target);
    const folderMatch = target.match(skillFolderRel);
    if (!folderMatch) continue;
    const skillName = folderMatch[1];
    const skillReadme = path.join(repoRoot, skillsRel, skillName, "README.md");
    if (!existsSync(skillReadme)) {
      errors.push(
        `README links to '${target}', but '${skillsRel}/${skillName}/README.md' does not exist.`,
      );
    }
  }
}

if (errors.length > 0) {
  console.error("check-readme-skill-links: README skill-link contract violated.");
  console.error("");
  for (const err of errors) console.error(`  - ${err}`);
  console.error("");
  process.exit(1);
}
