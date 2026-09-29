import Foundation

/// A change the agent wants to make, waiting for the person's go-ahead.
struct AgentApproval: Identifiable, Hashable {
  var id = UUID()
  /// The reply the request belongs to, so the card appears under it.
  var messageID: UUID
  var icon: MemoraIcon
  var title: String
  /// What exactly will change, one line per item.
  var lines: [String]
  var confirmTitle: String
}
