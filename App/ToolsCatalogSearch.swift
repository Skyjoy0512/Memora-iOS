import Foundation

/// Searches catalog metadata only, never records or connected services.
enum ToolsCatalogSearch {
  static func matches(_ query: String, fields: [String]) -> Bool {
    CollectionSearch.matches(query, fields: fields)
  }
}
