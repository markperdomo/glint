#!/usr/bin/env swift
// Reproducible viewing/benchmark fixtures. No downloaded or personal photographs.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/Glint-Samples")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let width = 6000, height = 4000
for index in 1...12 {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let shift = CGFloat(index - 1) / 12
    let colors = [NSColor(calibratedHue: 0.07 + shift, saturation: 0.22, brightness: 0.94, alpha: 1).cgColor,
                  NSColor(calibratedHue: 0.11 + shift, saturation: 0.5, brightness: 0.65, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
    for band in 0..<5 {
        let path = CGMutablePath()
        path.move(to: .zero)
        for step in 0...100 {
            let x = CGFloat(step) * CGFloat(width) / 100
            let y = CGFloat(500 + band * 440) + sin(x / CGFloat(700 + band * 130) + CGFloat(index) * 0.4 + CGFloat(band)) * 280
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: width, y: 0)); path.closeSubpath()
        context.setFillColor(NSColor(calibratedHue: 0.1 + shift, saturation: 0.27 + CGFloat(band) * 0.08, brightness: 0.32 + CGFloat(band) * 0.11, alpha: 1).cgColor)
        context.addPath(path); context.fillPath()
    }
    context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.7).cgColor)
    context.fillEllipse(in: CGRect(x: 4050, y: 2550, width: 620, height: 620))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let label = String(format: "GLINT  /  %02d", index)
    label.draw(at: NSPoint(x: 340, y: 3300), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 84, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.8), .kern: 14])
    "Color · edges · detail".draw(at: NSPoint(x: 340, y: 3070), withAttributes: [.font: NSFont.systemFont(ofSize: 164, weight: .light), .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.8)])
    "6000 × 4000 pixels   /   sRGB   /   generated test image".draw(at: NSPoint(x: 350, y: 2880), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 48, weight: .regular), .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.65)])
    NSGraphicsContext.restoreGraphicsState()
    let image = context.makeImage()!
    let url = directory.appendingPathComponent(String(format: "Image%02d.jpg", index))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Fixture encoding failed") }
}
print("Created 12 synthetic 24 MP JPEGs in \(directory.path)")
