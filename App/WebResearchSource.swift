import Foundation

struct WebResearchSource: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var title: String
  var url: URL
  var text: String
  var kind: Kind
  var retrievedAt = Date.now
  var publishedAt: Date?
  enum Kind: String, Codable, Sendable {
    case searchExcerpt
    case extractedPassage
    var label: String { self == .searchExcerpt ? "検索抜粋" : "検索APIの抽出本文" }
  }
}
