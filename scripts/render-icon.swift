#!/usr/bin/env swift
// Renders AIMonitor's app icon programmatically with CoreGraphics.
// Flat white background, dark rounded-rect outline, magenta graph line.
// No SVG loading, no shadows, no gradients: guaranteed flat output.
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

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let s = size

    // Flat white background filling the entire canvas.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded rect outline: dark grey, flat, no shadow.
    let inset = s * 0.103
    let rect = CGRect(x: inset, y: inset,
                      width: s - 2 * inset, height: s - 2 * inset)
    let frame = CGMutablePath()
    frame.addRoundedRect(in: rect, cornerWidth: s * 0.158,
                         cornerHeight: s * 0.158)
    ctx.addPath(frame)
    ctx.setStrokeColor(CGColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1))
    ctx.setLineWidth(s * 0.0583)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Magenta graph bump line: up-over-down shape.
    let line = CGMutablePath()
    let baseY = s * 0.517
    let peakY = s * 0.413
    line.move(to: CGPoint(x: s * 0.302, y: baseY))
    line.addLine(to: CGPoint(x: s * 0.404, y: baseY))
    line.addQuadCurve(
        to: CGPoint(x: s * 0.5, y: peakY),
        control: CGPoint(x: s * 0.453, y: baseY)
    )
    line.addQuadCurve(
        to: CGPoint(x: s * 0.596, y: baseY),
        control: CGPoint(x: s * 0.547, y: peakY)
    )
    line.addLine(to: CGPoint(x: s * 0.698, y: baseY))
    ctx.addPath(line)
    ctx.setStrokeColor(CGColor(red: 0.875, green: 0.078, blue: 0.388, alpha: 1))
    ctx.setLineWidth(s * 0.0583)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
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
    // Disable anti-aliasing on strokes for crisp pixel edges at small sizes.
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
