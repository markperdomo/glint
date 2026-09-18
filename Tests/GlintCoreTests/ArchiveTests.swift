import Foundation
import Testing

@testable import GlintCore

private func archiveFixture(_ name: String) throws -> URL {
  try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}

@Test(arguments: [
  "solid.rar", "independent.rar", "solid.7z", "independent.7z", "classic-solid.rar",
])
func archiveReadersBrowseImagesAndReuseExtractedMembers(name: String) throws {
  let store = ArchiveStore()
  defer { store.removeAll() }
  let url = try archiveFixture(name)
  let entries = try store.entries(at: url)
  #expect(entries.count == 4)
  #expect(entries.contains { $0.name == "café.png" })
  let last = try #require(entries.last)
  let data = try store.read(last, from: url)
  #expect(data.starts(with: [137, 80, 78, 71]))
  #expect(store.statistics.extractions == (name == "independent.rar" ? 1 : 4))
  for entry in entries.reversed() {
    #expect(try store.read(entry, from: url).count == entry.uncompressedSize)
  }
  #expect(store.statistics.extractions == 4)
  #expect(store.statistics.cacheHits >= 1)
  let collection = try FolderScanner.open([url])
  let asset = try #require(collection.assets.first)
  #expect(try ImageDecoder.decode(asset, maximumDimension: 60).image.width == 60)
  #expect(try ImageDecoder.decode(asset, maximumDimension: 120).image.width == 120)
}

@Test(arguments: ["solid.rar", "solid.7z"])
func concurrentArchiveReadsShareExtraction(name: String) async throws {
  let store = ArchiveStore()
  defer { store.removeAll() }
  let url = try archiveFixture(name)
  let entry = try #require(store.entries(at: url).last)
  try await withThrowingTaskGroup(of: Data.self) { group in
    for _ in 0..<8 { group.addTask { try store.read(entry, from: url) } }
    for try await data in group { #expect(data.count == entry.uncompressedSize) }
  }
  #expect(store.statistics.extractions == 4)
}

@Test(arguments: ["encrypted.rar", "encrypted.7z"])
func archivesRejectEncryptionWithoutPrompting(name: String) throws {
  let store = ArchiveStore()
  defer { store.removeAll() }
  #expect(throws: (any Error).self) { try store.entries(at: archiveFixture(name)) }
}

@Test func archiveCacheHonorsBudgetsAndCleansUp() throws {
  let store = ArchiveStore()
  defer { store.removeAll() }
  let entries = try store.entries(at: archiveFixture("solid.7z"))
  let cache = ArchiveMemberCache(memoryLimit: 4, diskLimit: 8)
  let bytes = Data([1, 2, 3, 4])
  for entry in entries.prefix(3) { try cache.insert(bytes, for: entry) }
  #expect(cache.statistics.memoryBytes <= 4)
  #expect(cache.statistics.diskBytes <= 8)
  #expect(cache.value(for: entries[0]) == nil)
  // The previous member was evicted from RAM, but remains readable from disk.
  #expect(cache.value(for: entries[1]) == bytes)
  cache.removeAll()
  #expect(cache.statistics.diskBytes == 0)
  #expect(cache.value(for: entries[1]) == nil)
}

@Test func archiveReplacementInvalidatesPreviouslyCachedBytes() throws {
  let directory = try FixtureDirectory()
  defer { directory.remove() }
  let url = directory.url.appendingPathComponent("images.7z")
  try FileManager.default.copyItem(at: archiveFixture("solid.7z"), to: url)
  let store = ArchiveStore()
  defer { store.removeAll() }
  let old = try #require(store.entries(at: url).first)
  _ = try store.read(old, from: url)
  try Data(contentsOf: archiveFixture("independent.7z")).write(to: url, options: .atomic)
  #expect(throws: (any Error).self) { try store.read(old, from: url) }
  let new = try #require(store.entries(at: url).first)
  #expect(new != old)
  #expect(try store.read(new, from: url).starts(with: [137, 80, 78, 71]))
}

@Test func cancelledArchiveRequestDoesNotExtract() async throws {
  let store = ArchiveStore()
  defer { store.removeAll() }
  let url = try archiveFixture("solid.7z")
  let entry = try #require(store.entries(at: url).last)
  let task = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    return try store.read(entry, from: url)
  }
  do {
    _ = try await task.value
    Issue.record("Cancelled archive request unexpectedly succeeded")
  } catch is CancellationError {}
  #expect(store.statistics.extractions == 0)
}
