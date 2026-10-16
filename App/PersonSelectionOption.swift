import Foundation

struct PersonSelectionOption: Identifiable {
  var id: UUID
  var label: String

  static func options(_ people: [Person]) -> [Self] {
    let counts = Dictionary(grouping: people, by: { PersonIdentity.normalized($0.name) }).mapValues(\.count)
    let prefixes = Dictionary(grouping: people, by: { PersonIdentity.normalized($0.name) + "|" + $0.id.uuidString.prefix(8) }).mapValues(\.count)
    return people.map { person in
      let duplicate = counts[PersonIdentity.normalized(person.name), default: 0] > 1
      let note = String((person.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
      let prefix = String(person.id.uuidString.prefix(8))
      let identifier = prefixes[PersonIdentity.normalized(person.name) + "|" + prefix, default: 0] > 1 ? person.id.uuidString : prefix
      let detail = note.isEmpty ? "ID " + identifier : note + " · " + identifier
      return Self(id: person.id, label: duplicate ? person.name + "（" + detail + "）" : person.name)
    }.sorted {
      let order = $0.label.localizedStandardCompare($1.label)
      return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
    }
  }
}
