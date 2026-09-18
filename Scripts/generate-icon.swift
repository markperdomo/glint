#!/usr/bin/env swift
// Original vector artwork; generates all macOS icon sizes without external assets.
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let directory = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 204, yRadius: 204)
        NSGradient(starting: NSColor(srgbRed: 0.89, green: 0.92, blue: 0.80, alpha: 1), ending: NSColor(srgbRed: 0.63, green: 0.72, blue: 0.49, alpha: 1))!.draw(in: tile, angle: -90)
        NSColor(srgbRed: 0.18, green: 0.27, blue: 0.12, alpha: 1).setStroke()
        let corners = NSBezierPath(); corners.lineWidth = 28; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
        for (x, y, sx, sy) in [(290.0,290.0,1.0,1.0),(734.0,290.0,-1.0,1.0),(290.0,734.0,1.0,-1.0),(734.0,734.0,-1.0,-1.0)] {
            corners.move(to: NSPoint(x: x + 100*sx, y: y)); corners.line(to: NSPoint(x: x, y: y)); corners.line(to: NSPoint(x: x, y: y + 100*sy))
        }
        corners.stroke()
        NSColor(srgbRed: 0.18, green: 0.27, blue: 0.12, alpha: 1).setFill()
        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: 512, y: 685))
        sparkle.curve(to: NSPoint(x: 685, y: 512), controlPoint1: NSPoint(x: 536, y: 562), controlPoint2: NSPoint(x: 562, y: 536))
        sparkle.curve(to: NSPoint(x: 512, y: 339), controlPoint1: NSPoint(x: 562, y: 488), controlPoint2: NSPoint(x: 536, y: 462))
        sparkle.curve(to: NSPoint(x: 339, y: 512), controlPoint1: NSPoint(x: 488, y: 462), controlPoint2: NSPoint(x: 462, y: 488))
        sparkle.curve(to: NSPoint(x: 512, y: 685), controlPoint1: NSPoint(x: 462, y: 536), controlPoint2: NSPoint(x: 488, y: 562))
        sparkle.fill()
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try representation.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
print("Generated Glint app icon")
