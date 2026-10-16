import Foundation

struct TaskRelationships: Hashable, Codable {
  var parentID: UUID?
  var documentIDs: [UUID] = []
  /// Set only by an explicit person selection; a name match never creates this link.
  var assigneePersonID: UUID?
}

extension TaskRelationships {
  private enum CodingKeys: String, CodingKey { case parentID, documentIDs, assigneePersonID }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
    documentIDs = try values.decodeIfPresent([UUID].self, forKey: .documentIDs) ?? []
    assigneePersonID = try values.decodeIfPresent(UUID.self, forKey: .assigneePersonID)
  }
}
