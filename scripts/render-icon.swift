#!/usr/bin/env swift
// Renders AIMonitor's app icon from the SVG source via NSImage.
// Uses macOS native SVG rasterisation for faithful vector rendering.
// Background added in code (light-blue rounded rect matching the -bg SVG).
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

// The SVG glyph (no background, just the monitor shape) in teal.
let svgGlyph = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="256" height="256">
  <g fill="#006d8f">
    <path d="M12,24C5.4,24,0,18.6,0,12S5.4,0,12,0s12,5.4,12,12S18.6,24,12,24z M12,2C6.5,2,2,6.5,2,12s4.5,10,10,10s10-4.5,10-10S17.5,2,12,2z"/>
    <rect x="2" y="16" width="20" height="2"/>
    <path d="M12,18c-0.2,0-0.3,0-0.5-0.1c-0.5-0.3-0.6-0.9-0.4-1.4l5-8.7c0.3-0.5,0.9-0.6,1.4-0.4c0.5,0.3,0.6,0.9,0.4,1.4l-5,8.7C12.7,17.8,12.3,18,12,18z"/>
  </g>
</svg>
"""

// Write the glyph SVG to a temp file for NSImage to load.
let tempSVG = "/tmp/aistat-glyph.svg"
try svgGlyph.write(toFile: tempSVG, atomically: true, encoding: .utf8)
let svgURL = URL(fileURLWithPath: tempSVG)
guard let glyphImage = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("could not load glyph SVG\n".data(using: .utf8)!)
    exit(1)
}

for spec in sizes {
    let pixels = spec.pixels
    // Render at 4x then downscale for clean anti-aliased edges, no halos.
    let renderRes = pixels * 4
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: renderRes,
        pixelsHigh: renderRes,
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
    rep.size = NSSize(width: renderRes, height: renderRes)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none

    // Flat white rounded rect background (no teal, no gradient, no shadow).
    let cornerR = CGFloat(renderRes) * 0.225
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: renderRes, height: renderRes),
                              xRadius: cornerR, yRadius: cornerR)
    NSColor.white.setFill()
    bgPath.fill()

    // Draw the glyph SVG centered with generous padding (~75% of icon).
    let inset = CGFloat(renderRes) * 0.125
    glyphImage.draw(in: NSRect(x: inset, y: inset,
                               width: CGFloat(renderRes) - 2 * inset,
                               height: CGFloat(renderRes) - 2 * inset),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    // Downscale to target resolution with high quality interpolation.
    guard let downscaled = NSBitmapImageRep(
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
        FileHandle.standardError.write("downscale failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    downscaled.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: downscaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = downscaled.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.name).png")
    try png.write(to: url)
}

print("rendered \(sizes.count) PNGs into \(outDir)")
