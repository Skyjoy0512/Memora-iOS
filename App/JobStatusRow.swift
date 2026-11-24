import Foundation

/// What the person needs to know about one queued summary: whether it is
/// running, waiting its turn, or stopped until they act.
struct JobStatusRow: Identifiable {
  enum State: Equatable {
    case running(stage: String)
    case waiting
    case stopped(reason: String)
  }

  var jobID: UUID
  var meetingID: UUID
  var title: String
  var state: State
  var receivedAt: Date
  var startedAt: Date?

  var id: UUID { jobID }

  /// Stopped work first, then what is running, then what is waiting.
  var urgency: Int {
    switch state {
    case .stopped: 0
    case .running: 1
    case .waiting: 2
    }
  }

  var needsUserAction: Bool {
    if case .stopped = state { return true }
    return false
  }
}
