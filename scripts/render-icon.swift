#!/usr/bin/env swift
// Renders AIStat's app icon programmatically with CoreGraphics.
// Independent of any SVG renderer (no rsvg-convert / Inkscape required).
// Outputs PNGs at every size macOS expects, then iconutil packs them into .icns.
//
// Usage: swift scripts/render-icon.swift <output-iconset-dir>

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// macOS requires these exact sizes (pixels, including the @2x variants).
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let s = size

    // Continuous-corner squircle background (approx via rounded rect).
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(
        roundedRect: bgRect.insetBy(dx: s * 0.045, dy: s * 0.045),
        cornerWidth: s * 0.223, cornerHeight: s * 0.223,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Vertical dark gradient.
    let colors = [CGColor(red: 0.12, green: 0.165, blue: 0.267, alpha: 1),
                  CGColor(red: 0.055, green: 0.082, blue: 0.149, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Gauge geometry: centre near the top, opens downward.
    let cx = s * 0.5
    let cy = s * 0.48
    let r = s * 0.30
    let trackW = s * 0.045

    func arcPath(from startAngle: CGFloat, to endAngle: CGFloat) -> CGPath {
        // CoreGraphics measures angles in radians, 0 = east, positive = CCW.
        // Flip so the gauge opens downward like a fuel gauge.
        // Using CGMutablePath.addArc avoids SDK drift in the CGPath arc init.
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: false)
        return path
    }

    // Track: full sweep, ~270 degrees from 135 to 405 (i.e. -45 going CCW).
    ctx.saveGState()
    ctx.setLineWidth(trackW)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 0.173, green: 0.227, blue: 0.353, alpha: 1))
    ctx.addPath(arcPath(from: .pi * 0.75, to: .pi * 2.25))
    ctx.strokePath()

    // Active arc: ~75% of the sweep, three-stop spectrum gradient.
    let arcColors = [CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1),  // green
                     CGColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1),     // yellow
                     CGColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1)] as CFArray // red
    let arcGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: arcColors, locations: [0, 0.55, 1])!
    // Stroke with a gradient: clip to the arc path, then fill the clip.
    let sweepStart: CGFloat = .pi * 0.75
    let sweepEnd: CGFloat = .pi * 0.75 + (.pi * 1.5) * 0.75  // 75% of 1.5pi sweep
    ctx.addPath(arcPath(from: sweepStart, to: sweepEnd))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(arcGrad,
                           start: CGPoint(x: cx - r, y: cy),
                           end: CGPoint(x: cx + r, y: cy),
                           options: [])
    ctx.restoreGState()

    // Tick marks.
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.353, green: 0.420, blue: 0.549, alpha: 1))
    let tickCount = 7
    for i in 0..<tickCount {
        let t = CGFloat(i) / CGFloat(tickCount - 1)
        let angle = .pi * 0.75 + t * (.pi * 1.5)
        let tx = cx + cos(angle) * (r + trackW * 0.6)
        let ty = cy + sin(angle) * (r + trackW * 0.6)
        let tickRect = CGRect(x: tx - s * 0.012, y: ty - s * 0.012,
                              width: s * 0.024, height: s * 0.024)
        ctx.fillEllipse(in: tickRect)
    }
    ctx.restoreGState()

    // Needle: white, pointing at the 75% mark.
    let needleAngle = sweepEnd
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.902, green: 0.925, blue: 1.0, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.022)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + cos(needleAngle) * r * 0.85,
                            y: cy + sin(needleAngle) * r * 0.85))
    ctx.strokePath()

    // Pivot hub.
    ctx.setFillColor(CGColor(red: 0.902, green: 0.925, blue: 1.0, alpha: 1))
    let hubRect = CGRect(x: cx - s * 0.042, y: cy - s * 0.042,
                         width: s * 0.084, height: s * 0.084)
    ctx.fillEllipse(in: hubRect)
    ctx.restoreGState()
}

for spec in sizes {
    let pixels = spec.pixels
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create context for \(spec.name)")
    }
    drawIcon(into: ctx, size: CGFloat(pixels))
    guard let img = ctx.makeImage() else { fatalError("render failed for \(spec.name)") }
    let bmp = NSBitmapImageRep(cgImage: img)
    guard let png = bmp.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed for \(spec.name)")
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.name).png")
    try png.write(to: url)
}

print("rendered \(sizes.count) PNGs into \(outDir)")
