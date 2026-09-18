import Foundation
import Synchronization

public struct CacheStatistics: Sendable {
  public let hits: Int
  public let misses: Int
  public let bytes: Int
  public let count: Int
  public let decodes: Int
  public let coalesced: Int
  public let inFlight: Int
}

/// Shared requests survive individual caller cancellation. Speculative work can
/// occupy only one of the viewer's two slots, leaving room for navigation.
public actor ImagePipeline {
  public static let shared = ImagePipeline(byteLimit: 256 * 1024 * 1024)
  public static let thumbnails = ImagePipeline(
    byteLimit: 48 * 1024 * 1024, maximumConcurrentDecodes: 1)

  public enum Priority: Sendable {
    case foreground, prefetch
  }

  typealias Decoder = @Sendable (ImageAsset, Int, Int) throws -> DecodedImage
  private struct Request {
    let id = UUID()
    let order: UInt64
    var priority: Priority
    var running = false
    var waiters: [UUID: CheckedContinuation<DecodedImage, any Error>]
  }

  private nonisolated let cache: RenditionCache
  private let decoder: Decoder
  private let maximumConcurrentDecodes: Int
  private var requests: [ImageCacheKey: Request] = [:]
  private var activeDecodes = 0
  private var activePrefetches = 0
  private var order: UInt64 = 0
  private var misses = 0
  private var decodes = 0
  private var coalesced = 0

  public init(byteLimit: Int, maximumConcurrentDecodes: Int = 2) {
    cache = RenditionCache(byteLimit: byteLimit)
    self.maximumConcurrentDecodes = max(1, maximumConcurrentDecodes)
    decoder = { try ImageDecoder.decode($0, frame: $1, maximumDimension: $2) }
  }

  init(byteLimit: Int, maximumConcurrentDecodes: Int = 2, decoder: @escaping Decoder) {
    cache = RenditionCache(byteLimit: byteLimit)
    self.maximumConcurrentDecodes = max(1, maximumConcurrentDecodes)
    self.decoder = decoder
  }

  /// Memory-only lookup, safe on the main actor. Returns a sufficient rendition
  /// when available, otherwise the largest cached preview of this exact asset/frame.
  public nonisolated func cachedImage(
    for asset: ImageAsset, frame: Int = 0, maximumDimension: Int = 2048
  ) -> DecodedImage? {
    cache.lookup(
      ImageCacheKey(asset: asset, frame: frame, dimension: maximumDimension), allowPreview: true)
  }

  public func image(
    for asset: ImageAsset, frame: Int = 0, maximumDimension: Int = 2048,
    priority: Priority = .foreground
  ) async throws -> DecodedImage {
    try Task.checkCancellation()
    let key = ImageCacheKey(asset: asset, frame: frame, dimension: maximumDimension)
    if let image = cache.lookup(key, allowPreview: false) { return image }
    misses += 1
    let waiter = UUID()
    let image = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if var request = requests[key] {
          request.waiters[waiter] = continuation
          if priority == .foreground { request.priority = .foreground }
          requests[key] = request
          coalesced += 1
        } else {
          order &+= 1
          requests[key] = Request(
            order: order, priority: priority, waiters: [waiter: continuation])
        }
        startWork()
      }
    } onCancel: {
      Task { await self.cancel(waiter, for: key) }
    }
    try Task.checkCancellation()
    return image
  }

  private func cancel(_ waiter: UUID, for key: ImageCacheKey) {
    guard var request = requests[key],
      let continuation = request.waiters.removeValue(forKey: waiter)
    else { return }
    // Image I/O cannot interrupt a synchronous decode. Keep a running result
    // adoptable and cache it, but discard abandoned work that has not started.
    requests[key] = request.waiters.isEmpty && !request.running ? nil : request
    continuation.resume(throwing: CancellationError())
    startWork()
  }

  private func startWork() {
    while activeDecodes < maximumConcurrentDecodes {
      let queued = requests.filter { !$0.value.running }
      let foreground = queued.filter { $0.value.priority == .foreground }
      let candidates = foreground.isEmpty ? queued : foreground
      guard let next = candidates.min(by: { $0.value.order < $1.value.order }) else { return }
      if next.value.priority == .prefetch,
        activePrefetches >= max(1, maximumConcurrentDecodes - 1)
      {
        return
      }
      let key = next.key
      let id = next.value.id
      requests[key]?.running = true
      activeDecodes += 1
      let speculative = next.value.priority == .prefetch
      if speculative { activePrefetches += 1 }
      decodes += 1
      let decoder = decoder
      Task.detached(priority: next.value.priority == .foreground ? .userInitiated : .utility) {
        let result = Result { try decoder(key.asset, key.frame, key.dimension) }
        await self.complete(key, id: id, speculative: speculative, result: result)
      }
    }
  }

  private func complete(
    _ key: ImageCacheKey, id: UUID, speculative: Bool, result: Result<DecodedImage, any Error>
  ) {
    activeDecodes -= 1
    if speculative { activePrefetches -= 1 }
    if let request = requests[key], request.id == id {
      requests.removeValue(forKey: key)
      if case .success(let image) = result { cache.insert(image, for: key) }
      for continuation in request.waiters.values { continuation.resume(with: result) }
    }
    startWork()
  }

  public func removeAll() {
    invalidateRequests { _ in true }
    cache.removeAll()
  }

  public func invalidate(url: URL) {
    let url = url.standardizedFileURL
    invalidateRequests { $0.asset.url == url }
    cache.invalidate(url: url)
  }

  private func invalidateRequests(where matches: (ImageCacheKey) -> Bool) {
    for key in requests.keys.filter(matches) {
      guard let request = requests.removeValue(forKey: key) else { continue }
      for continuation in request.waiters.values {
        continuation.resume(throwing: CancellationError())
      }
    }
    // Running jobs still count against concurrency until they finish. Their IDs
    // prevent obsolete completions from filling the cache or replacing new jobs.
    startWork()
  }

  public var statistics: CacheStatistics {
    let snapshot = cache.statistics
    return CacheStatistics(
      hits: snapshot.hits, misses: misses, bytes: snapshot.bytes, count: snapshot.count,
      decodes: decodes, coalesced: coalesced, inFlight: activeDecodes)
  }
}

