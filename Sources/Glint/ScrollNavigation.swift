import AppKit

/// Converts wheel ticks and smooth gestures into discrete navigation requests.
struct ScrollNavigation {
  struct Sample {
    var deltaX: CGFloat = 0
    var deltaY: CGFloat
    var precise = false
    var phase: NSEvent.Phase = []
    var momentumPhase: NSEvent.Phase = []
    var timestamp: TimeInterval = 0
  }

  private var accumulated: CGFloat = 0
  private var consumed = false
  private var lastTimestamp: TimeInterval?
  private var lastMode: ScrollNavigationMode?

  mutating func reset() {
    accumulated = 0
    consumed = false
    lastTimestamp = nil
  }

  mutating func offset(for sample: Sample, mode: ScrollNavigationMode) -> Int? {
    if mode != lastMode {
      reset()
      lastMode = mode
    }
    guard mode != .off, !sample.precise || mode == .wheelAndTrackpad else {
      reset()
      return nil
    }
    // Momentum is never a new request, even after the fingers leave the pad.
    guard sample.momentumPhase.isEmpty else { return nil }
    if !sample.precise {
      reset()
      guard abs(sample.deltaY) > abs(sample.deltaX) else { return nil }
      // A normal wheel detent is often exactly one line. Do not discard it or
      // throttle distinct ticks into one request.
      return sample.deltaY < 0 ? 1 : -1
    }
    if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) { reset() }
    if sample.phase.contains(.ended) || sample.phase.contains(.cancelled) {
      reset()
      return nil
    }
    // Some smooth-scroll mice have precise deltas but no gesture phases.
    // A pause separates their bursts, rather than every event changing images.
    if sample.phase.isEmpty, let lastTimestamp, sample.timestamp - lastTimestamp > 0.25 {
      reset()
    }
    lastTimestamp = sample.timestamp
    guard !consumed, abs(sample.deltaY) > abs(sample.deltaX) else { return nil }
    if accumulated * sample.deltaY < 0 { accumulated = 0 }
    accumulated += sample.deltaY
    guard abs(accumulated) >= 32 else { return nil }
    consumed = true
    return accumulated < 0 ? 1 : -1
  }
}
