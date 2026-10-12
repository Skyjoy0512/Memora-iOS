import Foundation

struct ProjectSourceText: Codable, Hashable, Sendable {
  var text: String
  var page: Int?
  var time: TimeInterval?
}
