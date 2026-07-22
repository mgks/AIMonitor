#!/usr/bin/env swift
// Renders AIMonitor's app icon programmatically with CoreGraphics.
// Design: circle outline + horizontal bar + diagonal needle (teal on light-blue).
// Flat, no shadows. Matches the monitor-icon SVG source.
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

// Colors from the SVG: fill #006d8f, bg #caf0fe
let tealColor = CGColor(red: 0.0, green: 0.427, blue: 0.561, alpha: 1)
let lightBlue = CGColor(red: 0.792, green: 0.941, blue: 0.996, alpha: 1)

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let s = size

    // Rounded rect background (light blue).
    let cornerR = s * 0.225
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: cornerR, cornerHeight: cornerR)
    ctx.addPath(bgPath)
    ctx.setFillColor(lightBlue)
    ctx.fillPath()

    // Circle outline (teal).
    let cx = s * 0.5
    let cy = s * 0.5
    let r = s * 0.375
    ctx.setStrokeColor(tealColor)
    ctx.setLineWidth(s * 0.067)
    ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    ctx.strokePath()

    // Horizontal bar near bottom of circle.
    let barY = cy - r * 0.35
    ctx.move(to: CGPoint(x: cx - r * 0.85, y: barY))
    ctx.addLine(to: CGPoint(x: cx + r * 0.85, y: barY))
    ctx.setLineWidth(s * 0.067)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Diagonal needle: from lower-left going up to upper-right.
    // Matches the SVG path: starts near (0.4, 0.6), ends near (0.7, 0.2).
    let needle = CGMutablePath()
    needle.move(to: CGPoint(x: cx - r * 0.25, y: cy + r * 0.05))
    needle.addLine(to: CGPoint(x: cx + r * 0.5, y: cy + r * 0.7))
    ctx.addPath(needle)
    ctx.setLineWidth(s * 0.067)
    ctx.setLineCap(.round)
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
    ctx.setShouldAntialias(pixels >= 64)
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
