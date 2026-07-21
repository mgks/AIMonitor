#!/usr/bin/env swift
// Renders AIMonitor's app icon from Resources/AppIcon.svg.
// The SVG already includes a flat white background with rounded corners,
// so we just rasterise it at every size macOS expects and pack into .icns.
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

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

guard FileManager.default.fileExists(atPath: svgPath) else {
    FileHandle.standardError.write("SVG not found at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

let svgURL = URL(fileURLWithPath: svgPath)

for spec in sizes {
    let pixels = spec.pixels
    guard let svg = NSImage(contentsOf: svgURL) else {
        FileHandle.standardError.write("could not load SVG\n".data(using: .utf8)!)
        exit(1)
    }

    // Rasterise the SVG at the target pixel size.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("bitmap rep failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Fill transparent so the SVG's own white background shows cleanly.
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
             from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let outURL = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.name).png")
    try png.write(to: outURL)
}

print("rendered \(sizes.count) PNGs into \(outDir)")
