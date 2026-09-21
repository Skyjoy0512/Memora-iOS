import ActivityKit
import Foundation

struct MemoraRecordingAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// Anchored so a live timer reads the real elapsed time, which excludes
    /// time spent paused.
    var startedAt: Date
    var isPaused: Bool
    /// The elapsed time frozen while paused, shown instead of a live timer.
    var pausedElapsed: TimeInterval

    init(startedAt: Date, isPaused: Bool, pausedElapsed: TimeInterval = 0) {
      self.startedAt = startedAt
      self.isPaused = isPaused
      self.pausedElapsed = pausedElapsed
    }

    /// Lenient so a state written by an older build still decodes.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      startedAt = try container.decode(Date.self, forKey: .startedAt)
      isPaused = try container.decode(Bool.self, forKey: .isPaused)
      pausedElapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedElapsed) ?? 0
    }
  }

  var title: String
}
