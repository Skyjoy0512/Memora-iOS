import Foundation

struct ShareInboxItem: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var kind: Kind
  var title: String
  var value: String
  enum Kind: String, Codable, Sendable { case link, file, text }
}
