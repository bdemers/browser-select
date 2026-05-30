// Generates BrowserSelect's app icon as an .icns, drawn from scratch with CoreGraphics.
//
// Motif ("mini picker"): the icon is a tiny version of the app itself — a small browser
// list on a card, with one row highlighted (selected) like the real picker. Original
// artwork; no third-party or SF Symbol assets, so it carries no licensing constraints.
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
    let cs = CGColorSpaceCreateDeviceRGB()
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: cs, components: [r, g, b, a])!
    }

    // macOS app icons leave a transparent margin around the rounded-rect body.
    let margin = s * 0.085
    let inner = s - 2 * margin

    /// Rect from normalized body coords (0..1, y-up: `b`=bottom, `t`=top).
    func rect(_ l: CGFloat, _ b: CGFloat, _ r: CGFloat, _ t: CGFloat) -> CGRect {
        CGRect(
            x: margin + l * inner, y: margin + b * inner,
            width: (r - l) * inner, height: (t - b) * inner)
    }
    func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // --- Background: clipped squircle with a vertical gradient (indigo → blue) ---
    let body = CGRect(x: margin, y: margin, width: inner, height: inner)
    cg.saveGState()
    cg.addPath(rounded(body, inner * 0.2237))
    cg.clip()
    let bg = CGGradient(
        colorsSpace: cs,
        colors: [
            color(0.36, 0.30, 0.96),  // top
            color(0.16, 0.52, 0.98),  // bottom
        ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    cg.restoreGState()

    // --- Picker card (light, with a soft drop shadow) ---
    let card = rect(0.13, 0.15, 0.87, 0.85)
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -inner * 0.012),
        blur: inner * 0.045, color: color(0, 0, 0, 0.28))
    cg.addPath(rounded(card, inner * 0.055))
    cg.setFillColor(color(0.97, 0.97, 0.98))
    cg.fillPath()
    cg.restoreGState()

    // --- Three rows; the middle one is "selected" (accent fill) ---
    // (top, bottom, browser-dot color, highlighted)
    let rows: [(CGFloat, CGFloat, CGColor, Bool)] = [
        (0.780, 0.635, color(0.92, 0.26, 0.21), false),  // red
        (0.575, 0.430, color(1.00, 1.00, 1.00), true),  // selected (white dot on accent)
        (0.370, 0.225, color(0.20, 0.66, 0.33), false),  // green
    ]
    let rowL: CGFloat = 0.18, rowR: CGFloat = 0.82
    let accent = color(0.20, 0.52, 0.96)

    for (top, bottom, dot, highlighted) in rows {
        let mid = (top + bottom) / 2

        if highlighted {
            cg.addPath(rounded(rect(0.155, bottom - 0.020, 0.845, top + 0.020), inner * 0.030))
            cg.setFillColor(accent)
            cg.fillPath()
        }

        // Browser swatch dot.
        let dotR = inner * 0.040
        let dotX = margin + (rowL + 0.045) * inner
        let dotY = margin + mid * inner
        cg.setFillColor(dot)
        cg.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: 2 * dotR, height: 2 * dotR))

        // "Name" bar (a pill standing in for the browser name text).
        let barH = inner * 0.050
        let bar = rect(rowL + 0.11, mid - barH / inner / 2, rowR - 0.02, mid + barH / inner / 2)
        cg.addPath(rounded(bar, barH / 2))
        cg.setFillColor(highlighted ? color(1, 1, 1, 0.95) : color(0.60, 0.62, 0.70))
        cg.fillPath()
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
