#!/usr/bin/env swift
// Renders AIMonitor's app icon directly from Resources/AppIcon.svg.
// Rasterises the SVG via NSImage at each required size, then packs into .icns.
// Pure SVG rendering - the icon matches the source exactly.
//
// Usage: swift scripts/render-icon.swift <output-iconset-dir>

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let svgPath = "Resources/AppIcon.svg"

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard fm.fileExists(atPath: svgPath) else {
    FileHandle.standardError.write("SVG not found at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

let svgURL = URL(fileURLWithPath: svgPath)
guard let svgImage = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("Could not load SVG\n".data(using: .utf8)!)
    exit(1)
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for spec in sizes {
    let pixels = spec.pixels

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

    // White background filling the whole canvas (the SVG has no bg rect).
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    // Draw the SVG to fill the canvas.
    svgImage.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                  from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.name).png")
    try png.write(to: url)
}

print("rendered \(sizes.count) PNGs into \(outDir)")
