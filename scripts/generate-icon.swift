#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift OUTPUT.icns\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let fileManager = FileManager.default
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int, destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "MacCapIcon", code: 1)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MacCapIcon", code: 2)
    }
    NSGraphicsContext.current = context

    let size = CGFloat(pixelSize)
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let outer = canvas.insetBy(dx: size * 0.065, dy: size * 0.065)
    let radius = size * 0.22
    let background = NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius)
    NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.31, green: 0.12, blue: 0.82, alpha: 1)
    )!.draw(in: background, angle: -58)

    let sheetRect = NSRect(x: size * 0.255, y: size * 0.19, width: size * 0.49, height: size * 0.62)
    let sheet = NSBezierPath(roundedRect: sheetRect, xRadius: size * 0.055, yRadius: size * 0.055)
    NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
    sheet.fill()

    NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.78, alpha: 0.75).setStroke()
    for row in 0..<4 {
        let y = sheetRect.maxY - size * (0.14 + CGFloat(row) * 0.105)
        let line = NSBezierPath()
        line.lineWidth = max(1, size * 0.018)
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: sheetRect.minX + size * 0.075, y: y))
        line.line(to: NSPoint(x: sheetRect.maxX - size * 0.075, y: y))
        line.stroke()
    }

    let arrow = NSBezierPath()
    arrow.lineWidth = max(2, size * 0.045)
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.98, green: 0.38, blue: 0.31, alpha: 1).setStroke()
    arrow.move(to: NSPoint(x: size * 0.50, y: size * 0.43))
    arrow.line(to: NSPoint(x: size * 0.50, y: size * 0.29))
    arrow.move(to: NSPoint(x: size * 0.42, y: size * 0.35))
    arrow.line(to: NSPoint(x: size * 0.50, y: size * 0.27))
    arrow.line(to: NSPoint(x: size * 0.58, y: size * 0.35))
    arrow.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MacCapIcon", code: 3)
    }
    try png.write(to: destination)
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    try renderIcon(pixelSize: variant.pixels, destination: iconsetURL.appendingPathComponent(variant.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", outputURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "MacCapIcon", code: Int(process.terminationStatus))
}
try? fileManager.removeItem(at: iconsetURL)
