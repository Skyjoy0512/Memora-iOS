import Foundation

/// A display name is a search hint; only a unique match can identify a person.
enum PersonIdentity {
  static func normalized(_ name: String) -> String {
    var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    for suffix in ["さん", "様", "さま", "くん", "君", "ちゃん", "氏"] where value.hasSuffix(suffix) {
      value.removeLast(suffix.count)
      break
    }
    return value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
      .filter { !$0.isWhitespace }
  }

  static func candidates(for query: String, in people: [Person]) -> [Person] {
    let query = normalized(query)
    guard !query.isEmpty else { return people }
    let exact = people.filter { normalized($0.name) == query }
    if !exact.isEmpty { return exact }
    return people.filter { normalized($0.name).contains(query) }
  }

  static func uniqueMatch(for query: String, in people: [Person]) -> Person? {
    guard !normalized(query).isEmpty else { return nil }
    let matches = candidates(for: query, in: people)
    return matches.count == 1 ? matches[0] : nil
  }
}
