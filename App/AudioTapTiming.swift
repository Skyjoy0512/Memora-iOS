import Foundation

/// Bounded, privacy-safe timing for the microphone tap. Only durations are
/// kept; no audio, file name or record identity enters it. Values are
/// microseconds measured around one tap callback.
struct AudioTapTiming: Sendable {
  struct Summary: Sendable, Equatable {
    var samples: Int
    var p50Microseconds: Double
    var p95Microseconds: Double
    var p99Microseconds: Double
    var maximumMicroseconds: Double
  }

  /// About six minutes of 44.1 kHz/4096-frame callbacks; older samples are
  /// overwritten so a 15-minute recording stays bounded.
  static let sampleCapacity = 4_096

  private var samples: [Double] = []
  private var nextIndex = 0
  private var total = 0
  private var maximum: Double = 0

  mutating func record(microseconds: Double) {
    guard microseconds.isFinite, microseconds >= 0 else { return }
    if samples.count < Self.sampleCapacity {
      samples.append(microseconds)
    } else {
      samples[nextIndex] = microseconds
      nextIndex = (nextIndex + 1) % Self.sampleCapacity
    }
    total += 1
    maximum = max(maximum, microseconds)
  }

  var summary: Summary? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    return Summary(
      samples: total,
      p50Microseconds: Self.percentile(sorted, 0.50),
      p95Microseconds: Self.percentile(sorted, 0.95),
      p99Microseconds: Self.percentile(sorted, 0.99),
      maximumMicroseconds: maximum)
  }

  private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    let position = Int((Double(sorted.count - 1) * fraction).rounded(.up))
    return sorted[min(max(position, 0), sorted.count - 1)]
  }
}
