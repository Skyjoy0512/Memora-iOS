import Foundation

struct SourceSearchRequest: Hashable {
  var query: String
  var sources: [ProjectSource]
  var workspaceGeneration: UUID
}
