#!/usr/bin/env bun
/**
 * CLI helper for the improvement-loop shell scripts. Each command is the
 * JSON/state-manipulation body of a user-facing helper — start.sh,
 * finish.sh, progress.sh, time-check.sh — routed through a single file
 * so each piece is testable in isolation.
 *
 * Usage: bun run helpers.ts <command> [args...]
 *
 * Commands:
 *   start-recovery  <state_file> <timestamp>
 *   start-assign    <personas_file> <counter> <timestamp> <state_file> <counter_file> <script_dir>
 *   finish          <state_file> <script_dir> <summary> <details> <end_time>
 *   progress        <state_file> <script_dir> <status> [files...]
 *   time-check      <state_file> <script_dir>
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync } from "node:fs"
import { join } from "node:path"

const [, , command, ...args] = process.argv

function parseTimestamp(s: string): Date {
  // "2026-04-06 08:03 UTC" → Date
  return new Date(`${s.replace(" UTC", "Z").replace(" ", "T")}`)
}

function elapsedMinutes(start: string, end: string): number {
  try {
    return (parseTimestamp(end).getTime() - parseTimestamp(start).getTime()) / 60000
  } catch {
    return 999
  }
}

function formatDuration(mins: number): string {
  mins = Math.max(1, Math.round(mins))
  if (mins >= 60) {
    const h = Math.floor(mins / 60)
    const m = mins % 60
    return `${h}h${String(m).padStart(2, "0")}m`
  }
  return `${mins}m`
}

function readJSON<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf-8"))
}

function startRecovery() {
  const [stateFile, timestamp] = args
  const s = readJSON<Record<string, unknown>>(stateFile!)
  const mins = elapsedMinutes(s.started_at as string, timestamp!)

  if (mins < 60) {
    console.log(`⏳ Previous iteration started ${Math.floor(mins)}m ago — likely still running.`)
    console.log("Do nothing. Wait for it to finish.")
    process.exit(0)
  }

  console.log("⚠️  RECOVERY NEEDED — previous iteration did not complete (over 60m stale).")
  console.log()
  console.log(`  Iteration: ${s.iteration}`)
  console.log(`  Persona:   ${s.persona_name}`)
  console.log(`  Started:   ${s.started_at}`)
  console.log(`  Status:    ${s.status}`)
  const files = (s.files_touched as string[]) ?? []
  if (files.length) console.log(`  Files:     ${files.join(", ")}`)
  console.log()
  console.log("Assess the state, then complete or revert the work.")
  console.log("When done, run: ./improvement/finish.sh 'summary' 'details'")
}

function startAssign() {
  const [personasFile, counterStr, timestamp, stateFile, counterFile, scriptDir] = args
  const counter = parseInt(counterStr!, 10)
  const personas = readJSON<
    Array<{ id: string; name: string; description: string; instructions: string[]; showGlobalHistory?: number }>
  >(personasFile!)
  const index = counter % personas.length
  const p = personas[index]!

  writeFileSync(
    stateFile!,
    JSON.stringify(
      {
        iteration: counter,
        persona_id: p.id,
        persona_name: p.name,
        started_at: timestamp,
        status: "Starting",
        files_touched: [],
      },
      null,
      2,
    ),
  )

  writeFileSync(counterFile!, `${counter + 1}\n`)

  writeFileSync(
    join(scriptDir!, "IN-PROGRESS.md"),
    `# In Progress\n\n## Iteration ${counter} — ${p.name}\nStarted: ${timestamp}\nStatus: Starting\nFiles touched: (none yet)\n`,
  )

  const bar = "═".repeat(56)
  console.log(`╔${bar}╗`)
  console.log(`║  IMPROVEMENT LOOP — ITERATION ${counter}`)
  console.log(`║  ${timestamp}`)
  console.log(`╠${bar}╣`)
  console.log(`║  Persona: ${p.name}`)
  console.log(`║  ID:      ${p.id}`)
  console.log(`╚${bar}╝`)
  console.log()
  console.log(p.description)
  console.log()
  console.log("Instructions:")
  p.instructions.forEach((step, i) => console.log(`  ${i + 1}. ${step}`))

  const nextP = personas[(index + 1) % personas.length]!
  console.log(`\nNext persona in rotation: ${nextP.name}`)

  // Session history from VERBOSE-CHANGELOG.md
  const verbosePath = join(scriptDir!, "VERBOSE-CHANGELOG.md")
  if (existsSync(verbosePath)) {
    const lines = readFileSync(verbosePath, "utf-8").split("\n")
    const durations = lines.filter((l) => l.includes("**Duration:**")).map((l) => l.trim())
    if (durations.length) {
      console.log("\n── Session History ──")
      for (const d of durations.slice(-5)) console.log(`  ${d}`)
    } else {
      console.log("\n── No prior sessions. Be conservative with scope. ──")
    }
  } else {
    console.log("\n── No prior sessions. Be conservative with scope. ──")
  }

  // Persona-specific history from SUCCINCT-CHANGELOG.md.
  const succinctPath = join(scriptDir!, "SUCCINCT-CHANGELOG.md")
  if (existsSync(succinctPath)) {
    const succinctLines = readFileSync(succinctPath, "utf-8").split("\n")
    const personaLines = succinctLines.filter((l) => l.includes(`| ${p.name}`))
    if (personaLines.length) {
      const recent = personaLines.slice(-10)
      console.log(`\n── Last ${recent.length} ${p.name} Runs ──`)
      for (const line of recent) {
        const cols = line.split("|").map((c) => c.trim()).filter(Boolean)
        const iter = cols[0] ?? "?"
        const summary = cols[4] ?? cols[cols.length - 1] ?? ""
        console.log(`  #${iter}: ${summary}`)
      }
    }

    // Global history (all personas) — opt-in via the persona's showGlobalHistory.
    if (p.showGlobalHistory) {
      const dataLines = succinctLines.filter((l) => /^\|\s*\d+/.test(l))
      if (dataLines.length) {
        const recent = dataLines.slice(-p.showGlobalHistory)
        console.log(`\n── Last ${recent.length} Iterations (All Personas) ──`)
        for (const line of recent) {
          const cols = line.split("|").map((c) => c.trim()).filter(Boolean)
          const iter = cols[0] ?? "?"
          const persona = cols[1] ?? "?"
          const summary = cols[4] ?? cols[cols.length - 1] ?? ""
          console.log(`  #${iter} [${persona}]: ${summary}`)
        }
      }
    }
  }
}

function finish() {
  const [stateFile, scriptDir, summary, details, endTime] = args
  const state = readJSON<Record<string, unknown>>(stateFile!)
  const iteration = state.iteration
  const persona = state.persona_name as string
  const personaId = state.persona_id as string
  const startTime = state.started_at as string
  const files = (state.files_touched as string[]) ?? []

  const mins = elapsedMinutes(startTime, endTime!)
  const duration = formatDuration(mins)

  // Append to SUCCINCT-CHANGELOG.md (skip if the iteration already has an entry).
  const succinctPath = join(scriptDir!, "SUCCINCT-CHANGELOG.md")
  const padded = (s: string, n: number) => s.padEnd(n)
  const succinctLine = `| ${String(iteration).padEnd(3)} | ${padded(persona, 20)} | ${padded(startTime, 16)} | ${padded(duration, 8)} | ${summary} |\n`
  const existing = existsSync(succinctPath) ? readFileSync(succinctPath, "utf-8") : ""
  const iterPrefix = `| ${String(iteration).padEnd(3)} |`
  if (!existing.includes(iterPrefix)) {
    writeFileSync(succinctPath, existing + succinctLine)
  }

  // Insert into VERBOSE-CHANGELOG.md (skip if the iteration already has an entry).
  const verbosePath = join(scriptDir!, "VERBOSE-CHANGELOG.md")
  let content = existsSync(verbosePath) ? readFileSync(verbosePath, "utf-8") : ""
  const iterHeader = `## Iteration ${iteration} —`

  if (!content.includes(iterHeader)) {
    const filesStr = files.length ? files.join(", ") : "none"
    const detailBlock = details ? `\n### Details\n${details}\n` : ""
    const entry = `## Iteration ${iteration} — ${personaId}

- **Persona:** ${persona}
- **Started:** ${startTime}
- **Finished:** ${endTime}
- **Duration:** ${duration}
- **Files touched:** ${filesStr}

### Summary
${summary}
${detailBlock}
---

`

    const marker = "<!-- New entries go here, most recent first -->"
    if (content.includes(marker)) {
      content = content.replace(marker, `${marker}\n\n${entry}`)
    } else {
      content += `\n${entry}`
    }
    writeFileSync(verbosePath, content)
  }

  writeFileSync(join(scriptDir!, "IN-PROGRESS.md"), "# In Progress\n\nNo active iteration.\n")
  unlinkSync(stateFile!)

  console.log(`✓ Iteration ${iteration} (${personaId}) finished — ${duration}`)
  console.log("  Changelogs updated. State cleared.")
}

function progress() {
  const [stateFile, scriptDir, status, ...newFiles] = args
  const state = readJSON<Record<string, unknown>>(stateFile!)
  state.status = status
  if (newFiles.length) {
    const existing = (state.files_touched as string[]) ?? []
    state.files_touched = [...new Set([...existing, ...newFiles])].sort()
  }

  writeFileSync(stateFile!, JSON.stringify(state, null, 2))

  const filesStr = (state.files_touched as string[]).length
    ? (state.files_touched as string[]).join(", ")
    : "(none yet)"
  writeFileSync(
    join(scriptDir!, "IN-PROGRESS.md"),
    `# In Progress\n\n## Iteration ${state.iteration} — ${state.persona_name}\nStarted: ${state.started_at}\nStatus: ${status}\nFiles touched: ${filesStr}\n`,
  )

  console.log(`✓ ${status}`)
}

function timeCheck() {
  const [stateFile, scriptDir] = args
  const state = readJSON<Record<string, unknown>>(stateFile!)
  const now = new Date().toISOString().replace("T", " ").slice(0, 16) + " UTC"
  const mins = elapsedMinutes(state.started_at as string, now)
  const elapsedStr = formatDuration(mins)

  console.log(`Iteration ${state.iteration} — ${state.persona_name}`)
  console.log(`  Elapsed: ${elapsedStr}`)
  console.log(`  Status:  ${state.status}`)

  const verbosePath = join(scriptDir!, "VERBOSE-CHANGELOG.md")
  if (!existsSync(verbosePath)) {
    console.log("  No past sessions for comparison.")
    return
  }

  const lines = readFileSync(verbosePath, "utf-8").split("\n")
  const durations = lines.filter((l) => l.includes("**Duration:**"))
  if (!durations.length) {
    console.log("  No past sessions for comparison.")
    return
  }

  const pastMins: number[] = []
  for (const d of durations) {
    const val = d.split("**Duration:**")[1]?.trim() ?? ""
    if (val.includes("h")) {
      const [h, m] = val.replace("m", "").split("h")
      pastMins.push(parseInt(h!, 10) * 60 + parseInt(m!, 10))
    } else {
      const n = parseInt(val.replace("m", ""), 10)
      if (!isNaN(n)) pastMins.push(n)
    }
  }
  if (!pastMins.length) {
    console.log("  No past sessions for comparison.")
    return
  }

  const avg = Math.floor(pastMins.reduce((a, b) => a + b, 0) / pastMins.length)
  console.log(`  Avg past session: ${avg}m (${pastMins.length} sessions)`)
  if (mins > avg * 1.5) {
    console.log(`  ⚠️  Running ${Math.floor(mins - avg)}m longer than average. Consider wrapping up.`)
  } else if (mins > avg) {
    console.log("  Approaching typical session length.")
  } else {
    console.log(`  ~${Math.floor(avg - mins)}m remaining based on average.`)
  }
}

switch (command) {
  case "start-recovery":
    startRecovery()
    break
  case "start-assign":
    startAssign()
    break
  case "finish":
    finish()
    break
  case "progress":
    progress()
    break
  case "time-check":
    timeCheck()
    break
  default:
    console.error(`Unknown command: ${command}`)
    console.error("Usage: bun run helpers.ts <command> [args...]")
    process.exit(1)
}
