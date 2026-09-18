import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageAsset: Identifiable, Hashable, Sendable {
  public let url: URL
  public let archiveEntry: ZIPEntry?
  public let byteCount: Int64
  public let modified: Date

  public init(
    url: URL, archiveEntry: ZIPEntry? = nil, byteCount: Int64 = 0, modified: Date = .distantPast
  ) {
    self.url = url.standardizedFileURL
    self.archiveEntry = archiveEntry
    self.byteCount = byteCount
    self.modified = modified
  }

  public var id: String { url.path + (archiveEntry.map { "::\($0.localOffset):\($0.name)" } ?? "") }
  public var name: String { archiveEntry?.name ?? url.lastPathComponent }
  public var shortName: String { (name as NSString).lastPathComponent }
  public var pathExtension: String { (name as NSString).pathExtension.lowercased() }
  public var isPDF: Bool { pathExtension == "pdf" }
  public var isFile: Bool { archiveEntry == nil }

  public func data() throws -> Data {
    if let archiveEntry { return try ZIPArchive.read(archiveEntry, from: url) }
    return try Data(contentsOf: url, options: .mappedIfSafe)
  }
}

public enum ImageFormats {
  public static let archiveExtensions: Set<String> = ["zip", "cbz"]
  public static let supportedTypes: [UTType] = (CGImageSourceCopyTypeIdentifiers() as! [String])
    .compactMap(UTType.init)
  public static let extensions: Set<String> = Set(
    supportedTypes.flatMap { $0.tags[.filenameExtension] ?? [] }
  ).union(["pdf"])
  public static func isImage(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if extensions.contains(ext) { return true }
    guard let type = UTType(filenameExtension: ext) else { return false }
    return supportedTypes.contains { type.conforms(to: $0) }
  }
  public static func isArchive(_ url: URL) -> Bool {
    archiveExtensions.contains(url.pathExtension.lowercased())
  }
}

public enum ImageSortOrder: String, CaseIterable, Sendable, Identifiable {
  case name, modified, size, kind
  public var id: Self { self }
  public var title: String {
    switch self {
    case .name: "Name"
    case .modified: "Date modified"
    case .size: "File size"
    case .kind: "Kind"
    }
  }

  public func sorted(_ assets: [ImageAsset], reversed: Bool = false) -> [ImageAsset] {
    assets.sorted { a, b in
      let comparison: ComparisonResult
      switch self {
      case .modified where a.modified != b.modified:
        comparison = a.modified < b.modified ? .orderedAscending : .orderedDescending
      case .size where a.byteCount != b.byteCount:
        comparison = a.byteCount < b.byteCount ? .orderedAscending : .orderedDescending
      case .kind where a.pathExtension != b.pathExtension:
        comparison = a.pathExtension.localizedStandardCompare(b.pathExtension)
      default:
        let names = a.name.localizedStandardCompare(b.name)
        comparison = names == .orderedSame ? a.id.compare(b.id) : names
      }
      return reversed ? comparison == .orderedDescending : comparison == .orderedAscending
    }
  }
}

public enum Navigation {
  public static func index(from current: Int, offset: Int, count: Int, wraps: Bool) -> Int? {
    guard count > 0 else { return nil }
    let base = min(max(current, 0), count - 1)
    if wraps { return ((base + offset % count) % count + count) % count }
    return min(max(base + offset, 0), count - 1)
  }
}

public enum GlintError: LocalizedError, Sendable {
  case unreadable(String)
  case unsupported(String)
  case archive(String)
  case tooLarge(String)
  public var errorDescription: String? {
    switch self {
    case .unreadable(let message), .unsupported(let message), .archive(let message),
      .tooLarge(let message):
      message
    }
  }
}
