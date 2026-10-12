import Foundation

/// A thread keeps a stable project identity; renaming a project never changes
/// its scope. Detaching on project deletion preserves the saved conversation.
struct ProjectChatThread: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var projectID: UUID?
  var title: String
  var createdAt = Date.now
  var updatedAt = Date.now
  var messages: [ProjectChatTurn] = []
  var pendingMessageID: UUID?
  var lastFailure: String?
}
