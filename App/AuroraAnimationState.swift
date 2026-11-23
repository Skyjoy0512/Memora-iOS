import Foundation

/// Active time remains continuous across power, visibility and motion changes.
struct AuroraAnimationState {
  private var accumulated: Duration = .zero
  private var resumedAt: ContinuousClock.Instant?

  mutating func setRunning(_ running: Bool, at instant: ContinuousClock.Instant) {
    if running {
      if resumedAt == nil { resumedAt = instant }
    } else if let resumedAt {
      accumulated += max(.zero, resumedAt.duration(to: instant))
      self.resumedAt = nil
    }
  }

  func phase(at instant: ContinuousClock.Instant) -> Double {
    let duration = accumulated + (resumedAt.map { max(.zero, $0.duration(to: instant)) } ?? .zero)
    let (seconds, attoseconds) = duration.components
    return (Double(seconds) + Double(attoseconds) / 1e18) * 0.27
  }
}
