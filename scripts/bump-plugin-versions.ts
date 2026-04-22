#!/usr/bin/env bun
//
// bump-plugin-versions — auto-bump the patch version of every plugin whose
// contents changed in the staged set for the current commit.
//
// Run from the pre-commit hook (see .githooks/pre-commit) and also
// invokable by hand (`bun scripts/bump-plugin-versions.ts`) to re-evaluate
// the current index without committing.
//
// Discovery is path-based: every `plugins/*/.claude-plugin/plugin.json`
// defines a plugin, so adding a new plugin directory wires it in
// automatically. Detection is also path-based: if any staged path under a
// plugin's directory (other than the plugin.json itself) appears in
// `git diff --cached`, that plugin's patch version is incremented.
// Metadata-only edits to plugin.json therefore do NOT self-trigger a bump
// — manual `version` edits are left alone.

import { $ } from "bun";
import { readdir } from "node:fs/promises";
import path from "node:path";

const repoRoot = (await $`git rev-parse --show-toplevel`.text()).trim();
const pluginsRoot = path.join(repoRoot, "plugins");

type Plugin = {
  name: string;
  manifestAbsPath: string;
  manifestRelPath: string;
  pluginRelPrefix: string;
};

async function discoverPlugins(): Promise<Plugin[]> {
  const entries = await readdir(pluginsRoot, { withFileTypes: true });
  const plugins: Plugin[] = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const manifestRelPath = path.posix.join(
      "plugins",
      entry.name,
      ".claude-plugin",
      "plugin.json",
    );
    const manifestAbsPath = path.join(repoRoot, manifestRelPath);
    if (!(await Bun.file(manifestAbsPath).exists())) continue;
    plugins.push({
      name: entry.name,
      manifestAbsPath,
      manifestRelPath,
      pluginRelPrefix: path.posix.join("plugins", entry.name) + "/",
    });
  }
  return plugins;
}

async function stagedPaths(): Promise<string[]> {
  const out = await $`git diff --cached --name-only --no-renames`.text();
  return out.split("\n").filter(Boolean);
}

function bumpPatch(version: string): string {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!match) {
    throw new Error(
      `unexpected version '${version}' — expected major.minor.patch`,
    );
  }
  const [, major, minor, patch] = match;
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

const plugins = await discoverPlugins();
const staged = await stagedPaths();

for (const plugin of plugins) {
  const pluginChanged = staged.some(
    (p) =>
      p.startsWith(plugin.pluginRelPrefix) && p !== plugin.manifestRelPath,
  );
  if (!pluginChanged) continue;

  const manifest = (await Bun.file(plugin.manifestAbsPath).json()) as {
    version: string;
    [key: string]: unknown;
  };
  const oldVersion = manifest.version;
  const newVersion = bumpPatch(oldVersion);
  manifest.version = newVersion;

  await Bun.write(
    plugin.manifestAbsPath,
    JSON.stringify(manifest, null, 2) + "\n",
  );
  await $`git add ${plugin.manifestAbsPath}`;
  console.log(
    `bump-plugin-versions: ${plugin.name} ${oldVersion} → ${newVersion}`,
  );
}
