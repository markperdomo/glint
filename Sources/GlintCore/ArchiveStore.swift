import Foundation

struct ArchiveIdentity: Hashable, Sendable {
  let url: URL
  let size: Int64
  let inode: UInt64
  let modified: timespec
  let changed: timespec

  init(url: URL) throws {
    self.url = url.standardizedFileURL
    var info = stat()
    guard url.withUnsafeFileSystemRepresentation({ fstatat(AT_FDCWD, $0!, &info, 0) }) == 0 else {
      throw GlintError.archive("The archive could not be opened.")
    }
    size = info.st_size
    inode = info.st_ino
    modified = info.st_mtimespec
    changed = info.st_ctimespec
  }

  static func == (a: Self, b: Self) -> Bool {
    a.url == b.url && a.size == b.size && a.inode == b.inode
      && a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec
      && a.changed.tv_sec == b.changed.tv_sec && a.changed.tv_nsec == b.changed.tv_nsec
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(url)
    hasher.combine(size)
    hasher.combine(inode)
    hasher.combine(modified.tv_sec)
    hasher.combine(modified.tv_nsec)
    hasher.combine(changed.tv_sec)
    hasher.combine(changed.tv_nsec)
  }
}

public struct ArchiveEntry: Hashable, Sendable {
  public let name: String
  public let uncompressedSize: Int64
  let index: Int
  let identity: ArchiveIdentity
  let zip: ZIPEntry?
}

public struct ArchiveStatistics: Sendable {
  public let extractions: Int
  public let cacheHits: Int
  public let memoryBytes: Int
  public let diskBytes: Int
}

/// Shared across thumbnails, viewer renditions, animation, and export. Asset
/// values never retain sessions, so decoded-image caches cannot pin decompressors.
public final class ArchiveStore: @unchecked Sendable {
  public static let shared = ArchiveStore()
  private let lock = NSLock()
  private var sessions: [ArchiveIdentity: ArchiveSession] = [:]
  private var recent: [ArchiveIdentity] = []
  private let cache = ArchiveMemberCache()

  public init() {}

  public func entries(at url: URL) throws -> [ArchiveEntry] {
    try session(for: ArchiveIdentity(url: url)).entries
  }

  private func session(for identity: ArchiveIdentity) throws -> ArchiveSession {
    lock.lock()
    if let session = sessions[identity] {
      recent.removeAll { $0 == identity }
      recent.append(identity)
      lock.unlock()
      return session
    }
    lock.unlock()
    let new = try ArchiveSession(identity: identity, cache: cache)
    lock.lock()
    defer { lock.unlock() }
    if let existing = sessions[identity] { return existing }
    sessions[identity] = new
    recent.append(identity)
    // Only two idle archive cursors are retained. Active calls own their session
    // until completion; member data has a separate global budget.
    while recent.count > 2 { sessions.removeValue(forKey: recent.removeFirst()) }
    return new
  }

  public func read(_ entry: ArchiveEntry, from url: URL) throws -> Data {
    try Task.checkCancellation()
    guard try ArchiveIdentity(url: url) == entry.identity else {
      throw GlintError.archive("The archive changed. Refresh it to continue browsing.")
    }
    try ArchiveSession.checkSize(entry.uncompressedSize)
    if let data = cache.value(for: entry) { return data }
    return try session(for: entry.identity).read(entry)
  }

  /// Use on application termination or in benchmarks with no active readers.
  public func removeAll() {
    lock.lock()
    sessions.removeAll()
    recent.removeAll()
    lock.unlock()
    cache.removeAll()
  }

  public var statistics: ArchiveStatistics { cache.statistics }
}

/// All reader state is confined to one ticket holder. The condition is released
/// during I/O. Foreground requests take precedence between members, and cache
/// hits do not wait for an unrelated solid-stream decompression.
final class ArchiveSession: @unchecked Sendable {
  let entries: [ArchiveEntry]
  private let identity: ArchiveIdentity
  private let cache: ArchiveMemberCache
  private let condition = NSCondition()
  private struct Ticket {
    let id: UUID
    let priority: TaskPriority
  }
  private var waiting: [Ticket] = []
  private var busy = false
  private var reader: (any ArchiveReader)?
  private var nextIndex = 0
  private let indexed: [Int: ArchiveEntry]

