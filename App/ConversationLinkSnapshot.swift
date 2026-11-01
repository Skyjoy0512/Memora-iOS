import Foundation

struct ConversationLinkSnapshot: Codable, Sendable {
  var originalURL: URL
  var title: String
  var fetchedAt: Date
  var blocks: [ProjectSourceText]
  var notice: String?
}
