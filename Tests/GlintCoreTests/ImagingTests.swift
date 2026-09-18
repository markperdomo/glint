import CZlib
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GlintCore

struct FixtureDirectory {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GlintTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  func remove() { try? FileManager.default.removeItem(at: url) }
  func image(
    _ name: String, width: Int = 120, height: Int = 80, orientation: Int = 1, type: UTType = .png,
    frames: Int = 1
  ) throws -> URL {
    let url = url.appendingPathComponent(name)
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
    for _ in 0..<frames {
      CGImageDestinationAddImage(
        destination, image,
        [
          kCGImagePropertyOrientation: orientation,
          kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2],
        ] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return url
  }
}

@Test func imageIOProducesBoundedOrientedThumbnails() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = try directory.image(
    "orientation.jpg", width: 120, height: 80, orientation: 6, type: .jpeg)
  let decoded = try ImageDecoder.decode(ImageAsset(url: url), maximumDimension: 60)
  #expect(decoded.image.width == 40)
  #expect(decoded.image.height == 60)
  #expect(decoded.metadata.pixelWidth == 80)
  #expect(decoded.metadata.pixelHeight == 120)
}

@Test func animatedGIFExposesFramesAndTiming() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = try directory.image("animation.gif", type: .gif, frames: 3)
  let decoded = try ImageDecoder.decode(ImageAsset(url: url), frame: 2)
  #expect(decoded.metadata.frameCount == 3)
  #expect(decoded.metadata.isAnimated)
  #expect(abs(decoded.frameDuration - 0.2) < 0.01)
  #expect(throws: (any Error).self) { try ImageDecoder.decode(ImageAsset(url: url), frame: 3) }
}

@Test func openingAnImageBrowsesSiblingsAndRecursionIsExplicit() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let first = try directory.image("image2.png")
  _ = try directory.image("image10.png")
  _ = try directory.image(".hidden.png")
  try Data("not an image".utf8).write(to: directory.url.appendingPathComponent("notes.txt"))
  let subdirectory = directory.url.appendingPathComponent("nested")
  try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
  try FileManager.default.copyItem(at: first, to: subdirectory.appendingPathComponent("nested.png"))
  let result = try FolderScanner.open([first])
  #expect(result.assets.count == 2)
  #expect(result.initialID == ImageAsset(url: first).id)
  #expect(try FolderScanner.open([directory.url], recursive: true).assets.count == 3)
  #expect(try FolderScanner.open([first, first]).assets.count == 1)
}

@Test func corruptImageReportsAnErrorInsteadOfCrashing() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("broken.png")
  try Data([0, 1, 2, 3]).write(to: url)
  #expect(throws: (any Error).self) { try ImageDecoder.decode(ImageAsset(url: url)) }
}

@Test func editsExportOriginalResolutionAndDoNotChangeOriginal() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let source = try directory.image("original.png")
  let original = try Data(contentsOf: source)
  var edits = ImageEdits()
  edits.quarterTurns = 1
  edits.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
  let destination = directory.url.appendingPathComponent("export.png")
  try ImageEditing.export(
    ImageAsset(url: source), frame: 0, edits: edits, to: destination, format: .png)
  let exported = try ImageDecoder.decode(ImageAsset(url: destination))
  #expect(exported.image.width == 40)
  #expect(exported.image.height == 120)
  #expect(try Data(contentsOf: source) == original)
}

@Test func cacheEnforcesBudgetAndReloadsChangedFiles() async throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = try directory.image("a.png", width: 40, height: 40)
  let a = ImageAsset(url: url, byteCount: 100, modified: Date(timeIntervalSince1970: 1))
  let pipeline = ImagePipeline(byteLimit: 20_000)
  _ = try await pipeline.image(for: a, maximumDimension: 40)
  _ = try await pipeline.image(for: a, maximumDimension: 40)
  let b = ImageAsset(url: url, byteCount: 101, modified: Date(timeIntervalSince1970: 2))
  _ = try await pipeline.image(for: b, maximumDimension: 40)
  var stats = await pipeline.statistics
  #expect(stats.hits == 1)
  #expect(stats.misses == 2)
  #expect(stats.bytes <= 20_000)
  await pipeline.invalidate(url: url)
  stats = await pipeline.statistics
  #expect(stats.count == 0)
  #expect(stats.bytes == 0)
  let tiny = ImagePipeline(byteLimit: 1)
  _ = try await tiny.image(for: a)
  #expect(await tiny.statistics.count == 0)
}

@Test func pdfPagesRenderAtRequestedSize() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("pages.pdf")
  var rect = CGRect(x: 0, y: 0, width: 300, height: 200)
  let context = try #require(CGContext(url as CFURL, mediaBox: &rect, nil))
  for _ in 0..<2 {
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(rect)
    context.endPDFPage()
  }
  context.closePDF()
  let decoded = try ImageDecoder.decode(ImageAsset(url: url), frame: 1, maximumDimension: 600)
  #expect(decoded.metadata.frameCount == 2)
  #expect(decoded.image.width == 600)
  #expect(decoded.image.height == 400)
  #expect(!decoded.metadata.isAnimated)
}
