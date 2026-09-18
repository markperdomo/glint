import AppKit
import CoreGraphics
import Foundation
import GlintCore
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Glint

@Suite(.serialized) @MainActor
struct ViewerModelTests {
  private func makeFolder(scale: Int = 1) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GlintModelTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 1...12 {
      let url = folder.appendingPathComponent("image\(index).png")
      let context = try #require(
        CGContext(
          data: nil, width: index * 20 * scale, height: 40 * scale, bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(gray: CGFloat(index) / 12, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: index * 20 * scale, height: 40 * scale))
      let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
      #expect(CGImageDestinationFinalize(destination))
    }
    return folder
  }
  private func makeModel() -> ViewerModel {
    let defaults = UserDefaults(suiteName: "GlintTests-\(UUID().uuidString)")!
    return ViewerModel(preferences: Preferences(defaults: defaults))
  }

  @Test func fitEnlargementDefaultsOnAndRespectsSavedPreferences() throws {
    let suite = "GlintFitPreferencesTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.enlargesSmallImages)
    preferences.enlargesSmallImages = false
    #expect(!Preferences(defaults: defaults).enlargesSmallImages)
    preferences.enlargesSmallImages = true
    #expect(Preferences(defaults: defaults).enlargesSmallImages)
  }

  private func settled(_ model: ViewerModel) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isLoading || model.isScanning {
      guard ContinuousClock.now < deadline else {
        Issue.record("Viewer did not finish loading")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.errorMessage == nil)
    #expect(model.loadError == nil)
  }

  @Test func rapidNavigationPublishesOnlyTheLastRequestedImage() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = makeModel()
    defer { model.suspend() }
    model.open([folder])
    try await settled(model)
    for _ in 0..<10 { model.navigate(1) }
    try await settled(model)
    #expect(model.current?.shortName == "image11.png")
    #expect(model.decoded?.metadata.pixelWidth == 220)
    #expect(model.displayImage?.width == 220)
  }

  @Test func navigationPublishesCachedThumbnailSynchronouslyThenRefinesIt() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let pipeline = ImagePipeline(byteLimit: 1_000_000)
    let thumbnails = ImagePipeline(byteLimit: 100_000)
    let defaults = UserDefaults(suiteName: "GlintPreviewTests-\(UUID().uuidString)")!
    let model = ViewerModel(
      preferences: Preferences(defaults: defaults), pipeline: pipeline,
      thumbnailPipeline: thumbnails)
    defer { model.suspend() }
    model.open([folder])
    try await settled(model)
    let target = try #require(model.visibleAssets.first { $0.shortName == "image7.png" })
    let preview = try await thumbnails.image(for: target, maximumDimension: 40)
    model.select(target.id)
    // No await: these pixels and their original dimensions must be published
    // before the asynchronous foreground request has any opportunity to run.
    #expect(model.current?.id == target.id)
    #expect(model.displayImage === preview.image)
    #expect(model.displayPixelSize == CGSize(width: 140, height: 40))
    #expect(model.isLoading)
    try await settled(model)
    #expect(model.displayImage?.width == 140)
    #expect(model.loadError == nil)
    // A fully cached image also survives navigation without a blank turn.
    model.first()
    model.select(target.id)
    #expect(model.displayImage?.width == 140)
    try await settled(model)
  }

  @Test func rapidNavigationRefinesALargeCachedPreviewAfterSettling() async throws {
    let folder = try makeFolder(scale: 10)
    defer { try? FileManager.default.removeItem(at: folder) }
    let pipeline = ImagePipeline(byteLimit: 20_000_000)
    let defaults = UserDefaults(suiteName: "GlintRefinementTests-\(UUID().uuidString)")!
    let model = ViewerModel(
      preferences: Preferences(defaults: defaults), pipeline: pipeline,
      thumbnailPipeline: ImagePipeline(byteLimit: 0))
    defer { model.suspend() }
    model.open([folder])
    try await settled(model)
    let target = try #require(model.visibleAssets.first { $0.shortName == "image10.png" })
    _ = try await pipeline.image(for: target, maximumDimension: 512)
    model.select(model.visibleAssets[7].id)
    model.navigate(1)
    model.navigate(1)
    #expect(model.current?.id == target.id)
    #expect(model.displayImage?.width == 512)
    #expect(model.displayPixelSize == CGSize(width: 2000, height: 400))
    #expect(model.isLoading)
    try await settled(model)
    #expect(model.displayImage?.width == 2000)
    #expect(!model.isLoading)
  }

  @Test func rapidDirectionChangesStillSettleOnTheCorrectImage() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = makeModel()
    defer { model.suspend() }
    model.open([folder])
    try await settled(model)
    for _ in 0..<6 { model.navigate(1) }
    for _ in 0..<3 { model.navigate(-1) }
    try await settled(model)
    #expect(model.current?.shortName == "image4.png")
    #expect(model.displayImage?.width == 80)
    #expect(!model.isLoading)
  }

  @Test func sortingPreservesSelectionAndFilteringClearsStaleImages() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = makeModel()
    defer { model.suspend() }
    model.open([folder.appendingPathComponent("image2.png")])
    try await settled(model)
    let selected = model.selectedID
    model.sortReversed = true
    #expect(model.selectedID == selected)
    #expect(model.current?.shortName == "image2.png")
    model.query = "no matching image"
    #expect(model.visibleAssets.isEmpty)
    #expect(model.selectedID == nil)
    #expect(model.displayImage == nil)
    model.query = "image10"
    try await settled(model)
    #expect(model.current?.shortName == "image10.png")
    #expect(model.decoded?.metadata.pixelWidth == 200)
  }

  @Test func deletingTheInitiallyOpenedFileStillRefreshesItsFolder() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("image2.png")
    let model = makeModel()
    defer { model.suspend() }
    model.open([original])
    try await settled(model)
    try FileManager.default.removeItem(at: original)
    model.refresh()
    try await settled(model)
    #expect(model.assets.count == 11)
    #expect(model.current?.shortName == "image3.png")
    #expect(model.decoded?.metadata.pixelWidth == 60)
  }

  @Test func staleFolderScansCannotReplaceANewerOpen() async throws {
    let first = try makeFolder()
    let second = try makeFolder()
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
    }
    let model = makeModel()
    defer { model.suspend() }
    model.open([first])
    model.open([second.appendingPathComponent("image7.png")])
    try await settled(model)
    #expect(model.location?.path == second.path)
    #expect(model.current?.shortName == "image7.png")
    #expect(model.decoded?.metadata.pixelWidth == 140)
  }

  @Test func arrowImmediatelyAfterZoomUsesTheNewMode() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = makeModel()
    defer { model.suspend() }
    model.open([folder])
    try await settled(model)
    let canvas = ImageCanvas()
    canvas.model = model
    canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    canvas.update(
      image: model.displayImage, pixels: CGSize(width: 6000, height: 4000), zoom: .fit, custom: 1,
      reset: 0, background: .charcoal, nearest: false, enlarges: false, cropping: false)
    let selected = model.selectedID
    model.setZoom(.actual)
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "\u{F703}",
        charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
    #expect(canvas.handleKey(event))
    #expect(model.selectedID == selected)
  }
}
