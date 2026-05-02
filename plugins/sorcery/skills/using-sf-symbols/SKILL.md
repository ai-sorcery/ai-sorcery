---
name: using-sf-symbols
description: Use when the user wants to use SF Symbols as the icon source for a project — phrasings like "I need an icon for X", "find an SF Symbol that looks like Y", "convert <symbol> to SVG", "set up SF Symbols tooling in this repo", "search SF Symbols". Installs two scripts under `scripts/` — `sf-symbol-search.ts` (keyword search across the system catalog) and `sf-symbol-to-svg.swift` (renders a named symbol to a `viewBox="0 0 1 1"` SVG with `fill="currentColor"`).
---

# Using SF Symbols

Apple's SF Symbols is a catalog of ~6000 vector glyphs that ships free with macOS. This skill turns it into a no-friction icon source for any project: search by keyword, pick a symbol, get an SVG with `fill="currentColor"` ready to drop into a web UI, README, or design mockup.

The tooling is two small scripts:

- **`scripts/sf-symbol-search.ts`** (Bun TypeScript) — searches the system catalog by name and designer-curated keywords. Multi-word queries are AND'd; matches rank by name-segment specificity.
- **`scripts/sf-symbol-to-svg.swift`** — renders a named symbol to a square `viewBox="0 0 1 1"` SVG. Uses public AppKit + Vision contour detection, so no automation permissions prompt and no SF Symbols.app dependency.

Neither script needs the SF Symbols.app to be installed — the catalog they read lives in `CoreGlyphs.bundle` and ships with macOS. The app is only useful as a visual browser for humans picking symbols.

## Installing

Run the installer from the root of the user's repo:

```bash
"${CLAUDE_PLUGIN_ROOT}/sf-symbols/install.sh"
```

It is idempotent — re-running picks up newer versions of either script. The installer:

1. Creates `scripts/` if it doesn't exist.
2. Copies `sf-symbol-search.ts` and `sf-symbol-to-svg.swift` into `scripts/`, marking both executable.
3. Prints a one-shot search and convert example so the user can verify end-to-end.

The skill does not depend on Apple's SF Symbols.app — the search and conversion scripts read the OS-shipped catalog and use AppKit's `NSImage(systemSymbolName:)` directly. If a designer wants the visual browser anyway, it's a one-liner: `brew install --cask sf-symbols`. No wrapper needed.

## Workflow

When the user asks for an icon ("I need a lightning bolt", "what's a good icon for download?"), do the search → preview → convert dance:

### 1. Search

```bash
bun scripts/sf-symbol-search.ts "<keyword>" --limit 10
```

The output lists symbol names with their associated keywords. Examples:

```
Found 35 symbols for "bolt" (showing 3):

  bolt  (camera, energy, power)
  bolt.fill  (camera, energy, power)
  cloud.bolt  (weather)
```

Pick whichever name fits. Symbols often come in `.fill` / outlined / `.circle` / `.square` variants — `bolt.fill` is the same glyph as `bolt` but solid-filled. The naming convention is consistent enough that once the user finds one variant, they can guess the rest.

### 2. Convert to SVG

```bash
swift scripts/sf-symbol-to-svg.swift <symbol-name> <output-path> [--detail low|medium|high]
```

Examples:

```bash
swift scripts/sf-symbol-to-svg.swift bolt.fill public/icons/bolt.svg
swift scripts/sf-symbol-to-svg.swift heart /tmp/heart.svg --detail high
```

`--detail` controls polygon simplification:

- **low** — smallest file, polygon approximation. Good for 16-48 px icons where the simplification is invisible.
- **medium** (default) — balanced. Good for most uses.
- **high** — full bezier curves, largest file. Use for hero illustrations or anywhere the symbol is shown above ~120 px.

The output is a square `viewBox="0 0 1 1"` SVG with `fill="currentColor"`, so it inherits surrounding text color when embedded inline:

```html
<span style="color: tomato"><!-- bolt.svg contents --></span>
```

### 3. Use it

Inline in HTML, drop into a CSS background-image (URL-encoded), or feed into a component library that takes raw SVG. The single-path output also makes the symbol easy to animate via CSS or to recolor by region with a manual edit.

## Caveats

- **SF Symbols are licensed for use as system images in apps that run on Apple platforms.** Outside of that — exporting them as standalone SVGs to ship in a non-Apple-platform product, embedding them in a logo, or modifying the shape — falls outside Apple's guidelines. Read Apple's [SF Symbols license](https://developer.apple.com/sf-symbols/) before publishing converted SVGs. This skill makes the conversion *technically* easy; the licensing question is the user's to answer, and a developer who reads "macOS only" first and stops there might ship a converted SVG without ever seeing the licensing note — so this caveat is first on purpose.
- **macOS only.** The search script needs `/System/Library/CoreServices/CoreGlyphs.bundle/`; the conversion script needs AppKit and Vision. Both fail fast on non-Darwin with a clear message. There's no Linux fallback — Linux users would need to point a different toolchain at the same SVG output shape.
- **Depends on `bun` and `swift` being on PATH.** The search script is Bun TypeScript; the conversion script is a Swift script. Bun installs via `brew install oven-sh/bun/bun` or the official installer; `swift` lives in the Xcode Command Line Tools (`xcode-select --install`). Neither install is automated by this skill. Missing `bun` produces a plain `command not found`. Missing `swift` triggers macOS's "Install the Command Line Developer Tools?" prompt on a desktop session, or an `xcrun: error: invalid active developer path` failure when there's no GUI; in either case the original invocation still exits non-zero and the user has to retry once the tools are in place.
- **Some symbols use multicolor or hierarchical rendering at runtime.** The conversion captures the *base shape* — what you'd see if you set the symbol's rendering mode to monochrome. Symbols designed around hierarchical layers (e.g. `person.crop.circle.badge.plus`) lose the layered effect when reduced to a single path. Pick a different symbol or accept the simplification.
- **Vision contour detection occasionally trips on very thin strokes.** Hairline-weight glyphs may render as broken outlines. The default `.medium` weight in the conversion script is the fix for the common case; if a specific symbol still looks broken, check whether it has a `.fill` variant — solid shapes always trace cleanly.
- **`--detail high` files are large.** A complex symbol like `heart` produces ~19 KB at high detail vs. ~700 bytes at medium. Don't ship `high` to a slow-loading first-paint critical path; medium is the safe default.

## Related skills

- `following-best-practices` — SF Symbols isn't on the language-agnostic catalog (it's Apple-specific) but is a reasonable answer to the *Starter scripts at the repo root* question for any project that already needs icons.