  static func checkSize(_ size: Int64) throws {
    guard size >= 0, size <= ZIPArchive.maximumMemberBytes else {
      throw GlintError.tooLarge("This archive member exceeds the 256 MiB decode limit.")
    }
  }

  init(identity: ArchiveIdentity, cache: ArchiveMemberCache) throws {
    self.identity = identity
    self.cache = cache
    var result: [ArchiveEntry] = []
    if ["zip", "cbz"].contains(identity.url.pathExtension.lowercased()) {
      result = try ZIPArchive.entries(at: identity.url).enumerated().compactMap { index, zip in
        guard Self.isVisibleImage(zip.name) else { return nil }
        return ArchiveEntry(
          name: zip.name, uncompressedSize: Int64(zip.uncompressedSize), index: index,
          identity: identity, zip: zip)
      }
    } else {
      let source = try Self.makeReader(identity.url, listing: true)
      var index = 0
      while let header = try source.next() {
        try Task.checkCancellation()
        guard index < 100_000 else {
          throw GlintError.tooLarge("The archive has too many entries.")
        }
        if header.regular && Self.isVisibleImage(header.name) {
          result.append(
            ArchiveEntry(
              name: header.name, uncompressedSize: header.size, index: index,
              identity: identity, zip: nil))
        }
        try source.skip()
        index += 1
      }
    }
    guard try ArchiveIdentity(url: identity.url) == identity else {
      throw GlintError.archive("The archive changed while it was being indexed.")
    }
    entries = result
    indexed = Dictionary(uniqueKeysWithValues: result.map { ($0.index, $0) })
  }

  private static func isVisibleImage(_ name: String) -> Bool {
    let parts = name.split(separator: "/")
    return !parts.contains { $0.hasPrefix(".") || $0 == "__MACOSX" }
      && ImageFormats.isImage(URL(fileURLWithPath: name))
  }

  private static func makeReader(_ url: URL, listing: Bool = false) throws -> any ArchiveReader {
    if ["rar", "cbr"].contains(url.pathExtension.lowercased()) {
      return try RARReader(url: url, listing: listing)
    }
    return try SevenZipReader(url: url)
  }

  private func acquire() throws {
    let ticket = Ticket(id: UUID(), priority: Task.currentPriority)
    condition.lock()
    waiting.append(ticket)
    defer { condition.unlock() }
    while true {
      if Task.isCancelled {
        waiting.removeAll { $0.id == ticket.id }
        condition.broadcast()
        throw CancellationError()
      }
      let highest = waiting.map(\.priority).max()
      let best = waiting.first { $0.priority == highest }
      if !busy && best?.id == ticket.id {
        busy = true
        waiting.removeAll { $0.id == ticket.id }
        return
      }
      _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
    }
  }

  private func release() {
    condition.lock()
    busy = false
    condition.broadcast()
    condition.unlock()
  }

  func read(_ target: ArchiveEntry) throws -> Data {
    while true {
      try Task.checkCancellation()
      if let data = cache.value(for: target) { return data }
      try acquire()
      do {
        if let data = cache.value(for: target) {
          release()
          return data
        }
        if let zip = target.zip {
          let data = try ZIPArchive.read(zip, from: identity.url)
          try cache.insert(data, for: target)
          release()
          return data
        }
        if reader == nil || nextIndex > target.index {
          reader = try Self.makeReader(identity.url)
          nextIndex = 0
        }
        guard let reader, let header = try reader.next() else {
          throw GlintError.archive("The archive member is missing.")
        }
        let currentIndex = nextIndex
        nextIndex += 1
        if let entry = indexed[currentIndex],
          currentIndex == target.index || reader.cachesPrecedingImages
        {
          guard header.name == entry.name, header.size == entry.uncompressedSize else {
            throw GlintError.archive("The archive changed while it was being read.")
          }
          let data = try reader.read(size: entry.uncompressedSize)
          try cache.insert(data, for: entry)
          release()
          if currentIndex == target.index { return data }
        } else {
          try reader.skip()
          release()
        }
      } catch {
        reader = nil
        nextIndex = 0
        release()
        throw error
      }
    }
  }
}

