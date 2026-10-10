import Foundation

struct TaskRelationships: Hashable, Codable {
  var parentID: UUID?
  var documentIDs: [UUID] = []
}
