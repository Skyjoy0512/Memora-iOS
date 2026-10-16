import Foundation

/// Fingerprint only the metadata eligible for AI, excluding photos and contact IDs.
struct PersonAIContext: Codable, Hashable {
  var id: UUID
  var name: String
  var note: String?
  var privacy: RecordPrivacy

  init(_ person: Person) {
    id = person.id
    name = String(person.name.prefix(200))
    note = person.note.map { String($0.prefix(2_000)) }
    privacy = person.effectivePrivacy
  }
}
