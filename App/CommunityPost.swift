import Foundation

struct CommunityPost: Codable, Identifiable {
  var id: String
  var title: String
  var summary: String
  var definition: MarketplaceDefinition
  var authorID: String
  var authorName: String
  var createdAt: Double
  var status: String
  var likes: Int
  var downloads: Int
  var version: String
  var liked: Bool?
  var statusLabel: String {
    switch status { case "published": "公開中"; case "pending": "審査待ち"; case "removed": "取り下げ済み"; default: "確認中" }
  }
}
