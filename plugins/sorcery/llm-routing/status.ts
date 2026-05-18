#!/usr/bin/env bun
/**
 * status.ts — inspect the local llm-routing setup and print a one-shot
 * report: which provider API keys are set, which models in
 * litellm.config.yaml are reachable given those keys, whether the proxy
 * is running, and which Swival profiles are wired.
 *
 * Used both as a standalone command (`./route.sh status`) and as the
 * first screen the wizard shows. Pure inspection — never writes.
 */

import { existsSync, readFileSync } from "node:fs"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"

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
  default_picks: Record<string, string[]>
}

const RESET = "\x1b[0m"
const BOLD = "\x1b[1m"
const DIM = "\x1b[2m"
const GREEN = "\x1b[32m"
const YELLOW = "\x1b[33m"
const RED = "\x1b[31m"
const CYAN = "\x1b[36m"

function readProviders(): ProvidersFile {
  return JSON.parse(readFileSync(join(here, "providers.json"), "utf-8"))
}

export function readLitellmConfig(): { rawLines: string[]; modelNames: string[]; modelKeyEnv: Record<string, string>; aliasTargets: Record<string, string> } {
  const path = join(here, "litellm.config.yaml")
  if (!existsSync(path)) {
    return { rawLines: [], modelNames: [], modelKeyEnv: {}, aliasTargets: {} }
  }
  const rawLines = readFileSync(path, "utf-8").split("\n")
  // Naive parse — sufficient for inspecting a config produced by this skill.
  // We do NOT pull in a YAML parser to keep this script dependency-free.
  const modelNames: string[] = []
  const modelKeyEnv: Record<string, string> = {}
  const aliasTargets: Record<string, string> = {}
  let currentName: string | null = null
  let inAliasBlock = false
  let aliasBlockIndent = 0
  for (const line of rawLines) {
    const nameMatch = line.match(/^\s*- model_name:\s*(\S+)\s*$/)
    if (nameMatch) {
      currentName = nameMatch[1]!
      modelNames.push(currentName)
      inAliasBlock = false
      continue
    }
    if (currentName) {
      const keyMatch = line.match(/^\s*api_key:\s*os\.environ\/(\S+)\s*$/)
      if (keyMatch) {
        modelKeyEnv[currentName] = keyMatch[1]!
      }
    }
    const aliasHeader = line.match(/^(\s*)model_group_alias:\s*$/)
    if (aliasHeader) {
      inAliasBlock = true
      aliasBlockIndent = aliasHeader[1]!.length
      currentName = null
      continue
    }
    if (inAliasBlock) {
      if (line.trim() === "") continue
      const lineIndent = line.match(/^(\s*)/)![1]!.length
      if (lineIndent <= aliasBlockIndent) {
        inAliasBlock = false
      } else {
        const aliasMatch = line.match(/^\s+(\S+):\s*(\S+)\s*$/)
        if (aliasMatch) {
          const alias = aliasMatch[1]!
          const target = aliasMatch[2]!
          aliasTargets[alias] = target
          if (!modelNames.includes(alias)) modelNames.push(alias)
        }
      }
    }
  }
  // Inherit the env-var requirement of each alias's target so the status
  // report can flag a missing key for "frontier" the same way it does for
  // the concrete model the alias points at.
  for (const [alias, target] of Object.entries(aliasTargets)) {
    const inherited = modelKeyEnv[target]
    if (inherited && !modelKeyEnv[alias]) {
      modelKeyEnv[alias] = inherited
    }
  }
  return { rawLines, modelNames, modelKeyEnv, aliasTargets }
}

function readSwivalProfiles(): { profiles: string[]; path: string; found: boolean } {
  const path = join(projectRoot, "swival.toml")
  if (!existsSync(path)) return { profiles: [], path, found: false }
  const text = readFileSync(path, "utf-8")
  const profiles: string[] = []
  for (const m of text.matchAll(/^\[profiles\.([^\]]+)\]/gm)) {
    profiles.push(m[1]!)
  }
  return { profiles, path, found: true }
}

function countRequestLog(): { exists: boolean; count: number; path: string } {
  const path = join(here, "logs", "litellm.log")
  if (!existsSync(path)) return { exists: false, count: 0, path }
  // Count JSON lines that look like a completed-request record. With
  // json_logs: true LiteLLM emits structured stdout — request records
  // carry a model field. Naive line-count is sufficient for a status
  // glance; the observability viewer does proper parsing.
  let count = 0
  try {
    const text = readFileSync(path, "utf-8")
    for (const line of text.split("\n")) {
      if (line.includes('"model"') && line.startsWith("{")) count += 1
    }
  } catch { /* unreadable — treat as zero */ }
  return { exists: true, count, path }
}

async function isProxyRunning(): Promise<{ up: boolean; reachable_url: string }> {
  const url = "http://127.0.0.1:4000/health/readiness"
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(800) })
    return { up: r.ok, reachable_url: url }
  } catch {
    return { up: false, reachable_url: url }
  }
}

function which(cmd: string): string | null {
  // Bun.which is the lightest reliable check.
  return Bun.which(cmd)
}

function locateLitellm(): string | null {
  // setup.sh installs litellm into a project-local venv; the proxy
  // start script prefers that path. Fall back to PATH for users who
  // installed it globally before adopting setup.sh.
  const venv = join(here, ".venv", "bin", "litellm")
  if (existsSync(venv)) return venv
  return which("litellm")
}

