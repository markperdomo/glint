import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Glint

@Suite(.serialized) @MainActor
struct ViewerModelTests {
  private func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GlintModelTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 1...12 {
      let url = folder.appendingPathComponent("image\(index).png")
      let context = try #require(
        CGContext(
          data: nil, width: index * 20, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(gray: CGFloat(index) / 12, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: index * 20, height: 40))
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
