#!/usr/bin/env swift
// Renders AIMonitor's app icon with direct CoreGraphics path drawing.
// No SVG rasterization = no anti-aliasing halos or shadow artifacts.
// Pure flat: white bg, teal paths.
//
// Usage: swift scripts/render-icon.swift <output-iconset-dir>

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let teal = CGColor(red: 0.0, green: 0.427, blue: 0.561, alpha: 1)

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let s = size

    // White rounded rect background.
    let cornerR = s * 0.225
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: cornerR, cornerHeight: cornerR)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // Center the gauge in the icon with ~20% padding on all sides.
    let inset = s * 0.2
    let gx = inset
    let gy = inset
    let gw = s - 2 * inset
    let gh = s - 2 * inset
    let gcx = gx + gw / 2
    let gcy = gy + gh / 2
    let gr = gw * 0.42
    let lw = s * 0.045

    ctx.setStrokeColor(teal)
    ctx.setFillColor(teal)
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // 1. Circle outline (the gauge dial).
    let circleRect = CGRect(x: gcx - gr, y: gcy - gr, width: gr * 2, height: gr * 2)
    ctx.addEllipse(in: circleRect)
    ctx.strokePath()

    // 2. Horizontal bar near the bottom of the circle.
    let barY = gcy - gr * 0.33
    ctx.move(to: CGPoint(x: gcx - gr * 0.83, y: barY))
    ctx.addLine(to: CGPoint(x: gcx + gr * 0.83, y: barY))
    ctx.strokePath()

    // 3. Diagonal needle from lower-left up to upper-right.
    ctx.move(to: CGPoint(x: gcx - gr * 0.25, y: gcy + gr * 0.05))
    ctx.addLine(to: CGPoint(x: gcx + gr * 0.5, y: gcy + gr * 0.67))
    ctx.strokePath()
}

for spec in sizes {
    let pixels = spec.pixels
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        FileHandle.standardError.write("context failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    // Full antialiasing for smooth strokes.
    ctx.setShouldAntialias(true)
    drawIcon(into: ctx, size: CGFloat(pixels))

    guard let img = ctx.makeImage() else {
        FileHandle.standardError.write("render failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: img)
    guard let png = bmp.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.name).png")
    try png.write(to: url)
}

print("rendered \(sizes.count) PNGs into \(outDir)")
