#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - App Icon Generator
// Generates a beautiful app icon using SF Symbols + solid background
// Output: AppIcon.icns

let iconSize: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath

// Create iconset directory
let iconsetPath = "\(outputPath)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: CGFloat) -> NSImage {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocusFlipped(false)

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        canvas.unlockFocus()
        return canvas
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Background: solid blue rounded rect
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    ctx.setFillColor(CGColor(red: 0.20, green: 0.42, blue: 0.82, alpha: 1.0))
    ctx.fill(rect)

    // Simple border
    ctx.setStrokeColor(CGColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.4))
    ctx.setLineWidth(size * 0.01)
    ctx.stroke(rect.insetBy(dx: size * 0.02, dy: size * 0.02))

    // Draw network symbol
    let symbolSize = size * 0.60
    let symbolRect = CGRect(x: (size - symbolSize) / 2, y: (size - symbolSize) / 2 + size * 0.02,
                           width: symbolSize, height: symbolSize)
    if let symbolImage = NSImage(systemSymbolName: "network", accessibilityDescription: "Network Monitor") {
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize * 0.85, weight: .regular)
        if let configured = symbolImage.withSymbolConfiguration(config) {
            configured.draw(in: symbolRect)
        }
    }

    canvas.unlockFocus()
    return canvas
}

// Generate all required sizes
let sizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
]

for (size, scale) in sizes {
    let pixelSize = size * scale
    let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    let filePath = "\(iconsetPath)/\(filename)"

    let image = renderIcon(size: CGFloat(pixelSize))

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Warning: Failed to create CGImage for \(filename)")
        continue
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    bitmapRep.size = NSSize(width: pixelSize, height: pixelSize)

    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Warning: Failed to create PNG for \(filename)")
        continue
    }

    try pngData.write(to: URL(fileURLWithPath: filePath))
    print("  OK \(filename) (\(pixelSize)x\(pixelSize))")
}

// Convert iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "--output", "\(outputPath)/AppIcon.icns"]

let pipe = Pipe()
process.standardError = pipe

try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("\nOK AppIcon.icns created successfully!")
    try? FileManager.default.removeItem(atPath: iconsetPath)
} else {
    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
    let errorStr = String(data: errorData, encoding: .utf8) ?? "unknown error"
    print("\nFailed: \(errorStr)")
}
