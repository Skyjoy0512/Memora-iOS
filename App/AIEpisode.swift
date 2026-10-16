import Foundation

/// Extractive metadata about an exchange, separate from claims about the user.
struct AIEpisode: Codable, Hashable {
  var id: UUID
  var sessionID: UUID
  var date: Date
  var topic: String
  var objective: String
  var summary: String
  var decisions: [String] = []
  var unresolved: [String] = []
  var personIDs: [UUID] = []
  var projectIDs: [UUID] = []
  var recordIDs: [UUID] = []
  var documentIDs: [UUID] = []
  var sourceMessageIDs: [UUID] = []
  var workspaceID: String?
  var provenance: AIConversationProvenance?
}
