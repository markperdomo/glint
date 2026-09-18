import Foundation

public struct ImageCollection: Sendable {
  public let location: URL
  public let assets: [ImageAsset]
  public let initialID: String?
  public let isArchive: Bool
}

public enum FolderScanner {
  // Call from a detached task. Resource values are requested in one directory pass.
  public static func open(_ urls: [URL], recursive: Bool = false) throws -> ImageCollection {
    guard let first = urls.first else {
      throw GlintError.unreadable("Choose an image, folder, or ZIP, RAR, or 7z archive.")
    }
    try Task.checkCancellation()
    if urls.count == 1, ImageFormats.isArchive(first) {
      let values = try first.resourceValues(forKeys: [.contentModificationDateKey])
      let entries = try ArchiveStore.shared.entries(at: first)
      let assets = entries.filter { ImageFormats.isImage(URL(fileURLWithPath: $0.name)) }
        .map {
          ImageAsset(
            url: first, archiveEntry: $0, byteCount: Int64($0.uncompressedSize),
            modified: values.contentModificationDate ?? .distantPast)
        }
      return ImageCollection(location: first, assets: assets, initialID: nil, isArchive: true)
    }
    let firstIsDirectory = try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    if urls.count == 1, !firstIsDirectory, !ImageFormats.isImage(first) {
      throw GlintError.unsupported(
        "“\(first.lastPathComponent)” is not a supported image, PDF, or ZIP, RAR, or 7z archive.")
    }
    let location = firstIsDirectory ? first : first.deletingLastPathComponent()
    let candidates: [URL]
    if urls.count > 1 {
      candidates = try urls.flatMap { url in
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
          ? files(in: url, recursive: recursive) : [url]
      }
    } else {
      candidates = try files(in: location, recursive: recursive)
    }
    var seen = Set<String>()
    var assets: [ImageAsset] = []
    for url in candidates {
      try Task.checkCancellation()
      guard ImageFormats.isImage(url), seen.insert(url.standardizedFileURL.path).inserted,
        let values = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        ]),
        values.isRegularFile == true
      else { continue }
      assets.append(
        ImageAsset(
          url: url, byteCount: Int64(values.fileSize ?? 0),
          modified: values.contentModificationDate ?? .distantPast))
    }
    return ImageCollection(
      location: location, assets: assets,
      initialID: firstIsDirectory ? nil : ImageAsset(url: first).id, isArchive: false)
  }

  private static func files(in directory: URL, recursive: Bool) throws -> [URL] {
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
      .contentModificationDateKey,
    ]
    if !recursive {
      return try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    }
    var enumerationError: (any Error)?
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
    else { throw GlintError.unreadable("This folder could not be read.") }
    var urls: [URL] = []
    for case let url as URL in enumerator {
      try Task.checkCancellation()
      if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
        enumerator.skipDescendants()
        continue
      }
      urls.append(url)
    }
    if let enumerationError { throw enumerationError }
    return urls
  }
}