/// Stores encoded image bytes, not rendered pixels. Disk names are random and
/// never derived from archive paths. One global budget serves all archives.
final class ArchiveMemberCache: @unchecked Sendable {
  private struct Value {
    let file: URL
    let count: Int
    var memory: Data?
    var accessed: UInt64
  }
  private let lock = NSLock()
  private var values: [ArchiveEntry: Value] = [:]
  private var root: URL?
  private var memoryBytes = 0
  private var diskBytes = 0
  private var clock: UInt64 = 0
  private var hits = 0
  private var extractions = 0
  private let memoryLimit: Int
  private let diskLimit: Int

  init(memoryLimit: Int = 64 * 1024 * 1024, diskLimit: Int = 1536 * 1024 * 1024) {
    self.memoryLimit = memoryLimit
    self.diskLimit = diskLimit
    // Recover space after a crash without touching another live Glint process.
    let temporary = FileManager.default.temporaryDirectory
    for url
      in (try? FileManager.default.contentsOfDirectory(
        at: temporary, includingPropertiesForKeys: nil)) ?? []
    where url.lastPathComponent.hasPrefix("Glint-ArchiveCache-") {
      let pieces = url.lastPathComponent.split(separator: "-")
      if pieces.count > 3, let pid = Int32(pieces[2]), pid > 0,
        kill(pid, 0) != 0, errno == ESRCH
      {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  deinit { if let root { try? FileManager.default.removeItem(at: root) } }

  func value(for entry: ArchiveEntry) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    guard var value = values[entry] else { return nil }
    guard let data = value.memory ?? (try? Data(contentsOf: value.file, options: .alwaysMapped))
    else {
      remove(entry)
      return nil
    }
    clock &+= 1
    value.accessed = clock
    values[entry] = value
    hits += 1
    return data
  }

  func insert(_ data: Data, for entry: ArchiveEntry) throws {
    lock.lock()
    defer { lock.unlock() }
    guard values[entry] == nil else { return }
    // Oversized cache candidates remain usable by the caller without exceeding
    // the cache budget (the member's independent decode limit was checked first).
    guard data.count <= diskLimit else {
      extractions += 1
      return
    }
    if root == nil {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "Glint-ArchiveCache-\(getpid())-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      root = directory
    }
    while diskBytes + data.count > diskLimit || values.count >= 4096 {
      guard let oldest = values.min(by: { $0.value.accessed < $1.value.accessed })?.key else {
        break
      }
      remove(oldest)
    }
    while memoryBytes + data.count > memoryLimit {
      guard
        let oldest = values.filter({ $0.value.memory != nil })
          .min(by: { $0.value.accessed < $1.value.accessed })?.key
      else { break }
      memoryBytes -= values[oldest]!.count
      values[oldest]!.memory = nil
    }
    let file = root!.appendingPathComponent(UUID().uuidString)
    try data.write(to: file, options: .atomic)
    clock &+= 1
    let keepMemory = data.count <= memoryLimit
    values[entry] = Value(
      file: file, count: data.count, memory: keepMemory ? data : nil, accessed: clock)
    if keepMemory { memoryBytes += data.count }
    diskBytes += data.count
    extractions += 1
  }

  private func remove(_ entry: ArchiveEntry) {
    guard let value = values.removeValue(forKey: entry) else { return }
    if value.memory != nil { memoryBytes -= value.count }
    diskBytes -= value.count
    try? FileManager.default.removeItem(at: value.file)
  }

  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    values.removeAll()
    memoryBytes = 0
    diskBytes = 0
    hits = 0
    extractions = 0
    if let root { try? FileManager.default.removeItem(at: root) }
    root = nil
  }

  var statistics: ArchiveStatistics {
    lock.lock()
    defer { lock.unlock() }
    return ArchiveStatistics(
      extractions: extractions, cacheHits: hits, memoryBytes: memoryBytes, diskBytes: diskBytes)
  }
}
