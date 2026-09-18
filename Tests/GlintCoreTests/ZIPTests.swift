import CZlib
import Foundation
import Testing

@testable import GlintCore

extension Data {
  fileprivate mutating func append16(_ value: UInt16) {
    append(UInt8(value & 255))
    append(UInt8(value >> 8))
  }
  fileprivate mutating func append32(_ value: UInt32) {
    append16(UInt16(value & 0xffff))
    append16(UInt16(value >> 16))
  }
}

private func makeZIP(name: String, payload: Data, deflated: Bool = false, corruptCRC: Bool = false)
  throws -> Data
{
  let filename = Data(name.utf8)
  let crc =
    payload.withUnsafeBytes {
      UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)))
    } ^ (corruptCRC ? 1 : 0)
  var compressed = payload
  if deflated {
    var stream = z_stream()
    #expect(
      deflateInit2_(
        &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)) == Z_OK)
    defer { deflateEnd(&stream) }
    var output = Data(count: payload.count + 1024)
    let result = payload.withUnsafeBytes { input in
      output.withUnsafeMutableBytes { bytes in
        stream.next_in = UnsafeMutablePointer(
          mutating: input.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(input.count)
        stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
        stream.avail_out = uInt(bytes.count)
        return deflate(&stream, Z_FINISH)
      }
    }
    #expect(result == Z_STREAM_END)
    compressed = output.prefix(Int(stream.total_out))
  }
  let method: UInt16 = deflated ? 8 : 0
  var zip = Data()
  zip.append32(0x0403_4b50)
  zip.append16(20)
  zip.append16(0)
  zip.append16(method)
  zip.append32(0)
  zip.append32(crc)
  zip.append32(UInt32(compressed.count))
  zip.append32(UInt32(payload.count))
  zip.append16(UInt16(filename.count))
  zip.append16(0)
  zip.append(filename)
  zip.append(compressed)
  let offset = zip.count
  zip.append32(0x0201_4b50)
  zip.append16(20)
  zip.append16(20)
  zip.append16(0)
  zip.append16(method)
  zip.append32(0)
  zip.append32(crc)
  zip.append32(UInt32(compressed.count))
  zip.append32(UInt32(payload.count))
  zip.append16(UInt16(filename.count))
  zip.append16(0)
  zip.append16(0)
  zip.append16(0)
  zip.append16(0)
  zip.append32(0)
  zip.append32(0)
  zip.append(filename)
  let size = zip.count - offset
  zip.append32(0x0605_4b50)
  zip.append16(0)
  zip.append16(0)
  zip.append16(1)
  zip.append16(1)
  zip.append32(UInt32(size))
  zip.append32(UInt32(offset))
  zip.append16(0)
  return zip
}

@Test(arguments: [false, true]) func zipReadsStoredAndDeflatedMembers(deflated: Bool) throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let png = try directory.image("original.png")
  let payload = try Data(contentsOf: png)
  let url = directory.url.appendingPathComponent("comic.cbz")
  try makeZIP(name: "chapters/page01.png", payload: payload, deflated: deflated).write(to: url)
  let entries = try ZIPArchive.entries(at: url)
  #expect(entries.count == 1)
  #expect(try ZIPArchive.read(entries[0], from: url) == payload)
  let collection = try FolderScanner.open([url])
  #expect(collection.isArchive)
  let image = try ImageDecoder.decode(try #require(collection.assets.first))
  #expect(image.metadata.pixelWidth == 120)
}

@Test func zipNeverExtractsTraversalNames() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("traversal.zip")
  let payload = Data("test".utf8)
  try makeZIP(name: "../../escape.png", payload: payload).write(to: url)
  let entry = try #require(ZIPArchive.entries(at: url).first)
  #expect(try ZIPArchive.read(entry, from: url) == payload)
  #expect(
    !FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("escape.png").path)
  )
}

@Test func zipRejectsCorruptionAndTruncation() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("bad.zip")
  let zip = try makeZIP(name: "x.png", payload: Data([1, 2, 3]), corruptCRC: true)
  try zip.write(to: url)
  let entry = try #require(ZIPArchive.entries(at: url).first)
  #expect(throws: (any Error).self) { try ZIPArchive.read(entry, from: url) }
  for length in [0, 1, 21, 22, zip.count - 1] {
    try zip.prefix(length).write(to: url)
    #expect(throws: (any Error).self) { try ZIPArchive.entries(at: url) }
  }
}

@Test func zipRejectsOversizedMembersBeforeAllocation() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("limit.zip")
  try makeZIP(name: "x.png", payload: Data([1, 2, 3])).write(to: url)
  let oversized = ZIPEntry(
    name: "x.png", compressedSize: 3, uncompressedSize: ZIPArchive.maximumMemberBytes + 1,
    localOffset: 0, method: 0, checksum: 0)
  #expect(throws: (any Error).self) { try ZIPArchive.read(oversized, from: url) }
}
