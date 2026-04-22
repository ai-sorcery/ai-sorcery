#!/usr/bin/env bun
/**
 * Post-processor for loop/stream.jq output.
 *
 * jq can't invoke external processes, so the jq filter wraps the `.result`
 * payload (a markdown document) in the  ...  sentinels. This
 * script streams jq's output unchanged, except for the wrapped region,
 * which it swaps for `Bun.markdown.ansi(content)`.
 *
 * Usage (inside loop.sh):
 *   claude ... | tee log | jq -f stream.jq | bun render.ts
 */

const MD_BEGIN = ""
const MD_END = ""

type BunWithMarkdown = typeof Bun & { markdown?: { ansi?: (s: string) => string } }

/** Render markdown to ANSI; fall through to raw text if the API is missing. */
export function renderMarkdown(s: string): string {
  const b = Bun as BunWithMarkdown
  const fn = b.markdown?.ansi
  if (typeof fn !== "function") return s
  try {
    return fn(s)
  } catch {
    return s
  }
}

/**
 * Consume text chunks; emit pass-through chunks immediately and buffer
 * content between MD_BEGIN/MD_END so the completed markdown renders in
 * one shot.
 */
export class LoopRenderStream {
  private inMd = false
  private mdBuf = ""
  private out: (s: string) => void

  constructor(write: (s: string) => void) {
    this.out = write
  }

  push(text: string): void {
    let pos = 0
    while (pos < text.length) {
      if (!this.inMd) {
        const idx = text.indexOf(MD_BEGIN, pos)
        if (idx === -1) {
          this.out(text.slice(pos))
          return
        }
        this.out(text.slice(pos, idx))
        pos = idx + MD_BEGIN.length
        this.inMd = true
        this.mdBuf = ""
      } else {
        const idx = text.indexOf(MD_END, pos)
        if (idx === -1) {
          this.mdBuf += text.slice(pos)
          return
        }
        this.mdBuf += text.slice(pos, idx)
        this.out(renderMarkdown(this.mdBuf))
        pos = idx + MD_END.length
        this.inMd = false
        this.mdBuf = ""
      }
    }
  }

  /** Emit any buffered markdown unrendered — only called at EOF. */
  flush(): void {
    if (this.inMd && this.mdBuf.length > 0) {
      this.out(this.mdBuf)
      this.mdBuf = ""
      this.inMd = false
    }
  }
}

if (import.meta.main) {
  const decoder = new TextDecoder()
  const stream = new LoopRenderStream((s) => process.stdout.write(s))
  for await (const chunk of Bun.stdin.stream()) {
    stream.push(decoder.decode(chunk, { stream: true }))
  }
  stream.push(decoder.decode())
  stream.flush()
}
