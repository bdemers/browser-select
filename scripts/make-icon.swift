// Generates BrowserSelect's app icon as an .icns, drawn from scratch with CoreGraphics.
//
// Motif: a single "link" (trunk node, bottom) branching up to three browser nodes —
// representing one URL being routed to one of several browsers. Original artwork; no
// third-party or SF Symbol assets, so it carries no licensing constraints.
//
// Usage: swift scripts/make-icon.swift <output.iconset-dir>
// Then:  iconutil -c icns <output.iconset-dir> -o AppBundle/AppIcon.icns
//
// Run via `make icon`, which wraps both steps.

import AppKit
import CoreGraphics

/// Renders the icon at a single square pixel size and returns PNG data.
func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let cg = nsctx.cgContext

    // macOS app icons leave a transparent margin around the rounded-rect body.
    let margin = s * 0.085
    let inner = s - 2 * margin
    let body = CGRect(x: margin, y: margin, width: inner, height: inner)
    let radius = inner * 0.2237 // approximates the macOS squircle corner

    // Map normalized coords (0..1 within the body, y-up) to canvas points.
    func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: margin + nx * inner, y: margin + ny * inner)
    }

    // --- Background: clipped rounded rect with a vertical gradient ---
    let bg = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(bg)
    cg.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(colorSpace: cs, components: [0.36, 0.30, 0.96, 1.0])!, // indigo (top)
            CGColor(colorSpace: cs, components: [0.16, 0.52, 0.98, 1.0])!, // blue (bottom)
        ] as CFArray,
        locations: [0.0, 1.0])!
    cg.drawLinearGradient(gradient, start: p(0.5, 1.0), end: p(0.5, 0.0), options: [])
    cg.restoreGState()

    // --- Branch geometry ---
    let trunk = p(0.5, 0.20)
    let leftN = p(0.24, 0.74)
    let midN  = p(0.5, 0.82)
    let rightN = p(0.76, 0.74)

    let lineW = inner * 0.055
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 0.95])!)
    cg.setLineWidth(lineW)
    for end in [leftN, midN, rightN] {
        cg.move(to: trunk)
        // gentle curve from trunk up to each node
        let ctrl = CGPoint(x: (trunk.x + end.x) / 2, y: trunk.y + (end.y - trunk.y) * 0.65)
        cg.addQuadCurve(to: end, control: ctrl)
    }
    cg.strokePath()

    // --- Trunk node (the incoming link): solid white dot ---
    let trunkR = inner * 0.055
    cg.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!)
    cg.fillEllipse(in: CGRect(x: trunk.x - trunkR, y: trunk.y - trunkR, width: 2*trunkR, height: 2*trunkR))

    // --- Browser nodes: colored discs with a white ring ---
    let nodeR = inner * 0.115
    let ring = inner * 0.022
    let colors: [[CGFloat]] = [
        [0.92, 0.26, 0.21, 1.0], // red
        [0.20, 0.66, 0.33, 1.0], // green
        [0.26, 0.52, 0.96, 1.0], // blue
    ]
    for (i, center) in [leftN, midN, rightN].enumerated() {
        // white ring (slightly larger filled circle behind)
        let outerR = nodeR + ring
        cg.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!)
        cg.fillEllipse(in: CGRect(x: center.x - outerR, y: center.y - outerR, width: 2*outerR, height: 2*outerR))
        // colored disc
        cg.setFillColor(CGColor(colorSpace: cs, components: colors[i])!)
        cg.fillEllipse(in: CGRect(x: center.x - nodeR, y: center.y - nodeR, width: 2*nodeR, height: 2*nodeR))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// --- Emit the full iconset ---
guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) pairs required by iconutil.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in variants {
    let data = renderPNG(size: px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("Wrote \(variants.count) icon variants to \(outDir)")
