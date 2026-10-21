import Foundation

/// Searches catalog metadata only, never records or connected services.
enum ToolsCatalogSearch {
  static func matches(_ query: String, fields: [String]) -> Bool {
    let terms = query.split(whereSeparator: \.isWhitespace)
    let text = fields.joined(separator: "\n")
    return terms.allSatisfy {
      text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) != nil
    }
  }
}
