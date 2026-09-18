import Foundation
import Synchronization
import Testing

@testable import GlintCore

private enum ProbeError: Error { case timeout }

/// Holds a real synchronous decode at a known point, without timing assumptions
/// about the speed of Image I/O or the order in which tasks begin executing.
private final class DecodeProbe: Sendable {
  let gate = DispatchSemaphore(value: 0)
  private let starts = Mutex<[String]>([])
  private let blocked: String

  init(blocked: String) { self.blocked = blocked }
  var names: [String] { starts.withLock { $0 } }

  func decode(_ asset: ImageAsset, _ frame: Int, _ dimension: Int) throws -> DecodedImage {
    starts.withLock { $0.append(asset.name) }
    if asset.name == blocked, gate.wait(timeout: .now() + 5) == .timedOut {
      throw ProbeError.timeout
    }
    return try ImageDecoder.decode(asset, frame: frame, maximumDimension: dimension)
  }
}

private func eventually(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !(await condition()) {
    guard ContinuousClock.now < deadline else { throw ProbeError.timeout }
    try await Task.sleep(for: .milliseconds(1))
  }
}

@Test func foregroundAdoptsCancelledRunningPrefetchWithoutDecodingAgain() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let asset = ImageAsset(url: try folder.image("a.png"))
  let probe = DecodeProbe(blocked: asset.name)
  defer { probe.gate.signal() }
  let pipeline = ImagePipeline(byteLimit: 1_000_000, decoder: probe.decode)
  let prefetch = Task { try await pipeline.image(for: asset, priority: .prefetch) }
  try await eventually { probe.names.count == 1 }
  prefetch.cancel()
  do {
    _ = try await prefetch.value
    Issue.record("A cancelled subscriber received an image")
  } catch { #expect(error is CancellationError) }
  let foreground = Task { try await pipeline.image(for: asset) }
  try await eventually { await pipeline.statistics.coalesced == 1 }
  probe.gate.signal()
  let image = try await foreground.value
  #expect(image.image.width == 120)
  #expect(await pipeline.statistics.decodes == 1)
  #expect(pipeline.cachedImage(for: asset)?.image === image.image)
}

@Test func foregroundHasReservedCapacityAndAbandonedQueuedWorkDoesNotDecode() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let a = ImageAsset(url: try folder.image("a.png"))
  let b = ImageAsset(url: try folder.image("b.png"))
  let c = ImageAsset(url: try folder.image("c.png"))
  let probe = DecodeProbe(blocked: a.name)
  defer { probe.gate.signal() }
  let pipeline = ImagePipeline(byteLimit: 1_000_000, decoder: probe.decode)
  let blocked = Task { try await pipeline.image(for: a, priority: .prefetch) }
  try await eventually { probe.names.count == 1 }
  let queued = Task { try await pipeline.image(for: c, priority: .prefetch) }
  try await eventually { await pipeline.statistics.misses == 2 }
  let foreground = Task { try await pipeline.image(for: b) }
  try await eventually { probe.names.contains(b.name) }
  _ = try await foreground.value
  #expect(!probe.names.contains(c.name))
  queued.cancel()
  do {
    _ = try await queued.value
    Issue.record("A cancelled queued request completed")
  } catch { #expect(error is CancellationError) }
  probe.gate.signal()
  _ = try await blocked.value
  #expect(probe.names == [a.name, b.name])
  #expect(await pipeline.statistics.decodes == 2)
}

@Test func foregroundPromotesAQueuedPrefetchAheadOfOtherSpeculation() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let a = ImageAsset(url: try folder.image("a.png"))
  let b = ImageAsset(url: try folder.image("b.png"))
  let c = ImageAsset(url: try folder.image("c.png"))
  let probe = DecodeProbe(blocked: a.name)
  defer { probe.gate.signal() }
  let pipeline = ImagePipeline(
    byteLimit: 1_000_000, maximumConcurrentDecodes: 1, decoder: probe.decode)
  let first = Task { try await pipeline.image(for: a) }
  try await eventually { probe.names.count == 1 }
  let second = Task { try await pipeline.image(for: b, priority: .prefetch) }
  try await eventually { await pipeline.statistics.misses == 2 }
  let third = Task { try await pipeline.image(for: c, priority: .prefetch) }
  try await eventually { await pipeline.statistics.misses == 3 }
  let foreground = Task { try await pipeline.image(for: c) }
  try await eventually { await pipeline.statistics.coalesced == 1 }
  probe.gate.signal()
  _ = try await first.value
  _ = try await foreground.value
  _ = try await second.value
  _ = try await third.value
  #expect(probe.names == [a.name, c.name, b.name])
  #expect(await pipeline.statistics.decodes == 3)
}

@Test func invalidationDiscardsRunningResultsWithoutEvictingUnrelatedImages() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let a = ImageAsset(url: try folder.image("a.png"))
  let b = ImageAsset(url: try folder.image("b.png"))
  let probe = DecodeProbe(blocked: a.name)
  defer { probe.gate.signal() }
  let pipeline = ImagePipeline(byteLimit: 1_000_000, decoder: probe.decode)
  _ = try await pipeline.image(for: b)
  let pending = Task { try await pipeline.image(for: a) }
  try await eventually { probe.names.contains(a.name) }
  await pipeline.invalidate(url: a.url)
  do {
    _ = try await pending.value
    Issue.record("An invalidated result was published")
  } catch { #expect(error is CancellationError) }
  probe.gate.signal()
  try await eventually { await pipeline.statistics.inFlight == 0 }
  #expect(pipeline.cachedImage(for: a) == nil)
  #expect(pipeline.cachedImage(for: b) != nil)
  // A fresh request for the same key must not reuse the invalidated job.
  probe.gate.signal()
  _ = try await pipeline.image(for: a)
  #expect(await pipeline.statistics.decodes == 3)
}

@Test func cachedPreviewsKeepAssetAndFrameIdentityAndLargerRenditionsAreReused() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let asset = ImageAsset(url: try folder.image("a.png", width: 1200, height: 800))
  let pipeline = ImagePipeline(byteLimit: 2_000_000)
  _ = try await pipeline.image(for: asset, maximumDimension: 80)
  #expect(pipeline.cachedImage(for: asset, maximumDimension: 512)?.image.width == 80)
  #expect(pipeline.cachedImage(for: asset, frame: 1) == nil)
  let changed = ImageAsset(url: asset.url, byteCount: asset.byteCount + 1)
  #expect(pipeline.cachedImage(for: changed) == nil)
  let larger = try await pipeline.image(for: asset, maximumDimension: 400)
  let smaller = try await pipeline.image(for: asset, maximumDimension: 200)
  #expect(larger.image === smaller.image)
  #expect(await pipeline.statistics.decodes == 2)
  #expect(await pipeline.statistics.bytes <= 2_000_000)
  await pipeline.removeAll()
  #expect(pipeline.cachedImage(for: asset) == nil)
}

@Test func failedSharedRequestsDoNotPoisonFutureLoads() async throws {
  let folder = try FixtureDirectory()
  defer { folder.remove() }
  let url = folder.url.appendingPathComponent("broken.png")
  try Data([0, 1, 2]).write(to: url)
  let asset = ImageAsset(url: url)
  let pipeline = ImagePipeline(byteLimit: 1_000_000)
  for _ in 0..<2 {
    do {
      _ = try await pipeline.image(for: asset)
      Issue.record("Corrupt image decoded successfully")
    } catch { #expect(!(error is CancellationError)) }
  }
  #expect(await pipeline.statistics.decodes == 2)
  #expect(pipeline.cachedImage(for: asset) == nil)
}
