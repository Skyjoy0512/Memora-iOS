import Foundation

struct OccupationCategory: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var icon: MemoraIcon
  var sortOrder: Int
}
