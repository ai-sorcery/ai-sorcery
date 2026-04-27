#!/usr/bin/env bun
//
// check-commit-message — validate a commit message against the ruleset
// documented in plugins/sorcery/skills/writing-commit-messages/SKILL.md.
//
// Invoked from a `commit-msg` git hook with the commit message file path
// as its first argument. Comment lines (#...) and trailer blocks
// (Token: value at the bottom) are stripped before validation, matching
// git's own behaviour.
//
// Em dashes are banned anywhere in the message — checked against the full
// stripped text, not per bullet. Em dashes encourage chained sub-clauses
// that bloat bullets and make subjects hard to scan in `git log --oneline`.

import { $ } from "bun";
import { readFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("Usage: check-commit-message <commit-msg-file>");
  process.exit(2);
}

const raw = readFileSync(file, "utf8");

let lines = raw.split("\n").filter((l) => !l.startsWith("#"));
while (lines.length && lines[lines.length - 1] === "") lines.pop();
const trailerRe = /^[A-Z][A-Za-z-]+:\s.+$/;
while (lines.length && trailerRe.test(lines[lines.length - 1])) lines.pop();
while (lines.length && lines[lines.length - 1] === "") lines.pop();

const errors: string[] = [];

const totalEmDashes = (lines.join("\n").match(/—/g) ?? []).length;
if (totalEmDashes > 0) {
  errors.push(
    `commit message contains ${totalEmDashes} em dash(es); none allowed (subject or body)`,
  );
}

// Read disallowed-commit-messages.txt at repo root, if present. Each
// non-empty, non-comment line is a substring (case-insensitive) that
// blocks the commit. Repo-level guard for things like overly-generic
// conventional-commits scopes.
const repoRoot = (await $`git rev-parse --show-toplevel`
  .text()
  .catch(() => ""))
  .trim();
if (repoRoot) {
  try {
    const disallowedRaw = readFileSync(
      `${repoRoot}/disallowed-commit-messages.txt`,
      "utf8",
    );
    const terms = disallowedRaw
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0 && !l.startsWith("#"));
    const haystack = lines.join("\n").toLowerCase();
    for (const term of terms) {
      if (haystack.includes(term.toLowerCase())) {
        errors.push(
          `commit message contains disallowed string \`${term}\` (see disallowed-commit-messages.txt)`,
        );
      }
    }
  } catch {
    // No file or unreadable — silent skip; the rule is opt-in per repo.
  }
}

// Staged file basenames, used by the concept check applied to subject + bullets.
// Only flag basenames that include an extension OR are ≥ 6 chars bare; stops
// false positives from short bare names like `me` (from `me.sh`).
const stagedOut = await $`git diff --cached --name-only`
  .text()
  .catch(() => "");
const basenames = new Set<string>();
for (const p of stagedOut.split("\n").filter(Boolean)) {
  const base = p.split("/").pop() ?? "";
  if (base.includes(".") || base.length >= 6) basenames.add(base);
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function checkConcept(text: string, label: string) {
  if (/(?<!\s)\/(?!\s)/.test(text)) {
    errors.push(
      `${label} contains a path-like token (slash with non-whitespace on both sides): ${text}`,
    );
  }
  for (const base of basenames) {
    const re = new RegExp(`\\b${escapeRegex(base)}\\b`);
    if (re.test(text)) {
      errors.push(`${label} mentions changed file \`${base}\`: ${text}`);
    }
  }
}

const subject = lines[0] ?? "";
if (subject.length > 72) {
  errors.push(`subject is ${subject.length} chars (max 72): ${subject}`);
}
if (subject.endsWith(".")) {
  errors.push(`subject ends with period: ${subject}`);
}
const subjectMatch = subject.match(/^(\w+(?:\([^)]+\))?:)\s*(\S)/);
if (subjectMatch && /[A-Z]/.test(subjectMatch[2])) {
  errors.push(
    `subject's first word after \`${subjectMatch[1]}\` should be lowercase: ${subject}`,
  );
}
checkConcept(subject, "subject");

if (lines.length > 1) {
  if (lines[1] !== "") {
    errors.push("subject and body must be separated by a blank line");
  }
  const bodyLines = lines.slice(2);
  const nonEmpty = bodyLines.filter((l) => l.trim() !== "");
  const bullets = nonEmpty.filter((l) => /^- /.test(l));
  const prose = nonEmpty.filter((l) => !/^- /.test(l));
  if (prose.length > 0) {
    errors.push(`body must be hyphen bullets only; found prose line: ${prose[0]}`);
  }
  if (bullets.length > 3) {
    errors.push(`body has ${bullets.length} bullets (max 3)`);
  }

  for (const bullet of bullets) {
    const text = bullet.replace(/^- /, "");
    const words = text.trim().split(/\s+/).length;
    if (words > 20) {
      errors.push(`bullet is ${words} words (max 20): ${bullet}`);
    }
    checkConcept(text, "bullet");
  }
}

if (errors.length > 0) {
  console.error(`check-commit-message: ${errors.length} violation(s)`);
  for (const e of errors) console.error(`  - ${e}`);
  console.error("");
  console.error(
    "See plugins/sorcery/skills/writing-commit-messages/SKILL.md for the rules.",
  );
  process.exit(1);
}
