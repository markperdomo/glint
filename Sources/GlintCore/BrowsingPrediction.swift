import Foundation

/// A short input history, independent of decoding and display timing.
public struct BrowsingPrediction: Sendable {
  public static let previewDimension = 512
  public static let settlingTime: Duration = .milliseconds(140)
  private var lastInput: ContinuousClock.Instant?
  private var direction = 1
  private var streak = 0
  private var rapid = false

  public init() {}

  public mutating func record(offset: Int, at now: ContinuousClock.Instant = .now) {
    let nextDirection = offset < 0 ? -1 : 1
    let recent = lastInput.map { $0.duration(to: now) < .seconds(1) } ?? false
    rapid = lastInput.map { $0.duration(to: now) < Self.settlingTime } ?? false
    streak = recent && nextDirection == direction ? streak + 1 : 1
    direction = nextDirection
    lastInput = now
  }

  public func isRapid(at now: ContinuousClock.Instant = .now) -> Bool {
    rapid && (settlingDeadline.map { now < $0 } ?? false)
  }

  public var settlingDeadline: ContinuousClock.Instant? {
    lastInput?.advanced(by: Self.settlingTime)
  }

  public var offsets: [Int] {
    let offsets = streak >= 2 ? [1, 2, 3, -1, 4, 5] : [1, -1, 2, -2]
    return offsets.map { $0 * direction }
  }
}
