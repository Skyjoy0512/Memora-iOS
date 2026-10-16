import Foundation

struct MemoryRetrievalItem: Equatable {
  enum Kind: String { case semantic, episode }
  var id: UUID
  var kind: Kind
  var text: String
  var updatedAt: Date
  var workspaceID: String?
  var personID: UUID?
  var sourceID: UUID
}
