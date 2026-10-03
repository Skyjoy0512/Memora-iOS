import Foundation

/// One thing the agent did while answering, shown in the reply so the person
/// can see which records it read and what it changed.
struct AgentStep: Identifiable, Hashable {
  enum State: Hashable {
    case running
    case done
    case declined
    case failed
  }

  var id = UUID()
  var icon: MemoraIcon
  var title: String
  /// What came of it: how many records were found, or why it stopped.
  var detail: String?
  var state = State.running
  /// For a search: what was searched for, and what it found.
  var query: String?
  var results: [Result] = []

  /// One thing a search found: a record or a mail.
  struct Result: Hashable {
    var title: String
    var subtitle: String?
    /// Set for a record, so the trace can open it.
    var meetingID: UUID?
  }
}
