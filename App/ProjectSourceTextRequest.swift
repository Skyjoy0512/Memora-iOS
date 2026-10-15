import Foundation

struct ProjectSourceTextRequest: Hashable {
  var sourceID: UUID
  var reference: String?
  var retry: Int
}
