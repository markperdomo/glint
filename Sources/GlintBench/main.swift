import Foundation
import GlintCore

@main
struct GlintBench {
  static func main() async throws {
    guard CommandLine.arguments.count > 1 else {
      print("Usage: swift run -c release glint-bench /path/to/images [count] [maximum-dimension]")
      return
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let limit = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 30 : 30
    let dimension = max(
      1, CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 2048 : 2048)
    let start = ContinuousClock.now
    let collection = try FolderScanner.open([url])
    let assets = Array(ImageSortOrder.name.sorted(collection.assets).prefix(max(1, limit)))
    print("Scanned \(collection.assets.count) images in \(start.duration(to: .now))")
    let pipeline = ImagePipeline(byteLimit: 256 * 1024 * 1024)
    var times: [Double] = []
    for asset in assets {
      let start = ContinuousClock.now
      _ = try await pipeline.image(for: asset, maximumDimension: dimension)
      let elapsed = start.duration(to: .now).components
      times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
    }
    if !times.isEmpty {
      let sorted = times.sorted()
      print(
        String(
          format: "Cold decode: median %.2f ms, p95 %.2f ms (%d images, %d px limit)",
          sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
          times.count, dimension))
      let warm = ContinuousClock.now
      for asset in assets.reversed() {
        _ = try await pipeline.image(for: asset, maximumDimension: dimension)
      }
      print("Reverse pass: \(warm.duration(to: .now))")
    }
    let stats = await pipeline.statistics
    print(
      "Cache: \(stats.hits) hits, \(stats.misses) misses, \(stats.bytes / 1024 / 1024) MiB retained"
    )
    print("Work: \(stats.decodes) decodes, \(stats.coalesced) shared requests")
    try await measureProgressiveLoading(assets, dimension: dimension)
    print("Decode measurements only; this does not measure display latency or compare against Xee.")
  }

  private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
  }

  private static func report(_ label: String, times: [Double]) {
    guard !times.isEmpty else { return }
    let sorted = times.sorted()
    print(
      String(
        format: "%@: median %.3f ms, p95 %.3f ms", label, sorted[sorted.count / 2],
        sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]))
  }

  private static func measureProgressiveLoading(_ assets: [ImageAsset], dimension: Int) async throws
  {
    let pipeline = ImagePipeline(byteLimit: 256 * 1024 * 1024)
    var previews: [Double] = []
    var refined: [Double] = []
    for asset in assets {
      let start = ContinuousClock.now
      _ = try await pipeline.image(
        for: asset, maximumDimension: min(dimension, BrowsingPrediction.previewDimension))
      previews.append(milliseconds(since: start))
      _ = try await pipeline.image(for: asset, maximumDimension: dimension)
      refined.append(milliseconds(since: start))
    }
    report("Progressive first pixels (decode/cache only)", times: previews)
    report("Progressive final pixels (including preview work)", times: refined)
    var cached: [Double] = []
    var available = 0
    for asset in assets.reversed() {
      let start = ContinuousClock.now
      if pipeline.cachedImage(for: asset, maximumDimension: dimension) != nil { available += 1 }
      cached.append(milliseconds(since: start))
    }
    report("Synchronous cache lookup", times: cached)
    print("Cached renditions available: \(available)/\(assets.count)")
  }

}