private struct ImageCacheKey: Hashable, Sendable {
  let asset: ImageAsset
  let frame: Int
  let dimension: Int
}

/// The lock only protects bounded in-memory bookkeeping, never decoding or I/O.
private final class RenditionCache: Sendable {
  private struct Entry {
    let image: DecodedImage
    var access: UInt64
    var dimension: Int { max(image.image.width, image.image.height) }
  }
  private struct State {
    var entries: [ImageCacheKey: Entry] = [:]
    var bytes = 0
    var clock: UInt64 = 0
    var hits = 0
  }
  private let state = Mutex(State())
  private let byteLimit: Int

  init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

  func lookup(_ key: ImageCacheKey, allowPreview: Bool) -> DecodedImage? {
    state.withLock { state in
      // Normal warm navigation is a dictionary lookup. Only fall back to a
      // bounded scan when another rendition may satisfy the requested size.
      var chosen: (key: ImageCacheKey, value: Entry)?
      if let exact = state.entries[key] {
        chosen = (key, exact)
      } else {
        var bestSufficient: (key: ImageCacheKey, value: Entry)?
        var bestPreview: (key: ImageCacheKey, value: Entry)?
        for candidate in state.entries
        where candidate.key.asset == key.asset && candidate.key.frame == key.frame {
          let metadata = candidate.value.image.metadata
          let originalDimension = max(metadata.pixelWidth, metadata.pixelHeight)
          let requested =
            key.dimension == 0
            ? (key.asset.isPDF ? 4096 : originalDimension) : key.dimension
          let sufficient =
            candidate.value.dimension >= requested
            || (!key.asset.isPDF && candidate.value.dimension >= originalDimension)
          if sufficient {
            if bestSufficient == nil || candidate.value.dimension < bestSufficient!.value.dimension
            {
              bestSufficient = candidate
            }
          } else if allowPreview,
            bestPreview == nil || candidate.value.dimension > bestPreview!.value.dimension
          {
            bestPreview = candidate
          }
        }
        chosen = bestSufficient ?? bestPreview
      }
      guard let chosen else { return nil }
      state.clock &+= 1
      state.hits += 1
      state.entries[chosen.key]?.access = state.clock
      return chosen.value.image
    }
  }

  func insert(_ image: DecodedImage, for key: ImageCacheKey) {
    state.withLock { state in
      if let old = state.entries.removeValue(forKey: key) { state.bytes -= old.image.byteCost }
      guard image.byteCost <= byteLimit else { return }
      while state.bytes + image.byteCost > byteLimit || state.entries.count >= 512 {
        guard let oldest = state.entries.min(by: { $0.value.access < $1.value.access }) else {
          break
        }
        state.bytes -= oldest.value.image.byteCost
        state.entries.removeValue(forKey: oldest.key)
      }
      state.clock &+= 1
      state.entries[key] = Entry(image: image, access: state.clock)
      state.bytes += image.byteCost
    }
  }

  func removeAll() {
    state.withLock { state in
      state.entries.removeAll()
      state.bytes = 0
    }
  }

  func invalidate(url: URL) {
    state.withLock { state in
      for key in state.entries.keys.filter({ $0.asset.url == url }) {
        state.bytes -= state.entries.removeValue(forKey: key)?.image.byteCost ?? 0
      }
    }
  }

  var statistics: (hits: Int, bytes: Int, count: Int) {
    state.withLock { ($0.hits, $0.bytes, $0.entries.count) }
  }
}
