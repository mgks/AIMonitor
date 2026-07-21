#!/usr/bin/env swift
// Renders AIStat's app icon from the SVG source (Resources/AppIcon.svg)
// onto a macOS squircle background with padding, then packs it into .icns.
//
// Loads the SVG through NSImage (macOS native SVG support), so the icon is
// rendered faithfully from its vector path with no external converter.
//
// Usage: swift scripts/render-icon.swift <output-iconset-dir> [svg-path]

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let svgPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "Resources/AppIcon.svg"

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

func renderSVGMask(_ url: URL, pixels: Int) -> CGImage? {
    guard let svg = NSImage(contentsOf: url) else { return nil }
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
             from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

func drawIcon(svgURL: URL, pixels: Int) -> CGImage? {
    let s = CGFloat(pixels)
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let iconMask = renderSVGMask(svgURL, pixels: pixels)
    else { return nil }

    // Squircle background, inset to match macOS icon grid margins.
    let inset = s * 0.045
    let bgRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: s * 0.223, cornerHeight: s * 0.223,
                        transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [CGColor(red: 0.122, green: 0.165, blue: 0.267, alpha: 1),
                    CGColor(red: 0.055, green: 0.082, blue: 0.149, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Icon glyph centred with padding so it never touches the squircle edge.
    let pad = s * 0.18
    let iconRect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)

    ctx.saveGState()
    ctx.clip(to: iconRect, mask: iconMask)
    ctx.setFillColor(CGColor(red: 0.941, green: 0.965, blue: 1.0, alpha: 1))
    ctx.fill(iconRect)
    ctx.restoreGState()

    return ctx.makeImage()
}

let svgURL = URL(fileURLWithPath: svgPath)
guard FileManager.default.fileExists(atPath: svgPath) else {
    FileHandle.standardError.write("SVG not found at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

for spec in sizes {
    guard let img = drawIcon(svgURL: svgURL, pixels: spec.pixels) else {
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
