import CZlib
import Foundation

public struct ZIPEntry: Hashable, Sendable {
  public let name: String
  public let compressedSize: Int
  public let uncompressedSize: Int
  public let localOffset: Int
  let method: UInt16
  let checksum: UInt32
}

/// Reads ZIP/CBZ members in memory; never extracts paths to the filesystem.
/// Intentionally rejects encryption, split archives, ZIP64, and oversized members.
public enum ZIPArchive {
  public static let maximumMemberBytes = 256 * 1_024 * 1_024

  public static func entries(at url: URL) throws -> [ZIPEntry] {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count >= 22 else { throw GlintError.archive("This is not a valid ZIP archive.") }
    let lower = max(0, data.count - 65_557)
    guard
      let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
        data.u32($0) == 0x0605_4b50 && $0 + 22 + Int(data.u16($0 + 20)) == data.count
      })
    else { throw GlintError.archive("The ZIP directory is missing or damaged.") }
    guard data.u16(end + 4) == 0, data.u16(end + 6) == 0,
      data.u16(end + 8) == data.u16(end + 10)
    else {
      throw GlintError.unsupported("Split ZIP archives are not supported yet.")
    }
    let count = Int(data.u16(end + 10))
    let size = Int(data.u32(end + 12))
    let start = Int(data.u32(end + 16))
    guard count != 0xffff, start != Int(UInt32.max), size != Int(UInt32.max) else {
      throw GlintError.unsupported("ZIP64 archives are not supported yet.")
    }
    guard start <= end, size <= end - start else {
      throw GlintError.archive("The ZIP directory has invalid bounds.")
    }
    var offset = start
    var result: [ZIPEntry] = []
    for _ in 0..<count {
      try Task.checkCancellation()
      guard offset + 46 <= start + size, data.u32(offset) == 0x0201_4b50 else {
        throw GlintError.archive("The ZIP directory is damaged.")
      }
      let flags = data.u16(offset + 8)
      let nameLength = Int(data.u16(offset + 28))
      let next = offset + 46 + nameLength + Int(data.u16(offset + 30)) + Int(data.u16(offset + 32))
      guard next <= start + size else {
        throw GlintError.archive("A ZIP member has invalid bounds.")
      }
      let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
      let name =
        String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1)
        ?? ""
      let compressed = Int(data.u32(offset + 20))
      let uncompressed = Int(data.u32(offset + 24))
      let local = Int(data.u32(offset + 42))
      if !name.isEmpty && !name.hasSuffix("/") && !name.hasPrefix("__MACOSX/")
        && !(name as NSString).lastPathComponent.hasPrefix(".")
      {
        guard flags & 1 == 0 else {
          throw GlintError.unsupported("Password-protected ZIP archives are not supported yet.")
        }
        guard compressed != Int(UInt32.max), uncompressed != Int(UInt32.max),
          local != Int(UInt32.max)
        else {
          throw GlintError.unsupported("ZIP64 members are not supported yet.")
        }
        result.append(
          ZIPEntry(
            name: name, compressedSize: compressed, uncompressedSize: uncompressed,
            localOffset: local, method: data.u16(offset + 10), checksum: data.u32(offset + 16)))
      }
      offset = next
    }
    return result
  }

  public static func read(_ entry: ZIPEntry, from url: URL) throws -> Data {
    try Task.checkCancellation()
    guard entry.uncompressedSize <= maximumMemberBytes, entry.compressedSize <= maximumMemberBytes
    else {
      throw GlintError.tooLarge("This archive member exceeds the 256 MB decode limit.")
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let local = entry.localOffset
    guard local >= 0, local + 30 <= data.count, data.u32(local) == 0x0403_4b50 else {
      throw GlintError.archive("The ZIP member header is damaged.")
    }
    let start = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28))
    guard start <= data.count, entry.compressedSize <= data.count - start else {
      throw GlintError.archive("The ZIP member is truncated.")
    }
    let compressed = data.subdata(in: start..<(start + entry.compressedSize))
    let output: Data
    switch entry.method {
    case 0:
      guard compressed.count == entry.uncompressedSize else {
        throw GlintError.archive("The ZIP member size does not match.")
      }
      output = compressed
    case 8:
      var buffer = Data(count: max(entry.uncompressedSize, 1))
      var stream = z_stream()
      guard
        inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
      else {
        throw GlintError.archive("ZIP decompression could not start.")
      }
      defer { inflateEnd(&stream) }
      let status: Int32 = compressed.withUnsafeBytes { input in
        buffer.withUnsafeMutableBytes { destination in
          stream.next_in = UnsafeMutablePointer(
            mutating: input.bindMemory(to: Bytef.self).baseAddress)
          stream.avail_in = uInt(compressed.count)
          stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(destination.count)
          return inflate(&stream, Z_FINISH)
        }
      }
      guard status == Z_STREAM_END, stream.total_out == entry.uncompressedSize,
        stream.total_in == entry.compressedSize
      else {
        throw GlintError.archive("The compressed ZIP member is damaged.")
      }
      output = buffer.prefix(entry.uncompressedSize)
    default:
      throw GlintError.unsupported(
        "This ZIP compression method is not supported. Use stored or Deflate ZIP/CBZ files.")
    }
    try Task.checkCancellation()
    let checksum = output.withUnsafeBytes {
      crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
    }
    guard UInt32(checksum) == entry.checksum else {
      throw GlintError.archive("The ZIP member failed its integrity check.")
    }
    return output
  }
}

extension Data {
  fileprivate func u16(_ offset: Int) -> UInt16 {
    UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
  }
  fileprivate func u32(_ offset: Int) -> UInt32 {
    UInt32(u16(offset)) | (UInt32(u16(offset + 2)) << 16)
  }
}
