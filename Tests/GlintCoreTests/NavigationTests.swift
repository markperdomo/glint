import Foundation
import Testing

@testable import GlintCore

@Test func navigationWrapsAndClamps() {
  #expect(Navigation.index(from: 0, offset: -1, count: 4, wraps: true) == 3)
  #expect(Navigation.index(from: 3, offset: 1, count: 4, wraps: true) == 0)
  #expect(Navigation.index(from: 1, offset: 100, count: 4, wraps: true) == 1)
  #expect(Navigation.index(from: 0, offset: -100, count: 4, wraps: false) == 0)
  #expect(Navigation.index(from: 0, offset: 100, count: 4, wraps: false) == 3)
  #expect(Navigation.index(from: 0, offset: 1, count: 0, wraps: true) == nil)
}

@Test func filenamesSortNaturallyAndStably() {
  let files = ["image10.jpg", "image2.jpg", "image1.jpg"].map {
    ImageAsset(url: URL(fileURLWithPath: "/test/\($0)"))
  }
  #expect(
    ImageSortOrder.name.sorted(files).map(\.name) == ["image1.jpg", "image2.jpg", "image10.jpg"])
  #expect(
    ImageSortOrder.name.sorted(files, reversed: true).map(\.name) == [
      "image10.jpg", "image2.jpg", "image1.jpg",
    ])
}

@Test func actualPixelsRespectRetinaBackingScale() {
  let viewport = Viewport(
    viewport: CGSize(width: 1000, height: 800), pixels: CGSize(width: 1600, height: 1200),
    mode: .actual)
  #expect(viewport.scale == 1)
  #expect(viewport.displaySize == CGSize(width: 800, height: 600))
  #expect(!viewport.canPanHorizontally)
}

@Test func fitMustNeverOverflowOrAccidentallyEnablePanning() {
  let viewport = Viewport(
    viewport: CGSize(width: 1000, height: 800), pixels: CGSize(width: 6000, height: 4000))
  #expect(abs(viewport.displaySize.width - 1000) < 0.01)
  #expect(!viewport.canPanHorizontally)
  #expect(!viewport.canPanVertically)
  #expect(viewport.clampedPan(CGPoint(x: 100, y: 100)) == .zero)
}

@Test func smallImagesDoNotEnlargeUnlessRequested() {
  var viewport = Viewport(
    viewport: CGSize(width: 1000, height: 800), pixels: CGSize(width: 200, height: 100))
  #expect(viewport.scale == 1)
  viewport.enlargesSmallImages = true
  #expect(viewport.scale == 10)
}
