import Foundation
import Observation

/// Keep microphone-level updates local to the recording sheet's meter.
@Observable
final class RecordingLevelMeter {
  /// 0...1, smoothed to avoid jitter between samples.
  private(set) var level: Double = 0
  /// Disables sampling when the meter is hidden.
  var isActive = false

  func update(from target: Double) {
    let rate = target > level ? 0.6 : 0.12
    let next = level + (target - level) * rate
    if abs(next - level) >= 0.002 { level = next }
  }

  func reset() {
    if level != 0 { level = 0 }
  }
}
