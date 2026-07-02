#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        red = CGFloat((hex >> 16) & 0xff) / 255
        green = CGFloat((hex >> 8) & 0xff) / 255
        blue = CGFloat(hex & 0xff) / 255
        self.alpha = alpha
    }

    var color: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, scale: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: (1024 - y - height) * scale, width: width * scale, height: height * scale)
}

func topPoint(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> NSPoint {
    NSPoint(x: x * scale, y: (1024 - y) * scale)
}

func drawCircle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat, scale: CGFloat, color: NSColor) {
    color.setFill()
    let rect = topRect(centerX - radius, centerY - radius, radius * 2, radius * 2, scale: scale)
    NSBezierPath(ovalIn: rect).fill()
}

func sparklePath(centerX: CGFloat, centerY: CGFloat, outer: CGFloat, inner: CGFloat, scale: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [
        (centerX, centerY - outer),
        (centerX + inner, centerY - inner),
        (centerX + outer, centerY),
        (centerX + inner, centerY + inner),
        (centerX, centerY + outer),
        (centerX - inner, centerY + inner),
        (centerX - outer, centerY),
        (centerX - inner, centerY - inner)
    ]

    path.move(to: topPoint(points[0].0, points[0].1, scale: scale))
    for point in points.dropFirst() {
        path.line(to: topPoint(point.0, point.1, scale: scale))
    }
    path.close()
    return path
}

func drawIcon(size: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "JustChatIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate bitmap"])
    }

    let canvasSize = CGFloat(size)
    let scale = canvasSize / 1024
    bitmap.size = NSSize(width: canvasSize, height: canvasSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

    let backgroundRect = topRect(56, 56, 912, 912, scale: scale)
    let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 214 * scale, yRadius: 214 * scale)

    let gradient = NSGradient(colors: [
        RGB(0xffffff).color,
        RGB(0xedeff1).color
    ])
    gradient?.draw(in: backgroundPath, angle: -52)

    RGB(0xd9dee3).color.setStroke()
    backgroundPath.lineWidth = max(1, 3 * scale)
    backgroundPath.stroke()

    let shadow = NSShadow()
    shadow.shadowColor = RGB(0x0f1720, alpha: 0.18).color
    shadow.shadowBlurRadius = 34 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -30 * scale)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    RGB(0x202225).color.setFill()

    let tail = NSBezierPath()
    tail.move(to: topPoint(336, 622, scale: scale))
    tail.curve(to: topPoint(241, 760, scale: scale),
               controlPoint1: topPoint(324, 688, scale: scale),
               controlPoint2: topPoint(282, 734, scale: scale))
    tail.curve(to: topPoint(468, 660, scale: scale),
               controlPoint1: topPoint(327, 766, scale: scale),
               controlPoint2: topPoint(411, 733, scale: scale))
    tail.line(to: topPoint(420, 620, scale: scale))
    tail.close()
    tail.fill()

    let bubble = NSBezierPath(roundedRect: topRect(188, 304, 648, 356, scale: scale),
                              xRadius: 126 * scale,
                              yRadius: 126 * scale)
    bubble.fill()
    NSGraphicsContext.restoreGraphicsState()

    RGB(0xf7f9fa).color.setFill()
    drawCircle(centerX: 402, centerY: 490, radius: 34, scale: scale, color: RGB(0xf7f9fa).color)
    drawCircle(centerX: 512, centerY: 490, radius: 34, scale: scale, color: RGB(0xf7f9fa).color)
    drawCircle(centerX: 622, centerY: 490, radius: 34, scale: scale, color: RGB(0xf7f9fa).color)

    RGB(0x00c878).color.setFill()
    sparklePath(centerX: 760, centerY: 288, outer: 100, inner: 30, scale: scale).fill()
    RGB(0x00c878, alpha: 0.85).color.setFill()
    sparklePath(centerX: 292, centerY: 268, outer: 54, inner: 16, scale: scale).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "JustChatIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG at \(url.path)"])
    }
    try pngData.write(to: url, options: .atomic)
}

let previewImage = try drawIcon(size: 1024)
try writePNG(previewImage, to: resourcesURL.appendingPathComponent("AppIcon.png"))

let iconFiles: [(String, Int)] = [
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

for (filename, size) in iconFiles {
    try writePNG(try drawIcon(size: size), to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetURL.path,
    "-o", resourcesURL.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "JustChatIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print(resourcesURL.appendingPathComponent("AppIcon.icns").path)
