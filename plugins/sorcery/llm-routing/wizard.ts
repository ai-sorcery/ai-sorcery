#!/usr/bin/env bun
/**
 * wizard.ts — interactive menu for the llm-routing setup.
 *
 * Reachable via ./route.sh (no args). Each menu choice is a self-contained
 * action that exits cleanly back to the menu when it's done, so the user
 * can keep poking around without re-launching.
 *
 * Also supports a few non-interactive entry points used by route.sh:
 *   bun run wizard.ts --verify    (= ./route.sh verify)
 *
 * No external deps — only Bun's bundled APIs and node:* shims.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs"
import { spawn, spawnSync } from "node:child_process"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { printStatus, readLitellmConfig } from "./status.ts"

const here = dirname(fileURLToPath(import.meta.url))
const projectRoot = join(here, "..")

type ProviderDef = {
  id: string
  label: string
  env: string
  signup_url: string
  docs_url: string
  litellm_prefix: string
  litellm_api_base?: string
  notes: string
  suggested_models: Array<{
    alias: string
    model: string
    tier: "cheap" | "balanced" | "frontier" | "claude"
    description: string
  }>
}

type ProvidersFile = {
  providers: ProviderDef[]
  default_picks: Record<"cheap" | "balanced" | "frontier" | "claude", string[]>
}

const BOLD = "\x1b[1m"
const DIM = "\x1b[2m"
const GREEN = "\x1b[32m"
const YELLOW = "\x1b[33m"
const RED = "\x1b[31m"
const CYAN = "\x1b[36m"
const RESET = "\x1b[0m"

function loadProviders(): ProvidersFile {
  return JSON.parse(readFileSync(join(here, "providers.json"), "utf-8"))
}

// Shared async iterator over Bun's console-line stream. Re-creating per
// prompt() call breaks under non-TTY stdin: the underlying stream is
// one-shot, so a second `Bun.stdin.stream()` returns an exhausted reader
// and every prompt after the first returns "".
let consoleIter: AsyncIterator<string> | null = null

async function prompt(question: string): Promise<string> {
  process.stdout.write(question)
  if (!consoleIter) {
    consoleIter = (console as unknown as AsyncIterable<string>)[Symbol.asyncIterator]()
  }
  const { value, done } = await consoleIter.next()
  if (done || value === undefined) return ""
  return value
}

function header(title: string): void {
  console.log()
  console.log(`${BOLD}─── ${title} ───${RESET}`)
  console.log()
}

async function pause(): Promise<void> {
  await prompt(`${DIM}Press Enter to return to the menu.${RESET}`)
}

async function showStatus(): Promise<void> {
  await printStatus()
  await pause()
}

async function setupKeys(): Promise<void> {
  const providers = loadProviders()
  header("Set up provider API keys")
  console.log(`Keys live in ${BOLD}.env${RESET} at the repo root (next to llm.sh). Copy ${BOLD}.env.example${RESET} → ${BOLD}.env${RESET} and fill in the values:`)
  console.log()
  console.log(`  ${DIM}cp ../.env.example ../.env${RESET}`)
  console.log(`  ${DIM}$EDITOR ../.env${RESET}`)
  console.log()
  console.log(`route.sh and llm.sh source .env before launching the proxy, so a fresh shell isn't required.`)
  console.log()

  for (const [i, p] of providers.providers.entries()) {
    const set = !!process.env[p.env]
    const marker = set ? `${GREEN}[set]${RESET}` : `${YELLOW}[empty]${RESET}`
    console.log(`  ${i + 1}) ${BOLD}${p.label}${RESET}  ${marker}`)
  }
  console.log(`  0) back`)
  console.log()
  const choice = (await prompt("Provider number for details: ")).trim()
  const idx = parseInt(choice, 10) - 1
  if (Number.isNaN(idx) || idx < 0 || idx >= providers.providers.length) {
    return
  }
  const p = providers.providers[idx]!
  header(p.label)
  console.log(`${BOLD}Env var${RESET}        ${p.env}`)
  console.log(`${BOLD}Get a key${RESET}      ${CYAN}${p.signup_url}${RESET}`)
  console.log(`${BOLD}Docs${RESET}           ${CYAN}${p.docs_url}${RESET}`)
  console.log()
  console.log(p.notes)
  console.log()
  console.log(`${BOLD}Suggested LiteLLM aliases${RESET} (already in litellm.config.yaml — drop the ones you don't want):`)
  for (const m of p.suggested_models) {
    console.log(`  ${m.tier.padEnd(8)}  ${BOLD}${m.alias.padEnd(20)}${RESET}  ${DIM}${m.description}${RESET}`)
  }
  console.log()
  if (process.env[p.env]) {
    console.log(`${GREEN}✓${RESET} ${p.env} is set in this shell.`)
  } else {
    console.log(`${YELLOW}-${RESET} ${p.env} is not set. Add it to .env and re-run llm.sh / route.sh.`)
  }
  console.log()
  await pause()
}

function findLitellmBinary(): string | null {
  const venvLitellm = join(here, ".venv", "bin", "litellm")
  if (existsSync(venvLitellm)) return venvLitellm
  return Bun.which("litellm")
}

async function startProxy(): Promise<void> {
  header("Start the LiteLLM proxy")
  if (!findLitellmBinary()) {
    console.log(`${YELLOW}litellm${RESET} not found. Run ${CYAN}./setup.sh${RESET} to install it into .venv/.`)
    await pause()
    return
  }
  console.log("Launching ./start-proxy.sh in the background. Logs stream to ./logs/litellm.log.")
  console.log(`Tail the log with:  ${CYAN}tail -f logs/litellm.log${RESET}`)
  console.log()
  const child = spawn("bash", [join(here, "start-proxy.sh"), "--detach"], {
    detached: true,
    stdio: "ignore",
    cwd: here,
  })
  child.unref()
  console.log(`${DIM}Spawned PID ${child.pid}. Give it a couple of seconds, then run option 1 to confirm it's up.${RESET}`)
  await pause()
}

async function stopProxy(): Promise<void> {
  header("Stop the LiteLLM proxy")
  const r = spawnSync("bash", [join(here, "stop-proxy.sh")], {
    stdio: "inherit",
    cwd: here,
  })
  if (r.status !== 0) {
    console.log(`${YELLOW}stop-proxy.sh exited with status ${r.status}${RESET}`)
  }
  await pause()
}

async function sendTestRequest(): Promise<void> {
  header("Send a test prompt through the proxy")
  console.log("Pick a model alias declared in litellm.config.yaml. Common ones:")
  console.log(`  ${BOLD}claude${RESET} | ${BOLD}frontier${RESET} | ${BOLD}balanced${RESET} | ${BOLD}cheap${RESET}  ${DIM}(tier aliases)${RESET}`)
  console.log(`  ${BOLD}claude-opus-1m${RESET}, ${BOLD}gpt-4.1-mini${RESET}, ${BOLD}deepseek-chat${RESET}, ${BOLD}kimi-k2${RESET}, …`)
  console.log()
  const model = (await prompt("Model alias (default 'claude'): ")).trim() || "claude"
  const userPrompt = (await prompt("Prompt (default 'say hi in five words'): ")).trim() || "say hi in five words"
  console.log()
  console.log(`${DIM}POST http://127.0.0.1:4000/v1/chat/completions${RESET}`)

  try {
    const r = await fetch("http://127.0.0.1:4000/v1/chat/completions", {
      method: "POST",
      headers: { "content-type": "application/json", "authorization": "Bearer not-needed" },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: userPrompt }],
        max_tokens: 256,
      }),
      signal: AbortSignal.timeout(60_000),
    })
    if (!r.ok) {
      const text = await r.text()
      let parsed: any
      try { parsed = JSON.parse(text) } catch { parsed = null }
      console.log(`${RED}HTTP ${r.status}${RESET}`)
      if (parsed?.error) {
        if (parsed.error.code) console.log(`  ${DIM}code:${RESET} ${parsed.error.code}`)
        if (parsed.error.message) console.log(`  ${DIM}message:${RESET} ${parsed.error.message}`)
      } else {
        console.log(text)
      }
    } else {
      const j = (await r.json()) as any
      const text = j?.choices?.[0]?.message?.content ?? JSON.stringify(j, null, 2)
      console.log()
      console.log(`${GREEN}── reply ──${RESET}`)
      console.log(text)
    }
  } catch (e) {
    console.log(`${RED}Request failed:${RESET} ${(e as Error).message}`)
    console.log(`${DIM}Is the proxy running? (option 2 to start.)${RESET}`)
  }
  console.log()
  await pause()
}

async function pingAlias(alias: string): Promise<{ alias: string; ok: boolean; status: number; detail: string; ms: number }> {
  const t0 = performance.now()
  try {
    const r = await fetch("http://127.0.0.1:4000/v1/chat/completions", {
      method: "POST",
      headers: { "content-type": "application/json", "authorization": "Bearer not-needed" },
      body: JSON.stringify({
        model: alias,
        messages: [{ role: "user", content: "ping" }],
        max_tokens: 4,
      }),
      signal: AbortSignal.timeout(30_000),
    })
    const ms = Math.round(performance.now() - t0)
    if (r.ok) {
      return { alias, ok: true, status: r.status, detail: "ok", ms }
    }
    const text = await r.text()
    let parsed: any
    try { parsed = JSON.parse(text) } catch { parsed = null }
    const detail = parsed?.error?.message?.slice(0, 80) ?? `HTTP ${r.status}`
    return { alias, ok: false, status: r.status, detail, ms }
  } catch (e) {
    const ms = Math.round(performance.now() - t0)
    return { alias, ok: false, status: 0, detail: (e as Error).message.slice(0, 80), ms }
  }
}

async function verifyAliases(opts: { paused: boolean } = { paused: true }): Promise<number> {
  header("Verify model aliases")
  const cfg = readLitellmConfig()
  const allNames = cfg.modelNames
  if (allNames.length === 0) {
    console.log(`${YELLOW}-${RESET} no model_list entries — check litellm.config.yaml`)
    if (opts.paused) await pause()
    return 1
  }

  // Skip aliases whose required env var is missing — those are guaranteed
  // failures and the report shouldn't be dominated by "ANTHROPIC_API_KEY
  // missing" lines.
  const reachable = allNames.filter((n) => {
    const env = cfg.modelKeyEnv[n]
    return !env || !!process.env[env]
  })
  const skipped = allNames.filter((n) => !reachable.includes(n))

  console.log(`Pinging ${reachable.length} alias${reachable.length === 1 ? "" : "es"} in parallel ${DIM}(timeout: 30s each)${RESET}`)
  if (skipped.length) {
    console.log(`${DIM}Skipping ${skipped.length} for missing API keys: ${skipped.join(", ")}${RESET}`)
  }
  console.log()

  const results = await Promise.all(reachable.map(pingAlias))
  results.sort((a, b) => a.alias.localeCompare(b.alias))

  let failed = 0
  for (const r of results) {
    const marker = r.ok ? `${GREEN}✓${RESET}` : `${RED}✗${RESET}`
    const status = r.ok ? `${DIM}${r.ms}ms${RESET}` : `${YELLOW}HTTP ${r.status || "—"}${RESET}`
    const detail = r.ok ? "" : `  ${DIM}${r.detail}${RESET}`
    console.log(`  ${marker} ${r.alias.padEnd(24)} ${status}${detail}`)
    if (!r.ok) {
      failed += 1
      // 404 from a reachable alias means the upstream rejected the
      // model id with the env key present — almost always a retired
      // (or access-gated) model id rather than a transient failure.
      if (r.status === 404) {
        console.log(`    ${DIM}↳ likely a retired or inaccessible upstream model id — re-target the alias in litellm.config.yaml${RESET}`)
      }
    }
  }
  console.log()
  const summary = failed === 0
    ? `${GREEN}all ${results.length} reachable aliases responded${RESET}`
    : `${RED}${failed}/${results.length} failed${RESET}`
  console.log(`${BOLD}Summary:${RESET} ${summary}`)
  console.log()
  if (opts.paused) await pause()
  return failed === 0 ? 0 : 1
}

async function listAliases(): Promise<void> {
  header("All model aliases")
  const cfg = readLitellmConfig()
  if (cfg.modelNames.length === 0) {
    console.log(`${YELLOW}-${RESET} no model_list entries — check litellm.config.yaml`)
    await pause()
    return
  }
  // Concrete model_names first, then tier aliases (group_alias targets
  // are flagged so the user sees what resolves to what).
  const aliasNames = new Set(Object.keys(cfg.aliasTargets))
  const concrete = cfg.modelNames.filter((n) => !aliasNames.has(n))
  const aliases = cfg.modelNames.filter((n) => aliasNames.has(n))

  console.log(`${BOLD}Tier aliases${RESET}  ${DIM}(model_group_alias)${RESET}`)
  for (const name of aliases) {
    const target = cfg.aliasTargets[name]
    console.log(`  ${BOLD}${name.padEnd(12)}${RESET} → ${target}`)
  }
  console.log()
  console.log(`${BOLD}Concrete models${RESET}  ${DIM}(model_list entries — ${concrete.length} total)${RESET}`)
  for (const name of concrete) {
    const env = cfg.modelKeyEnv[name]
    const present = env ? !!process.env[env] : true
    const marker = present ? `${GREEN}✓${RESET}` : `${YELLOW}-${RESET}`
    const envNote = env ? `${DIM}(${env}${present ? "" : " missing"})${RESET}` : ""
    console.log(`  ${marker} ${name.padEnd(22)} ${envNote}`)
  }
  console.log()
  await pause()
}

async function retargetTierAlias(): Promise<void> {
  header("Re-target a tier alias")
  const cfg = readLitellmConfig()
  const tiers = Object.entries(cfg.aliasTargets)
  if (tiers.length === 0) {
    console.log(`${YELLOW}-${RESET} no model_group_alias block found in litellm.config.yaml`)
    await pause()
    return
  }

  console.log("Current tier-alias bindings:")
  for (const [i, [tier, target]] of tiers.entries()) {
    console.log(`  ${i + 1}) ${BOLD}${tier.padEnd(10)}${RESET} → ${target}`)
  }
  console.log(`  0) back`)
  console.log()

  const choice = (await prompt("Tier number: ")).trim()
  const idx = parseInt(choice, 10) - 1
  if (Number.isNaN(idx) || idx < 0 || idx >= tiers.length) return
  const [tier, currentTarget] = tiers[idx]!

  // Build the candidate list from the concrete model_list entries (the
  // tier aliases themselves can't target another alias).
  const aliasSet = new Set(Object.keys(cfg.aliasTargets))
  const candidates = cfg.modelNames.filter((n) => !aliasSet.has(n))

  console.log()
  console.log(`Available targets for ${BOLD}${tier}${RESET}:`)
  for (const [i, name] of candidates.entries()) {
    const env = cfg.modelKeyEnv[name]
    const present = env ? !!process.env[env] : true
    const marker = present ? `${GREEN}✓${RESET}` : `${YELLOW}-${RESET}`
    const note = env ? `${DIM}(${env}${present ? "" : " missing"})${RESET}` : ""
    const cur = name === currentTarget ? ` ${DIM}(current)${RESET}` : ""
    console.log(`  ${(i + 1).toString().padStart(2)}) ${marker} ${name.padEnd(22)} ${note}${cur}`)
  }
  console.log()
  const newChoice = (await prompt("New target number (or model_name): ")).trim()
  if (!newChoice) return
  let newTarget: string | undefined
  const newIdx = parseInt(newChoice, 10) - 1
  if (!Number.isNaN(newIdx) && newIdx >= 0 && newIdx < candidates.length) {
    newTarget = candidates[newIdx]
  } else if (candidates.includes(newChoice)) {
    newTarget = newChoice
  }
  if (!newTarget) {
    console.log(`${YELLOW}unknown target: ${newChoice}${RESET}`)
    await pause()
    return
  }
  if (newTarget === currentTarget) {
    console.log(`${DIM}target unchanged${RESET}`)
    await pause()
    return
  }

  // In-place edit of the YAML — match the `<tier>: <something>` line
  // inside the model_group_alias block. The parser already validated
  // the block exists, so a regex against the known shape is safe.
  // The trailing group is restricted to non-newline whitespace so it
  // can't accidentally swallow the blank line after the alias block.
  const path = join(here, "litellm.config.yaml")
  const text = readFileSync(path, "utf-8")
  const aliasRe = new RegExp(`^(\\s+${tier}:\\s+)\\S+([ \\t]*(?:#.*)?)$`, "m")
  if (!aliasRe.test(text)) {
    console.log(`${YELLOW}couldn't find the ${tier}: alias line to rewrite — edit by hand:${RESET}`)
    console.log(`  ${CYAN}${path}${RESET}`)
    await pause()
    return
  }
  let updated = text.replace(aliasRe, `$1${newTarget}$2`)

  // Re-key the fallback chain so the new target inherits the resilience
  // chain. Without this, retargeting silently strips fallbacks: the old
  // `<currentTarget>: [...]` line stays but no longer applies, and the
  // new target has no fallback entry. Match the YAML-list shape used
  // throughout the file: `- <name>: [...]`.
  const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  const fallbackRe = new RegExp(`^(\\s*-\\s*)${escapeRegex(currentTarget)}(:\\s*\\[)`, "m")
  let fallbacksRekeyed = false
  if (fallbackRe.test(updated)) {
    // Only re-key if the new target doesn't already have its own
    // fallback line (which would otherwise create a duplicate key).
    const newTargetHasFallback = new RegExp(
      `^\\s*-\\s*${escapeRegex(newTarget)}:\\s*\\[`,
      "m",
    ).test(updated)
    if (!newTargetHasFallback) {
      updated = updated.replace(fallbackRe, `$1${newTarget}$2`)
      fallbacksRekeyed = true
    }
  }

  writeFileSync(path, updated)
  console.log()
  console.log(`${GREEN}✓${RESET} ${BOLD}${tier}${RESET}: ${currentTarget} → ${newTarget}`)
  if (fallbacksRekeyed) {
    console.log(`${DIM}  re-keyed fallbacks: ${currentTarget}: [...] → ${newTarget}: [...]${RESET}`)
  } else {
    console.log(`${YELLOW}  no fallback chain migrated.${RESET} ${DIM}Add an entry under router_settings.fallbacks for ${newTarget} if you want a fallback chain.${RESET}`)
  }
  console.log(`${DIM}Restart the proxy for the change to take effect (option 3, then option 2).${RESET}`)
  console.log()
  await pause()
}

async function showRecommendations(): Promise<void> {
  const providers = loadProviders()
  header("Recommended model picks")
  console.log("Pair a frontier model with a cheap one for fan-out style work — drive the hard reasoning with the frontier tier, expand and edit with the cheap tier. `claude` stays its own tier so a request to `frontier` never silently requires an ANTHROPIC_API_KEY.")
  console.log()
  for (const tier of ["frontier", "balanced", "cheap", "claude"] as const) {
    console.log(`${BOLD}${tier}${RESET}`)
    for (const alias of providers.default_picks[tier]) {
      const provider = providers.providers.find((p) => p.suggested_models.some((m) => m.alias === alias))
      const model = provider?.suggested_models.find((m) => m.alias === alias)
      if (!provider || !model) continue
      const keyOK = !!process.env[provider.env]
      const marker = keyOK ? `${GREEN}✓${RESET}` : `${YELLOW}-${RESET}`
      console.log(`  ${marker} ${alias.padEnd(20)} ${DIM}${model.description} (${provider.label})${RESET}`)
    }
    console.log()
  }
  console.log(`${DIM}Swival profiles \`frontier\`, \`balanced\`, \`cheap\`, and \`claude\` map to the first pick in each tier via router_settings.model_group_alias. Use option 12 (Re-target a tier alias) to swap them.${RESET}`)
  console.log()
  await pause()
}

async function tailRequestLog(): Promise<void> {
  header("Tail the request log")
  const r = spawnSync("bun", ["run", join(here, "observability.ts"), "tail", "--once"], {
    stdio: "inherit",
    cwd: here,
  })
  if (r.status !== 0) {
    console.log(`${YELLOW}observability.ts exited with status ${r.status}${RESET}`)
  }
  await pause()
}

async function showCosts(): Promise<void> {
  header("Aggregate costs by model")
  const r = spawnSync("bun", ["run", join(here, "observability.ts"), "costs"], {
    stdio: "inherit",
    cwd: here,
  })
  if (r.status !== 0) {
    console.log(`${YELLOW}observability.ts exited with status ${r.status}${RESET}`)
  }
  await pause()
}

async function openConfig(filename: string, baseDir: string = here): Promise<void> {
  const path = join(baseDir, filename)
  const editor = process.env.VISUAL || process.env.EDITOR
  header(`Open ${filename}`)
  if (!existsSync(path)) {
    console.log(`${YELLOW}${path}${RESET} doesn't exist yet.`)
    await pause()
    return
  }
  if (!editor) {
    console.log(`No ${BOLD}$VISUAL${RESET} or ${BOLD}$EDITOR${RESET} set. Open this file manually:`)
    console.log(`  ${CYAN}${path}${RESET}`)
    await pause()
    return
  }
  console.log(`Launching ${BOLD}${editor}${RESET} on ${CYAN}${path}${RESET}…`)
  const r = spawnSync(editor, [path], { stdio: "inherit" })
  if (r.status !== 0) {
    console.log(`${YELLOW}editor exited with status ${r.status}${RESET}`)
  }
  await pause()
}

const MENU: Array<{ key: string; label: string; run: () => Promise<void> }> = [
  { key: "1",  label: "Show status (keys, models, proxy)",         run: showStatus },
  { key: "2",  label: "Start the LiteLLM proxy",                   run: startProxy },
  { key: "3",  label: "Stop the LiteLLM proxy",                    run: stopProxy },
  { key: "4",  label: "Send a test prompt through the proxy",      run: sendTestRequest },
  { key: "5",  label: "Verify all model aliases (ping each one)",  run: () => verifyAliases().then(() => undefined) },
  { key: "6",  label: "List all model aliases",                    run: listAliases },
  { key: "7",  label: "Tail the request log",                      run: tailRequestLog },
  { key: "8",  label: "Aggregate costs by model",                  run: showCosts },
  { key: "9",  label: "Set up provider API keys",                  run: setupKeys },
  { key: "10", label: "Edit litellm.config.yaml",                  run: () => openConfig("litellm.config.yaml") },
  { key: "11", label: "Edit swival.toml (at repo root)",           run: () => openConfig("swival.toml", projectRoot) },
  { key: "12", label: "Re-target a tier alias",                    run: retargetTierAlias },
  { key: "13", label: "Show recommended model picks",              run: showRecommendations },
]

async function main(): Promise<void> {
  if (!existsSync(join(here, "providers.json"))) {
    console.error("wizard: providers.json missing — is this script running from inside llm-routing/?")
    process.exit(1)
  }

  // Non-interactive entry points used by route.sh sub-commands.
  if (process.argv.includes("--verify")) {
    process.exit(await verifyAliases({ paused: false }))
  }

  // Print status once at startup so the user sees the picture before being
  // asked to pick anything. Skip the "press enter" pause on this first read.
  await printStatus()

  while (true) {
    console.log()
    console.log(`${BOLD}── llm-routing wizard ──${RESET}`)
    for (const item of MENU) {
      console.log(`  ${BOLD}${item.key.padStart(2)}${RESET}) ${item.label}`)
    }
    console.log(`  ${BOLD} q${RESET}) quit`)
    console.log()
    const choice = (await prompt("Choice: ")).trim().toLowerCase()
    if (choice === "q" || choice === "quit" || choice === "exit") {
      console.log()
      console.log(`${DIM}bye${RESET}`)
      return
    }
    const item = MENU.find((m) => m.key === choice)
    if (!item) {
      console.log(`${YELLOW}unknown choice: ${choice}${RESET}`)
      continue
    }
    await item.run()
  }
}

await main()
