import ActivityKit
import Foundation

struct MemoraRecordingAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var startedAt: Date
    var isPaused: Bool
  }

  var title: String
}
