import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct MetadataRow: Identifiable, Hashable, Sendable {
  public var id: String { key }
  public let key: String
  public let value: String
}

public struct ImageMetadata: Sendable {
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let format: String
  public let frameCount: Int
  public let isAnimated: Bool
  public let hasAlpha: Bool
  public let colorSpace: String
  public let bitsPerComponent: Int
  public let rows: [MetadataRow]
  public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
}

// CGImage is immutable. Ownership can safely cross the decode actor boundary.
public struct DecodedImage: @unchecked Sendable {
  public let image: CGImage
  public let metadata: ImageMetadata
  public let frameDuration: Double
  public var byteCost: Int { image.bytesPerRow * image.height }
}

public enum ImageDecoder {
  public static let maximumFullResolutionPixels = 64_000_000

  public static func decode(_ asset: ImageAsset, frame: Int = 0, maximumDimension: Int = 4096)
    throws -> DecodedImage
  {
    try Task.checkCancellation()
    return try autoreleasepool {
      if asset.isPDF {
        return try decodePDF(asset, page: frame, maximumDimension: maximumDimension)
      }
      let source: CGImageSource?
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      if asset.archiveEntry != nil {
        source = CGImageSourceCreateWithData(try asset.data() as CFData, options)
      } else {
        source = CGImageSourceCreateWithURL(asset.url as CFURL, options)
      }
      guard let source else {
        throw GlintError.unreadable("“\(asset.shortName)” could not be opened by Image I/O.")
      }
      let count = CGImageSourceGetCount(source)
      guard frame >= 0, frame < count else {
        throw GlintError.unreadable("This image has no frame \(frame + 1).")
      }
      let properties =
        CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any] ?? [:]
      let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
      let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
      guard width > 0, height > 0 else {
        throw GlintError.unreadable("The image has invalid dimensions.")
      }
      if maximumDimension == 0, Double(width) * Double(height) > Double(maximumFullResolutionPixels)
      {
        throw GlintError.tooLarge(
          "Full-resolution operations are limited to 64 megapixels. You can still browse this image at reduced resolution."
        )
      }
      let limit = maximumDimension == 0 ? max(width, height) : max(1, maximumDimension)
      let decodeOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: limit,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceShouldAllowFloat: true,
      ]
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, frame, decodeOptions as CFDictionary)
      else {
        throw GlintError.unreadable(
          "“\(asset.shortName)” could not be decoded. It may be damaged or use an unsupported variant."
        )
      }
      try Task.checkCancellation()
      let type = CGImageSourceGetType(source) as String? ?? ""
      let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
      let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
      let webp = properties["{WebP}"] as? [String: Any]
      let animation = gif ?? png ?? webp ?? [:]
      let duration =
        (animation["UnclampedDelayTime"] as? NSNumber)?.doubleValue
        ?? (animation["DelayTime"] as? NSNumber)?.doubleValue ?? 0.1
      let orientation =
        (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
      let swapsAxes = (5...8).contains(orientation)
      let metadata = ImageMetadata(
        pixelWidth: swapsAxes ? height : width, pixelHeight: swapsAxes ? width : height,
        format: UTType(type)?.localizedDescription ?? asset.pathExtension.uppercased(),
        frameCount: count,
        isAnimated: count > 1
          && (gif != nil || (png?["DelayTime"] != nil) || (png?["UnclampedDelayTime"] != nil)
            || webp != nil),
        hasAlpha: (properties[kCGImagePropertyHasAlpha as String] as? Bool) ?? false,
        colorSpace: properties[kCGImagePropertyProfileName as String] as? String ?? image
          .colorSpace?.name as String? ?? "Unknown",
        bitsPerComponent: (properties[kCGImagePropertyDepth as String] as? NSNumber)?.intValue
          ?? image.bitsPerComponent,
        rows: flatten(properties))
      return DecodedImage(
        image: image, metadata: metadata, frameDuration: max(0.02, min(duration, 60)))
    }
  }

  private static func decodePDF(_ asset: ImageAsset, page: Int, maximumDimension: Int) throws
    -> DecodedImage
  {
    guard let provider = CGDataProvider(data: try asset.data() as CFData),
      let document = CGPDFDocument(provider)
    else {
      throw GlintError.unreadable("This PDF could not be opened.")
    }
    guard !document.isEncrypted || document.isUnlocked else {
      throw GlintError.unsupported("Password-protected PDFs are not supported yet.")
    }
    guard let pdfPage = document.page(at: page + 1) else {
      throw GlintError.unreadable("This PDF page does not exist.")
    }
    let box = pdfPage.getBoxRect(.cropBox)
    let rotated = abs(pdfPage.rotationAngle) % 180 != 0
    let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
    guard size.width > 0, size.height > 0 else {
      throw GlintError.unreadable("This PDF has an empty page.")
    }
    let scale =
      CGFloat(maximumDimension == 0 ? 4096 : max(1, maximumDimension))
      / max(size.width, size.height)
    let width = max(1, Int(ceil(size.width * scale)))
    let height = max(1, Int(ceil(size.height * scale)))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
      throw GlintError.unreadable("Could not allocate a PDF page.")
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(rect)
    context.concatenate(
      pdfPage.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(pdfPage)
    guard let image = context.makeImage() else {
      throw GlintError.unreadable("The PDF page could not be rendered.")
    }
    let metadata = ImageMetadata(
      pixelWidth: Int(size.width * 2), pixelHeight: Int(size.height * 2), format: "PDF document",
      frameCount: document.numberOfPages, isAnimated: false, hasAlpha: false,
      colorSpace: "sRGB", bitsPerComponent: 8,
      rows: [MetadataRow(key: "Page size", value: "\(Int(size.width)) × \(Int(size.height)) pt")])
    return DecodedImage(image: image, metadata: metadata, frameDuration: 0.1)
  }

  private static func flatten(_ dictionary: [String: Any], prefix: String = "") -> [MetadataRow] {
    dictionary.keys.sorted().flatMap { key -> [MetadataRow] in
      let clean = key.replacingOccurrences(of: "{", with: "").replacingOccurrences(
        of: "}", with: "")
      let title = prefix.isEmpty ? clean : "\(prefix) · \(clean)"
      if let nested = dictionary[key] as? [String: Any] { return flatten(nested, prefix: title) }
      guard let value = dictionary[key], !(value is Data) else { return [] }
      let string = String(describing: value)
      guard string.count < 1000 else { return [] }
      return [MetadataRow(key: title, value: string)]
    }
  }
}
