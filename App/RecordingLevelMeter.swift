import Foundation
import Observation

/// The microphone level the glow follows. It is kept apart from the model so the
/// ~22 updates a second reach only the view that draws the glow, instead of
/// every screen observing the model.
@Observable
final class RecordingLevelMeter {
  /// 0...1, smoothed so the glow follows a voice rather than jittering.
  private(set) var level: Double = 0
  /// False while no screen is showing the glow; sampling then costs nothing.
  var isActive = false

  func update(from target: Double) {
    let rate = target > level ? 0.6 : 0.12
    level += (target - level) * rate
  }

  func reset() {
    level = 0
  }
}
