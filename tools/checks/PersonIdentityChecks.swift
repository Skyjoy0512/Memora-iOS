import Foundation

@main struct PersonIdentityChecks {
  static func main() throws {
    let first = Person(id: UUID(), name: "田中 太郎")
    let second = Person(id: UUID(), name: "田中 花子")
    let same = Person(id: UUID(), name: "田中 太郎")
    precondition(PersonIdentity.uniqueMatch(for: "田中さん", in: [first, second]) == nil)
    precondition(PersonIdentity.uniqueMatch(for: "田中太郎様", in: [first, second])?.id == first.id)
    precondition(PersonIdentity.uniqueMatch(for: "田中太郎", in: [first, same]) == nil)
    precondition(PersonIdentity.uniqueMatch(for: "", in: [first]) == nil)
    precondition(PersonIdentity.uniqueMatch(for: "存在しない", in: [first]) == nil)
    precondition(PersonIdentity.candidates(for: "田中", in: [second, first]).count == 2)
    print("PersonIdentityChecks: passed (same family, identical names, honorific, spaces, missing)")
  }
}
