import Foundation

public struct CacheStatistics: Sendable {
  public let hits: Int
  public let misses: Int
  public let bytes: Int
  public let count: Int
}

/// Cache lookup stays responsive while a separate worker actor decodes misses.
/// Each pipeline has one worker, bounding decode concurrency across the app to two.
public actor ImagePipeline {
  public static let shared = ImagePipeline(byteLimit: 256 * 1024 * 1024)
  public static let thumbnails = ImagePipeline(byteLimit: 48 * 1024 * 1024)

  private struct Key: Hashable {
    let asset: ImageAsset
    let frame: Int
    let dimension: Int
  }
  private struct Entry {
    let decoded: DecodedImage
    var access: UInt64
  }
  private var cache: [Key: Entry] = [:]
  private let worker = ImageDecodeWorker()
  private let byteLimit: Int
  private var bytes = 0
  private var clock: UInt64 = 0
  private var hits = 0
  private var misses = 0
  private var epoch: UInt64 = 0

  public init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

  public func image(for asset: ImageAsset, frame: Int = 0, maximumDimension: Int = 2048)
    async throws -> DecodedImage
  {
    try Task.checkCancellation()
    let key = Key(asset: asset, frame: frame, dimension: maximumDimension)
    clock &+= 1
    if var entry = cache[key] {
      entry.access = clock
      cache[key] = entry
      hits += 1
      return entry.decoded
    }
    misses += 1
    let epochAtStart = epoch
    let decoded = try await worker.decode(asset, frame: frame, dimension: maximumDimension)
    try Task.checkCancellation()
    guard epochAtStart == epoch else { return decoded }
    let cost = decoded.byteCost
    // Concurrent callers can request the same uncached key. Replace, rather
    // than double-count, a result that another caller has already inserted.
    if let previous = cache.removeValue(forKey: key) { bytes -= previous.decoded.byteCost }
    if cost <= byteLimit {
      while bytes + cost > byteLimit || cache.count >= 512 {
        guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
        bytes -= oldest.value.decoded.byteCost
        cache.removeValue(forKey: oldest.key)
      }
      cache[key] = Entry(decoded: decoded, access: clock)
      bytes += cost
    }
    return decoded
  }

  public func removeAll() {
    epoch &+= 1
    cache.removeAll()
    bytes = 0
  }
  public func invalidate(url: URL) {
    epoch &+= 1
    for key in cache.keys.filter({ $0.asset.url == url.standardizedFileURL }) {
      bytes -= cache.removeValue(forKey: key)?.decoded.byteCost ?? 0
    }
  }
  public var statistics: CacheStatistics {
    CacheStatistics(hits: hits, misses: misses, bytes: bytes, count: cache.count)
  }
}

private actor ImageDecodeWorker {
  func decode(_ asset: ImageAsset, frame: Int, dimension: Int) throws -> DecodedImage {
    try Task.checkCancellation()
    return try ImageDecoder.decode(asset, frame: frame, maximumDimension: dimension)
  }
}
