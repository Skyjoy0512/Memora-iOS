import Foundation

/// Matches local text fields without fetching files or contacting a service.
enum CollectionSearch {
  static func matches(_ query: String, fields: [String]) -> Bool {
    let terms = query.split(whereSeparator: \.isWhitespace)
    guard !terms.isEmpty else { return true }
    return terms.allSatisfy { term in
      fields.contains { field in
        field.range(of: String(term), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) != nil
      }
    }
  }
}
