import Foundation

struct ProjectChatTurn: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var role: Role
  var text: String
  var createdAt = Date.now
  var engineLabel: String?
  var modelLabel: String?
  var citations: [ProjectCitation] = []

  enum Role: String, Codable, Sendable { case user, assistant }
}
