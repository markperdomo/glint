import CLibArchive
import CUnrar
import Foundation

struct ArchiveHeader {
  let name: String
  let size: Int64
  let regular: Bool
}

/// Confined to one archive session's worker. Neither implementation extracts paths.
protocol ArchiveReader: AnyObject {
  var cachesPrecedingImages: Bool { get }
  func next() throws -> ArchiveHeader?
  func read(size: Int64) throws -> Data
  func skip() throws
}

final class SevenZipReader: ArchiveReader {
  // libarchive does not expose solid-block membership. Retain intervening images
  // while advancing its stream so reverse navigation never replays that work.
  let cachesPrecedingImages = true
  private let handle: OpaquePointer

  init(url: URL) throws {
    guard let handle = archive_read_new() else { throw GlintError.archive("Cannot open archive.") }
    self.handle = handle
    archive_read_support_format_7zip(handle)
    let status = url.withUnsafeFileSystemRepresentation {
      archive_read_open_filename(handle, $0, 128 * 1024)
    }
    if status != ARCHIVE_OK {
      let error = failure()
      archive_read_free(handle)
      throw error
    }
  }

  deinit { archive_read_free(handle) }

  private func failure() -> GlintError {
    let detail = archive_error_string(handle).map { String(cString: $0) } ?? "Invalid archive."
    return .archive("Could not read 7z archive: \(detail)")
  }

  func next() throws -> ArchiveHeader? {
    try Task.checkCancellation()
    var entry: OpaquePointer?
    let status = archive_read_next_header(handle, &entry)
    if status == ARCHIVE_EOF { return nil }
    guard status == ARCHIVE_OK, let entry else { throw failure() }
    guard archive_entry_is_encrypted(entry) == 0 else {
      throw GlintError.unsupported("Encrypted archives are not supported.")
    }
    guard let path = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else {
      throw GlintError.archive("An archive filename could not be read.")
    }
    return ArchiveHeader(
      name: String(cString: path), size: archive_entry_size(entry),
      regular: archive_entry_filetype(entry) == UInt16(S_IFREG)
        && archive_entry_symlink(entry) == nil && archive_entry_hardlink(entry) == nil)
  }

  func read(size: Int64) throws -> Data {
    try ArchiveSession.checkSize(size)
    var output = Data()
    output.reserveCapacity(Int(size))
    var buffer = [UInt8](repeating: 0, count: 128 * 1024)
    while true {
      try Task.checkCancellation()
      let count = archive_read_data(handle, &buffer, buffer.count)
      guard count >= 0 else { throw failure() }
      if count == 0 { break }
      guard count <= Int(size) - output.count else {
        throw GlintError.archive("An archive member exceeds its declared size.")
      }
      output.append(contentsOf: buffer.prefix(count))
    }
    guard output.count == Int(size) else { throw GlintError.archive("Truncated archive member.") }
    return output
  }

  func skip() throws {
    try Task.checkCancellation()
    guard archive_read_data_skip(handle) == ARCHIVE_OK else { throw failure() }
  }
}

final class RARReader: ArchiveReader {
  var cachesPrecedingImages: Bool { glint_rar_is_solid(handle) != 0 }
  private let handle: OpaquePointer

  init(url: URL, listing: Bool = false) throws {
    var error: Int32 = 0
    let handle = url.withUnsafeFileSystemRepresentation {
      glint_rar_open($0, listing ? 1 : 0, &error)
    }
    guard let handle else { throw Self.failure(error) }
    self.handle = handle
  }

  deinit { glint_rar_close(handle) }

  private static func failure(_ status: Int32) -> GlintError {
    switch status {
    case 22, 24: .unsupported("Encrypted archives are not supported.")
    case 14: .unsupported("This RAR variant or split archive is not supported.")
    case 25: .tooLarge("This RAR archive requires an oversized decompression dictionary.")
    default:
      .archive("Could not read RAR archive (error \(status)). It may be damaged or incomplete.")
    }
  }

  func next() throws -> ArchiveHeader? {
    try Task.checkCancellation()
    var header = GlintRARHeader()
    let status = glint_rar_next(handle, &header)
    if status == 10 { return nil }
    guard status == 0 else { throw Self.failure(status) }
    guard header.flags & 4 == 0 else {
      throw GlintError.unsupported("Encrypted archives are not supported.")
    }
    guard header.flags & 3 == 0 else {
      throw GlintError.unsupported("Split archives are not supported.")
    }
    guard header.size <= UInt64(Int64.max), header.dictionaryKB <= 256 * 1024 else {
      throw GlintError.tooLarge("This RAR member or decompression dictionary is too large.")
    }
    let name = withUnsafeBytes(of: header.name) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    return ArchiveHeader(name: name, size: Int64(header.size), regular: header.regular != 0)
  }

  private final class Output {
    var data = Data()
    var error: (any Error)?
    let size: Int
    init(size: Int) {
      self.size = size
      data.reserveCapacity(size)
    }
  }

  func read(size: Int64) throws -> Data {
    try ArchiveSession.checkSize(size)
    let output = Output(size: Int(size))
    let status = glint_rar_process(
      handle, 0,
      { bytes, count, context in
        let output = Unmanaged<Output>.fromOpaque(context!).takeUnretainedValue()
        do {
          try Task.checkCancellation()
          guard count <= output.size - output.data.count else {
            throw GlintError.archive("An archive member exceeds its declared size.")
          }
          if let bytes {
            output.data.append(bytes.assumingMemoryBound(to: UInt8.self), count: count)
          }
          return 0
        } catch {
          output.error = error
          return -1
        }
      }, Unmanaged.passUnretained(output).toOpaque())
    if let error = output.error { throw error }
    guard status == 0 else { throw Self.failure(status) }
    guard output.data.count == Int(size) else {
      throw GlintError.archive("Truncated archive member.")
    }
    return output.data
  }

  func skip() throws {
    try Task.checkCancellation()
    let status = glint_rar_process(handle, 1, nil, nil)
    guard status == 0 else { throw Self.failure(status) }
  }
}
