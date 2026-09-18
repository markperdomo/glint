import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageEdits: Equatable, Sendable {
  public var quarterTurns = 0
  public var flipHorizontal = false
  public var flipVertical = false
  /// Normalized rectangle, in the rotated/flipped image's bottom-left coordinate system.
  public var crop: CGRect?
  public init() {}
  public var isIdentity: Bool {
    quarterTurns % 4 == 0 && !flipHorizontal && !flipVertical && crop == nil
  }
  public func size(for original: CGSize) -> CGSize {
    let rotated =
      quarterTurns % 2 == 0 ? original : CGSize(width: original.height, height: original.width)
    guard let crop else { return rotated }
    return CGSize(width: rotated.width * crop.width, height: rotated.height * crop.height)
  }
}

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
  case png, jpeg, heic, tiff
  public var id: Self { self }
  public var title: String { rawValue.uppercased() }
  public var type: UTType {
    switch self {
    case .png: .png
    case .jpeg: .jpeg
    case .heic: .heic
    case .tiff: .tiff
    }
  }
  public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

public enum ImageEditing {
  // Core Image uses the system's GPU renderer and retains reusable compilation caches.
  private static let context = CIContext(options: [.cacheIntermediates: false])

  public static func render(_ image: CGImage, edits: ImageEdits) throws -> CGImage {
    if edits.isIdentity { return image }
    var result = CIImage(cgImage: image)
    let orientation: CGImagePropertyOrientation =
      switch (edits.quarterTurns % 4 + 4) % 4 {
      case 1: .right
      case 2: .down
      case 3: .left
      default: .up
      }
    result = result.oriented(orientation)
    result = result.transformed(
      by: CGAffineTransform(scaleX: edits.flipHorizontal ? -1 : 1, y: edits.flipVertical ? -1 : 1))
    result = result.transformed(
      by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
    if let crop = edits.crop {
      let unit = crop.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
      guard !unit.isNull, unit.width > 0, unit.height > 0 else {
        throw GlintError.unreadable("The crop selection is empty.")
      }
      let rect = CGRect(
        x: unit.minX * result.extent.width, y: unit.minY * result.extent.height,
        width: unit.width * result.extent.width, height: unit.height * result.extent.height
      ).integral
        .intersection(result.extent)
      result = result.cropped(to: rect)
    }
    let outputSpace =
      image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let output = context.createCGImage(
        result, from: result.extent, format: .RGBA8, colorSpace: outputSpace)
    else {
      throw GlintError.unreadable("This image could not be transformed.")
    }
    return output
  }

  public static func export(
    _ asset: ImageAsset, frame: Int, edits: ImageEdits, to url: URL,
    format: ExportFormat, quality: Double = 0.92
  ) throws {
    let decoded = try ImageDecoder.decode(asset, frame: frame, maximumDimension: 0)
    let image = try render(decoded.image, edits: edits)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, format.type.identifier as CFString, 1, nil)
    else {
      throw GlintError.unsupported("\(format.title) export is unavailable on this Mac.")
    }
    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality,
      kCGImagePropertyOrientation: 1,
    ]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw GlintError.unreadable("The exported image could not be encoded.")
    }
    try Task.checkCancellation()
    try (data as Data).write(to: url, options: .atomic)
  }
}
