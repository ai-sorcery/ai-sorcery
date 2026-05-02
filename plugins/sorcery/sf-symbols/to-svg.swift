#!/usr/bin/env swift
// Render a named SF Symbol to an SVG using Vision framework contour detection.
// Extracts proper vector paths — works with complex shapes (cat, person, etc.).
// Uses public AppKit / Vision APIs — no automation permissions needed.
//
// Usage:
//   swift scripts/sf-symbol-to-svg.swift <symbol-name> [output.svg] [--detail low|medium|high]
//
// Examples:
//   swift scripts/sf-symbol-to-svg.swift bolt.fill public/icons/bolt.svg
//   swift scripts/sf-symbol-to-svg.swift cat /tmp/cat.svg
//   swift scripts/sf-symbol-to-svg.swift cat /tmp/cat-hd.svg --detail high
//
// Detail levels control polygon simplification (Ramer-Douglas-Peucker
// epsilon, expressed as a fraction of the normalized image dimension):
//   low    — smallest file, polygon approximation (good for 16-48 px icons)
//   medium — balanced (default, good for most uses)
//   high   — full bezier curves, largest file, best for hero illustrations
//
// Output is a square viewBox="0 0 1 1" SVG with fill="currentColor", so it
// inherits the surrounding text color when embedded inline.

import AppKit
import Vision

// Diagnostics go to stderr so a caller can redirect 2>/dev/null to suppress
// them without losing the success line written to stdout.
func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Argument parsing

let args = CommandLine.arguments
guard args.count >= 2 else {
    warn("Usage: swift \(args[0]) <symbol-name> [output.svg] [--detail low|medium|high]")
    warn("")
    warn("Detail levels:")
    warn("  low    — smallest file, polygon approximation (good for 16-48 px icons)")
    warn("  medium — balanced (default, good for most uses)")
    warn("  high   — full bezier curves, largest file")
    exit(2)
}

let symbolName = args[1]

// Pull --detail out of the argument list so the remaining positionals are
// just <symbol-name> and optional <output>.
var detailLevel = "medium"
var positional: [String] = []
var i = 2
while i < args.count {
    if args[i] == "--detail" {
        guard i + 1 < args.count else {
            warn("ERROR: --detail requires a value (low | medium | high)")
            exit(2)
        }
        detailLevel = args[i + 1]
        i += 2
    } else {
        positional.append(args[i])
        i += 1
    }
}

guard ["low", "medium", "high"].contains(detailLevel) else {
    warn("ERROR: --detail must be one of: low, medium, high (got '\(detailLevel)')")
    exit(2)
}

let outputPath = positional.first
    ?? "\(symbolName.replacingOccurrences(of: ".", with: "-")).svg"

// epsilon = nil means "no polygon simplification" — keeps the raw bezier
// curves Vision returns, producing the largest, smoothest path.
let epsilon: Float? = {
    switch detailLevel {
    case "low":  return 0.003
    case "high": return nil
    default:     return 0.001
    }
}()

// MARK: - Render the symbol to a bitmap

guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    warn("ERROR: Unknown SF Symbol '\(symbolName)'")
    warn("Hint: search the system catalog with 'bun scripts/sf-symbol-search.ts <query>'.")
    exit(1)
}

// 256 pt is large enough that contour detection picks up fine details without
// burning too much memory. .medium weight matches the default visual weight
// the SF Symbols app shows.
let config = NSImage.SymbolConfiguration(pointSize: 256, weight: .medium)
let image = baseImage.withSymbolConfiguration(config)!
let size = image.size
let W = Int(size.width)
let H = Int(size.height)

// Black symbol on white background — required for Vision's
// detectsDarkOnLight contour detection to work cleanly.
guard let context = CGContext(
    data: nil, width: W, height: H,
    bitsPerComponent: 8, bytesPerRow: W * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    warn("ERROR: Could not create CGContext")
    exit(1)
}

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: W, height: H))

let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
NSColor.black.setFill()
image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let cgImage = context.makeImage() else {
    warn("ERROR: Could not create CGImage from context")
    exit(1)
}

// MARK: - Run Vision contour detection

let request = VNDetectContoursRequest()
request.contrastAdjustment = 1.0
request.detectsDarkOnLight = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    warn("ERROR: Vision contour detection failed: \(error)")
    exit(1)
}

guard let observation = request.results?.first else {
    warn("ERROR: No contours detected — symbol may have rendered blank")
    exit(1)
}

// MARK: - Build the SVG path data

// VNContour.polygonApproximation(epsilon:) is per-contour, not per-observation,
// so when simplifying we walk the contour tree manually and combine the
// simplified subpaths. When epsilon is nil we use the observation's combined
// normalizedPath directly.
let contourPath: CGPath
if let eps = epsilon {
    let combined = CGMutablePath()
    func addSimplified(_ contour: VNContour) {
        if let simplified = try? contour.polygonApproximation(epsilon: eps) {
            combined.addPath(simplified.normalizedPath)
        } else {
            combined.addPath(contour.normalizedPath)
        }
        for child in contour.childContours {
            addSimplified(child)
        }
    }
    for contour in observation.topLevelContours {
        addSimplified(contour)
    }
    contourPath = combined
} else {
    contourPath = observation.normalizedPath
}

// Vision returns paths in normalized (0,0)-(1,1) coords with Y going up.
// SVG Y goes down, so we flip.
let pathBounds = contourPath.boundingBox
guard !pathBounds.isEmpty else {
    warn("ERROR: Empty path bounds — nothing to draw")
    exit(1)
}

var svgCommands: [String] = []
var elementCount = 0

contourPath.applyWithBlock { elementPtr in
    let el = elementPtr.pointee
    let pts = el.points

    func tx(_ p: CGPoint) -> (String, String) {
        let x = (p.x - pathBounds.minX) / pathBounds.width
        let y = 1.0 - ((p.y - pathBounds.minY) / pathBounds.height)
        return (String(format: "%.3f", x), String(format: "%.3f", y))
    }

    switch el.type {
    case .moveToPoint:
        let (x, y) = tx(pts[0])
        svgCommands.append("M\(x) \(y)")
    case .addLineToPoint:
        let (x, y) = tx(pts[0])
        svgCommands.append("L\(x) \(y)")
    case .addQuadCurveToPoint:
        let (cx, cy) = tx(pts[0])
        let (x, y) = tx(pts[1])
        svgCommands.append("Q\(cx) \(cy) \(x) \(y)")
    case .addCurveToPoint:
        let (c1x, c1y) = tx(pts[0])
        let (c2x, c2y) = tx(pts[1])
        let (x, y) = tx(pts[2])
        svgCommands.append("C\(c1x) \(c1y) \(c2x) \(c2y) \(x) \(y)")
    case .closeSubpath:
        svgCommands.append("Z")
    @unknown default:
        break
    }
    elementCount += 1
}

let pathData = svgCommands.joined()

// viewBox 0 0 1 1: path coords are already normalized to 0-1.
// SVG's default preserveAspectRatio="xMidYMid meet" handles non-square symbols.
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1" fill="currentColor" fill-rule="evenodd">
  <!-- SF Symbol: \(symbolName) -->
  <path d="\(pathData)"/>
</svg>
"""

do {
    try svg.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch {
    warn("ERROR: Could not write \(outputPath): \(error)")
    exit(1)
}

let kb = String(format: "%.1f", Double(svg.count) / 1024)
print("Wrote \(outputPath) (\(elementCount) elements, \(kb) KB, detail: \(detailLevel))")