function summariseTool(name: string, hint: string, locator: () => string | null = () => which(name)): { line: string; ok: boolean } {
  const path = locator()
  if (path) {
    return { line: `${GREEN}✓${RESET} ${BOLD}${name}${RESET}  ${DIM}${path}${RESET}`, ok: true }
  }
  return { line: `${RED}✗${RESET} ${BOLD}${name}${RESET}  ${DIM}not on PATH — ${hint}${RESET}`, ok: false }
}

export async function printStatus(): Promise<void> {
  const providers = readProviders()
  const cfg = readLitellmConfig()
  const swival = readSwivalProfiles()
  const proxy = await isProxyRunning()
  const log = countRequestLog()

  console.log()
  console.log(`${BOLD}=== llm-routing status ===${RESET}`)
  console.log()

  console.log(`${BOLD}Tooling${RESET}`)
  console.log(`  ${summariseTool("litellm", "run ./setup.sh to install into .venv/", locateLitellm).line}`)
  console.log(`  ${summariseTool("swival",  "run ./setup.sh (brew install swival/tap/swival)").line}`)
  console.log(`  ${summariseTool("bun",     "comes from the Nix dev shell (run ./setup.sh)").line}`)
  console.log(`  ${summariseTool("nix",     "run ./setup.sh — installs Nix via the Determinate installer").line}`)
  if (process.env.IN_NIX_SHELL) {
    console.log(`  ${GREEN}✓${RESET} ${BOLD}nix dev shell${RESET}  ${DIM}entered (IN_NIX_SHELL=${process.env.IN_NIX_SHELL})${RESET}`)
  } else {
    console.log(`  ${YELLOW}-${RESET} ${BOLD}nix dev shell${RESET}  ${DIM}not entered — route.sh/llm.sh re-exec into it automatically${RESET}`)
  }
  console.log()

  console.log(`${BOLD}Proxy${RESET}`)
  if (proxy.up) {
    console.log(`  ${GREEN}✓${RESET} LiteLLM proxy is responding on ${CYAN}${proxy.reachable_url}${RESET}`)
  } else {
    console.log(`  ${YELLOW}-${RESET} LiteLLM proxy is not reachable on ${CYAN}http://127.0.0.1:4000${RESET} ${DIM}(start with ./start-proxy.sh)${RESET}`)
  }
  console.log()

  console.log(`${BOLD}Provider API keys${RESET}`)
  for (const p of providers.providers) {
    const value = process.env[p.env]
    const present = value && value.length > 0
    const marker = present ? `${GREEN}✓${RESET}` : `${YELLOW}-${RESET}`
    const masked = present ? `${DIM}${maskKey(value!)}${RESET}` : `${DIM}not set — ${p.signup_url}${RESET}`
    console.log(`  ${marker} ${BOLD}${p.env.padEnd(20)}${RESET} ${p.label.padEnd(34)} ${masked}`)
  }
  console.log()

  console.log(`${BOLD}LiteLLM model aliases${RESET}  ${DIM}(${cfg.modelNames.length} declared in litellm.config.yaml)${RESET}`)
  if (cfg.modelNames.length === 0) {
    console.log(`  ${YELLOW}-${RESET} no model_list entries found — check litellm.config.yaml`)
  } else {
    for (const name of cfg.modelNames) {
      const requiredEnv = cfg.modelKeyEnv[name]
      const present = requiredEnv ? !!process.env[requiredEnv] : true
      const marker = present ? `${GREEN}✓${RESET}` : `${YELLOW}-${RESET}`
      const aliasTarget = cfg.aliasTargets[name]
      const target = aliasTarget ? ` ${DIM}→ ${aliasTarget}${RESET}` : ""
      const detail = requiredEnv
        ? present
          ? `${DIM}${requiredEnv} set${RESET}`
          : `${YELLOW}${requiredEnv} not set${RESET}`
        : `${DIM}no env requirement${RESET}`
      console.log(`  ${marker} ${name.padEnd(22)} ${detail}${target}`)
    }
  }
  console.log()

  console.log(`${BOLD}Swival profiles${RESET}  ${DIM}(${swival.profiles.length} declared in ${swival.found ? "swival.toml" : "?"})${RESET}`)
  if (!swival.found) {
    console.log(`  ${YELLOW}-${RESET} ${swival.path} not found — re-run install-llm-routing.sh`)
  } else if (swival.profiles.length === 0) {
    console.log(`  ${YELLOW}-${RESET} no profiles found — check ${swival.path}`)
  } else {
    const wrap = (xs: string[], width: number): string[] => {
      const lines: string[] = []
      let cur = ""
      for (const x of xs) {
        if ((cur + ", " + x).length > width) {
          lines.push(cur)
          cur = x
        } else {
          cur = cur ? `${cur}, ${x}` : x
        }
      }
      if (cur) lines.push(cur)
      return lines
    }
    for (const line of wrap(swival.profiles, 76)) {
      console.log(`  ${line}`)
    }
  }
  console.log()

  console.log(`${BOLD}Request log${RESET}  ${DIM}(${log.path.replace(projectRoot + "/", "")})${RESET}`)
  if (!log.exists) {
    console.log(`  ${YELLOW}-${RESET} no log yet — proxy hasn't run, or no requests have completed`)
  } else {
    console.log(`  ${GREEN}✓${RESET} ${log.count} request record${log.count === 1 ? "" : "s"}`)
    console.log(`  ${DIM}view with: ./route.sh tail   ./route.sh costs${RESET}`)
  }
  console.log()
}

function maskKey(value: string): string {
  if (value.length <= 8) return "***"
  return `${value.slice(0, 4)}…${value.slice(-4)}`
}

if (import.meta.main) {
  await printStatus()
}
