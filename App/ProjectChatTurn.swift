import Foundation

struct ProjectChatTurn: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var role: Role
  var text: String
  var createdAt = Date.now
  var engineLabel: String?
  var modelLabel: String?
  var citations: [ProjectCitation] = []
  var contextReferences: [ProjectCitation]?
  /// Set by a cloud response whose current and inherited evidence was checked.
  var cloudReplayAuthorizationVersion: Int?

  enum Role: String, Codable, Sendable { case user, assistant }
}
