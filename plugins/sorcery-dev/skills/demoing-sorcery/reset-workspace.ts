#!/usr/bin/env bun
//
// reset-workspace — wipe `<repo-root>/demo-workspace/` and re-seed it with a
// tiny TypeScript "snippet-box" CLI scenario plus three Claude-Bot-authored
// commits, ready for the demoing-sorcery walkthrough.
//
// The workspace is intentionally skeletal — no README, no setup script, no
// hooks — so `following-best-practices` finds genuine day-one gaps, and so
// `claiming-authorship` has commits to re-author. Re-running the script
// always wipes first; never merges into an existing tree.

import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import path from "node:path";

// Resolve the parent repo root *before* the demo-workspace gains its own
// `.git`, otherwise a later `git rev-parse` from inside the workspace would
// return the child repo.
const repoRoot = (await $`git rev-parse --show-toplevel`.text()).trim();
const ws = path.join(repoRoot, "demo-workspace");

const botEnv = {
  GIT_AUTHOR_NAME: "Claude Bot",
  GIT_AUTHOR_EMAIL: "bot@anthropic.com",
  GIT_COMMITTER_NAME: "Claude Bot",
  GIT_COMMITTER_EMAIL: "bot@anthropic.com",
};

async function botCommit(message: string): Promise<void> {
  await $`git -C ${ws} add -A`.env(botEnv).quiet();
  await $`git -C ${ws} commit -q -m ${message}`.env(botEnv).quiet();
}

await $`rm -rf ${ws}`;
await mkdir(path.join(ws, "src"), { recursive: true });

await Bun.write(
  path.join(ws, "package.json"),
  JSON.stringify(
    {
      name: "snippet-box",
      version: "0.0.1",
      type: "module",
      scripts: { start: "bun src/index.ts" },
    },
    null,
    2,
  ) + "\n",
);

await Bun.write(
  path.join(ws, "src/index.ts"),
  [
    "// snippet-box — a tiny CLI that stores quick code snippets.",
    "// Reads the [list|add|show] command from argv and dispatches.",
    "",
    'const cmd = process.argv[2] ?? "list";',
    'console.log("snippet-box:", cmd, "(stub)");',
    "",
  ].join("\n"),
);

await Bun.write(path.join(ws, ".gitignore"), "node_modules/\n");

await $`git -C ${ws} init -q -b main`.env(botEnv).quiet();
await botCommit("feat: scaffold snippet-box CLI");

await Bun.write(
  path.join(ws, "src/store.ts"),
  [
    "// Storage layer for snippet-box. JSON-on-disk, no external deps.",
    "export const placeholder = true;",
    "",
  ].join("\n"),
);
await botCommit("feat: add snippet store stub");

await Bun.write(
  path.join(ws, "src/index.ts"),
  [
    "// snippet-box — a tiny CLI that stores quick code snippets.",
    'import { placeholder } from "./store.ts";',
    "",
    'const cmd = process.argv[2] ?? "list";',
    'console.log("snippet-box:", cmd, placeholder ? "(stub)" : "");',
    "",
  ].join("\n"),
);
await botCommit("feat: wire store into entry point");

console.log(`reset-workspace: seeded ${ws}`);
console.log(`reset-workspace: 3 bot-authored commits on branch main`);
