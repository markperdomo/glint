import CoreGraphics
import Foundation

public enum ZoomMode: String, CaseIterable, Sendable {
  case fit, actual, fill, custom
}

public struct Viewport: Sendable {
  public var viewport: CGSize
  public var pixels: CGSize
  public var backingScale: CGFloat
  public var mode: ZoomMode
  public var customScale: CGFloat
  public var enlargesSmallImages: Bool

  public init(
    viewport: CGSize, pixels: CGSize, backingScale: CGFloat = 2, mode: ZoomMode = .fit,
    customScale: CGFloat = 1, enlargesSmallImages: Bool = true
  ) {
    self.viewport = viewport
    self.pixels = pixels
    self.backingScale = backingScale
    self.mode = mode
    self.customScale = customScale
    self.enlargesSmallImages = enlargesSmallImages
  }

  /// Display pixels per source pixel. 100% is truly one-to-one on Retina.
  public var scale: CGFloat {
    guard pixels.width > 0, pixels.height > 0, viewport.width > 0, viewport.height > 0,
      backingScale > 0
    else { return 1 }
    let x = viewport.width * backingScale / pixels.width
    let y = viewport.height * backingScale / pixels.height
    switch mode {
    case .actual: return 1
    case .custom: return min(32, max(0.01, customScale))
    case .fit: return enlargesSmallImages ? min(x, y) : min(1, x, y)
    case .fill: return max(x, y)
    }
  }

  public var displaySize: CGSize {
    CGSize(
      width: pixels.width * scale / max(backingScale, 1),
      height: pixels.height * scale / max(backingScale, 1))
  }
  public var canPanHorizontally: Bool { displaySize.width > viewport.width + 0.5 }
  public var canPanVertically: Bool { displaySize.height > viewport.height + 0.5 }
  public func clampedPan(_ pan: CGPoint) -> CGPoint {
    let x = max(0, (displaySize.width - viewport.width) / 2)
    let y = max(0, (displaySize.height - viewport.height) / 2)
    return CGPoint(x: min(x, max(-x, pan.x)), y: min(y, max(-y, pan.y)))
  }
}
