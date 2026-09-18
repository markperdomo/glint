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
  private func makeModel(cachesImages: Bool = true) -> ViewerModel {
    let defaults = UserDefaults(suiteName: "GlintTests-\(UUID().uuidString)")!
    return ViewerModel(
      preferences: Preferences(defaults: defaults),
      pipeline: cachesImages ? .shared : ImagePipeline(byteLimit: 0),
      thumbnailPipeline: cachesImages ? .thumbnails : ImagePipeline(byteLimit: 0))
  }

  private func updateCanvas(_ canvas: ImageCanvas, from model: ViewerModel) {
    canvas.update(
      image: model.displayImage, pixels: model.displayPixelSize,
      zoom: model.zoomMode, custom: model.customZoom, reset: model.panReset,
      background: model.preferences.background, nearest: model.preferences.nearestNeighbor,
      enlarges: model.preferences.enlargesSmallImages, cropping: model.cropMode,
      loading: model.isLoading)
  }

  @Test func uncachedNavigationHoldsPixelsAndFramingUntilReplacementIsReady() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = makeModel(cachesImages: false)
    defer { model.suspend() }
    model.preferences.remembersZoom = false
    model.open([folder])
    try await settled(model)
    model.zoom(by: 32)
    let canvas = ImageCanvas()
    canvas.model = model
    canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    updateCanvas(canvas, from: model)
    let down = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "\u{F701}",
        charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
    #expect(canvas.handleKey(down))
    canvas.layout()
    let layer = try #require(canvas.layer?.sublayers?.first)
    let original = try #require(model.displayImage)
    let originalFrame = layer.frame
    #expect(originalFrame.height > canvas.bounds.height)

    model.select(model.visibleAssets[6].id)
    #expect(model.isLoading)
    #expect(model.displayImage == nil)
    #expect(model.decoded == nil)
    #expect(!model.canEdit)
    #expect(model.zoomMode == .fit)
    updateCanvas(canvas, from: model)
    // Even an intervening layout must keep the old image's zoom and pan.
    canvas.layout()
    #expect((layer.contents as AnyObject?) === original)
    #expect(!layer.isHidden)
    #expect(layer.frame == originalFrame)
    #expect(canvas.accessibilityValue() as? String == "image1.png")

    // Repeated input navigates, rather than panning the retained old image.
    #expect(canvas.handleKey(down))
    #expect(model.current?.shortName == "image8.png")
    updateCanvas(canvas, from: model)
    #expect((layer.contents as AnyObject?) === original)
    #expect(layer.frame == originalFrame)
    try await settled(model)
    updateCanvas(canvas, from: model)
    #expect((layer.contents as AnyObject?) === model.displayImage)
    #expect(model.displayImage?.width == 160)
    #expect(!layer.isHidden)
    // The 4:1 replacement arrives in Fit, with pan reset, in the same update.
    #expect(abs(layer.frame.width - 368) < 0.001)
    #expect(abs(layer.frame.height - 92) < 0.001)
    #expect(abs(layer.frame.midX - canvas.bounds.midX) < 0.001)
    #expect(abs(layer.frame.midY - canvas.bounds.midY) < 0.001)
    #expect(canvas.accessibilityValue() as? String == "image8.png")

    model.select(model.visibleAssets[10].id)
    updateCanvas(canvas, from: model)
    #expect(!layer.isHidden)
    model.query = "no matching image"
    updateCanvas(canvas, from: model)
    #expect(layer.contents == nil)
    #expect(layer.isHidden)
  }

  @Test func failedReplacementClearsTheRetainedCanvasImage() async throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let broken = folder.appendingPathComponent("broken.png")
    try Data("not an image".utf8).write(to: broken)
    let model = makeModel(cachesImages: false)
    defer { model.suspend() }
    model.open([folder.appendingPathComponent("image1.png")])
    try await settled(model)
    let canvas = ImageCanvas()
    canvas.model = model
    canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    updateCanvas(canvas, from: model)
    let layer = try #require(canvas.layer?.sublayers?.first)
    let original = try #require(model.displayImage)
    model.select(try #require(model.visibleAssets.first { $0.url == broken }).id)
    updateCanvas(canvas, from: model)
    #expect((layer.contents as AnyObject?) === original)
    #expect(!layer.isHidden)
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isLoading, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!model.isLoading)
    #expect(model.loadError != nil)
    updateCanvas(canvas, from: model)
    #expect(layer.contents == nil)
    #expect(layer.isHidden)
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
    let canvas = ImageCanvas()
    canvas.model = model
    canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    updateCanvas(canvas, from: model)
    model.select(target.id)
    // No await: these pixels and their original dimensions must be published
    // before the asynchronous foreground request has any opportunity to run.
    #expect(model.current?.id == target.id)
    #expect(model.displayImage === preview.image)
    #expect(model.displayPixelSize == CGSize(width: 140, height: 40))
    #expect(model.isLoading)
    updateCanvas(canvas, from: model)
    let layer = try #require(canvas.layer?.sublayers?.first)
    #expect((layer.contents as AnyObject?) === preview.image)
    #expect(!layer.isHidden)
    #expect(abs(layer.frame.width / layer.frame.height - 3.5) < 0.001)
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

  @Test func canvasScrollNavigationRespectsTheSettingPanAndOptionZoom() async throws {
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
    let wheel = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)
    )
    let event = try #require(NSEvent(cgEvent: wheel))
    #expect(!event.hasPreciseScrollingDeltas)
    let initial = model.selectedID
    canvas.scrollWheel(with: event)
    #expect(model.selectedID == initial)
    model.preferences.scrollNavigation = .wheelOnly
    canvas.scrollWheel(with: event)
    #expect(model.current?.shortName == "image2.png")
    try await settled(model)
    let selected = model.selectedID
    model.setZoom(.actual)
    canvas.scrollWheel(with: event)
    #expect(model.selectedID == selected)
    model.setZoom(.fit)
    wheel.flags = .maskAlternate
    canvas.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
    #expect(model.selectedID == selected)
    #expect(model.zoomMode == .custom)
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
